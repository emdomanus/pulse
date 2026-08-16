--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback)
local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence)
local TemporalAdapterTypes = require(script.Parent.Parent.Parent.Parent.types.managers.temporalAdapter)
local SequenceRuntime = require(script.Parent.Parent.Parent.sequence.shared.sequence.runtime)
local TemporalAdapterModule =
	require(script.Parent.Parent.Parent.Parent.managers.temporalAdapter.shared.temporalAdapter)
local Lifecycle = require(script.lifecycle)
local Runtime = require(script.runtime)
local Traversal = require(script.traversal)

type AddressCause = DefTypes.AddressCause
type AddressMode = DefTypes.AddressMode
type ClockChange = TemporalAdapterTypes.ClockChange
type ClockSample = TemporalAdapterTypes.ClockSample
type Completion = DefTypes.Completion
type EndedBinding = PlaybackTypes.EndedBinding
type EndedCallback = PlaybackTypes.EndedCallback
type LoopedBinding = PlaybackTypes.LoopedBinding
type LoopedCallback = PlaybackTypes.LoopedCallback
type Playback = PlaybackTypes.Playback
type PlaybackImpl = PlaybackTypes.PlaybackImpl
type PlaybackOptions = PlaybackTypes.PlaybackOptions
type PlaybackPosition = DefTypes.PlaybackPosition
type PlaybackSink = TemporalAdapterTypes.PlaybackSink
type SequenceAddress = DefTypes.SequenceAddress
type Sequence<ContextT> = SequenceTypes.Sequence<ContextT>
type Status = DefTypes.Status
type StoredSequence = SequenceTypes.StoredSequence
type TemporalAdapterType = TemporalAdapterTypes.TemporalAdapter
type TerminalRequest = PlaybackTypes.TerminalRequest

type PlaybackModule = {
	new: <ContextT>(
		sequence: Sequence<ContextT>,
		adapter: TemporalAdapterType,
		context: ContextT,
		options: PlaybackOptions?
	) -> Playback,
}

local Playback = {}
Playback.__index = Playback

local function noopRelease() end

local function asPlaybackSink(self: PlaybackImpl): PlaybackSink
	return self
end

local function publicPosition(position: PlaybackPosition): PlaybackPosition
	return {
		timePosition = position.timePosition,
		loopIndex = position.loopIndex,
		unwrappedTimePosition = position.unwrappedTimePosition,
	}
end

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function validateInitialMode(mode: AddressMode?): AddressMode
	local resolved: AddressMode = if mode == nil then "reconstruct" :: AddressMode else mode
	assert(resolved == "reconstruct" or resolved == "skip", "Pulse initialMode must be 'reconstruct' or 'skip'")
	return resolved
end

local function ConstructPlayback<ContextT>(
	sequence: Sequence<ContextT>,
	adapter: TemporalAdapterType,
	context: ContextT,
	options: PlaybackOptions?
): Playback
	local config: PlaybackOptions = options or {}
	local speed = config.playbackSpeed or 1
	local initialMode = validateInitialMode(config.initialMode)
	assert(isFinite(speed), "Pulse playbackSpeed must be finite")
	local storedSequence = (sequence :: unknown) :: StoredSequence
	local initial = SequenceRuntime.validateAddress(storedSequence, config.position or { timePosition = 0 })
	local self: PlaybackImpl
	local function reachedCallback(_now: number, _direction: unknown)
		Runtime.onReached(self)
	end
	self = (
		setmetatable({
			_sequence = storedSequence,
			_context = context,
			_adapter = adapter,
			_status = "idle" :: Status,
			_completion = nil,
			_playbackSpeed = speed,
			_anchorClock = 0,
			_anchorSequence = initial.unwrappedTimePosition,
			_clockRate = 0,
			_position = initial,
			_initialPosition = initial,
			_initialMode = initialMode,
			_boundaryState = nil,
			_direction = nil,
			_scheduledId = nil,
			_scheduledDirection = nil,
			_scheduledBoundary = nil,
			_attached = false,
			_updating = false,
			_updateCursor = initial.unwrappedTimePosition,
			_cleanup = {},
			_endedBindings = {},
			_loopedBindings = {},
			_operations = {},
			_busy = false,
			_finishing = false,
			_deliveringEnded = false,
			_terminalRequest = nil,
			_reachedCallback = reachedCallback,
			_workCount = 0,
			_appliedClockSerial = 0,
		}, Playback) :: unknown
	) :: PlaybackImpl
	return self
end

function Playback.play(self: PlaybackImpl): Playback
	if self._status ~= "idle" or self._finishing then
		return self
	end
	local sample, clockSerial = TemporalAdapterModule._snapshot(self._adapter)
	if sample == nil then
		Lifecycle.finish(self, "failed", "clockReadFailed")
		return self
	end
	self._status = "playing"
	self._anchorClock = sample.timePosition
	self._anchorSequence = self._initialPosition.unwrappedTimePosition
	self._clockRate = sample.rate
	self._appliedClockSerial = clockSerial
	self._position = self._initialPosition
	if not TemporalAdapterModule._attach(self._adapter, asPlaybackSink(self)) then
		Lifecycle.finish(self, "failed", "adapterAttachFailed")
		return self
	end
	self._attached = true

	self._busy = true
	self._workCount = 0
	local initialized: boolean
	if self._initialMode == "reconstruct" then
		initialized = Traversal.reconstructTo(self, self._initialPosition, false)
	else
		initialized = Traversal.beginGeneration(self, self._initialPosition, false)
		if initialized then
			Traversal.placeWithoutTraversal(self, self._initialPosition, Runtime.desiredDirection(self))
		end
	end
	if initialized then
		Traversal.emitAddress(self, "initial" :: AddressCause, self._initialMode, nil)
	end
	if self._terminalRequest == nil and self._sequence:getDuration() == 0 then
		Lifecycle.requestTerminal(self, "completed", nil)
	end
	if self._terminalRequest == nil then
		Runtime.reanchor(self, sample)
		Runtime.refreshOwnership(self, false)
	end
	local terminal: TerminalRequest? = self._terminalRequest
	self._terminalRequest = nil
	self._busy = false
	if terminal ~= nil then
		Lifecycle.finish(self, terminal.status, terminal.reason)
	else
		Runtime.drainOperations(self)
	end
	return self
end

function Playback.pause(self: PlaybackImpl)
	if self._status ~= "playing" or self._finishing or self._terminalRequest ~= nil then
		return
	end
	local sample, clockSerial = Runtime.snapshotClock(self)
	if sample ~= nil then
		Runtime.enqueue(self, {
			kind = "pause",
			sample = sample,
			clockSerial = clockSerial,
		})
	end
end

function Playback.resume(self: PlaybackImpl)
	if self._status ~= "paused" or self._finishing or self._terminalRequest ~= nil then
		return
	end
	local sample, clockSerial = Runtime.snapshotClock(self)
	if sample ~= nil then
		Runtime.enqueue(self, {
			kind = "resume",
			sample = sample,
			clockSerial = clockSerial,
		})
	end
end

function Playback.setPlaybackSpeed(self: PlaybackImpl, speed: number)
	assert(isFinite(speed), "Pulse playbackSpeed must be finite")
	if
		(self._status == "playing" or self._status == "paused")
		and not self._finishing
		and self._terminalRequest == nil
	then
		local sample, clockSerial = Runtime.snapshotClock(self)
		if sample ~= nil then
			Runtime.enqueue(self, {
				kind = "speed",
				speed = speed,
				sample = sample,
				clockSerial = clockSerial,
			})
		end
	end
end

function Playback.getPlaybackSpeed(self: PlaybackImpl): number
	return self._playbackSpeed
end

function Playback.seek(self: PlaybackImpl, address: SequenceAddress): boolean
	local validated = SequenceRuntime.validateAddress(self._sequence, address)
	if self._status == "idle" or self._completion ~= nil or self._finishing or self._terminalRequest ~= nil then
		return false
	end
	local sample, clockSerial = Runtime.snapshotClock(self)
	if sample == nil then
		return false
	end
	Runtime.enqueue(self, {
		kind = "seek",
		address = {
			timePosition = validated.timePosition,
			loopIndex = validated.loopIndex,
		},
		sample = sample,
		clockSerial = clockSerial,
	})
	return true
end

function Playback.getPosition(self: PlaybackImpl): PlaybackPosition
	if self._status == "playing" and not self._busy and not self._finishing then
		local sample, clockSerial = TemporalAdapterModule._snapshot(self._adapter)
		if sample == nil then
			Lifecycle.requestTerminal(self, "failed", "clockReadFailed")
		elseif clockSerial > self._appliedClockSerial then
			return publicPosition(self._position)
		else
			local target = Runtime.derivePosition(self, sample.timePosition)
			if target ~= nil then
				if target == self._position.unwrappedTimePosition then
					return publicPosition(self._position)
				end
				local ok, position = pcall(SequenceRuntime.positionAt, self._sequence, target)
				if ok then
					return position
				end
			end
			Lifecycle.requestTerminal(self, "failed", "numericOverflow")
		end
	end
	return publicPosition(self._position)
end

function Playback.getStatus(self: PlaybackImpl): Status
	return self._status
end

function Playback.addCleanup(self: PlaybackImpl, cleanup: () -> ())
	assert(type(cleanup) == "function", "Pulse cleanup must be a callback")
	if self._completion ~= nil then
		if self._finishing then
			return
		end
		self._finishing = true
		pcall(cleanup)
		self._finishing = false
		return
	end
	table.insert(self._cleanup, cleanup)
end

function Playback.cancel(self: PlaybackImpl, reason: string?)
	Lifecycle.requestTerminal(self, "cancelled", reason)
end

function Playback.destroy(self: PlaybackImpl)
	if self._completion ~= nil then
		self._endedBindings = {}
		self._loopedBindings = {}
		return
	end
	Lifecycle.requestTerminal(self, "destroyed", nil)
end

function Playback.onEnded(self: PlaybackImpl, callback: EndedCallback): () -> ()
	local completion = self._completion
	if completion ~= nil then
		if self._deliveringEnded then
			return noopRelease
		end
		self._deliveringEnded = true
		pcall(callback, completion)
		self._deliveringEnded = false
		return noopRelease
	end
	local binding: EndedBinding = {
		callback = callback,
		active = true,
	}
	table.insert(self._endedBindings, binding)
	return function()
		if not binding.active then
			return
		end
		binding.active = false
		binding.callback = nil
		for index, candidate in self._endedBindings do
			if candidate == binding then
				table.remove(self._endedBindings, index)
				break
			end
		end
	end
end

function Playback.onLooped(self: PlaybackImpl, callback: LoopedCallback): () -> ()
	if self._completion ~= nil or self._finishing then
		return noopRelease
	end
	local binding: LoopedBinding = {
		callback = callback,
		active = true,
	}
	table.insert(self._loopedBindings, binding)
	return function()
		if not binding.active then
			return
		end
		binding.active = false
		binding.callback = nil
		for index, candidate in self._loopedBindings do
			if candidate == binding then
				table.remove(self._loopedBindings, index)
				break
			end
		end
	end
end

function Playback.isAlive(self: PlaybackImpl): boolean
	return self._completion == nil
end

function Playback.getCompletion(self: PlaybackImpl): Completion?
	return self._completion
end

function Playback._onAdapterClockChanged(
	self: PlaybackImpl,
	change: ClockChange,
	sample: ClockSample,
	clockSerial: number
)
	Runtime.enqueue(self, {
		kind = "clockChange",
		change = change,
		sample = sample,
		clockSerial = clockSerial,
	})
end

function Playback._onAdapterPhase(self: PlaybackImpl, sample: ClockSample, clockSerial: number)
	Runtime.enqueue(self, {
		kind = "phase",
		sample = sample,
		clockSerial = clockSerial,
	})
end

function Playback._onAdapterDestroyed(self: PlaybackImpl, reason: string)
	Lifecycle.requestTerminal(self, "failed", reason)
end

local module: PlaybackModule = {
	new = ConstructPlayback,
}

return module
