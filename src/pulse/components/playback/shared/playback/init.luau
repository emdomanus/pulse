--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback)
local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence)
local SequenceRuntime = require(script.Parent.Parent.Parent.sequence.shared.sequence.runtime)
local Lifecycle = require(script.lifecycle)
local Runtime = require(script.runtime)
local Traversal = require(script.traversal)

type AddressCause = DefTypes.AddressCause
type AddressMode = DefTypes.AddressMode
type Completion = DefTypes.Completion
type EndedBinding = PlaybackTypes.EndedBinding
type EndedCallback = PlaybackTypes.EndedCallback
type LoopedBinding = PlaybackTypes.LoopedBinding
type LoopedCallback = PlaybackTypes.LoopedCallback
type Playback = PlaybackTypes.Playback
type PlaybackImpl = PlaybackTypes.PlaybackImpl
type PlaybackOptions = PlaybackTypes.PlaybackOptions
type PlaybackPosition = DefTypes.PlaybackPosition
type TraversalForecast = PlaybackTypes.TraversalForecast
type SequenceAddress = DefTypes.SequenceAddress
type Sequence<ContextT> = SequenceTypes.Sequence<ContextT>
type Status = DefTypes.Status
type StoredSequence = SequenceTypes.StoredSequence
type TerminalRequest = PlaybackTypes.TerminalRequest
type TimeSample = DefTypes.TimeSample

type PlaybackModule = {
	new: <ContextT>(sequence: Sequence<ContextT>, context: ContextT, options: PlaybackOptions?) -> Playback,
	_fail: (playback: Playback, reason: string) -> (),
	_getTraversalForecast: (playback: Playback) -> TraversalForecast,
	_validateAddress: (playback: Playback, address: SequenceAddress) -> SequenceAddress,
	_projectSourcePosition: (playback: Playback, sourcePosition: number) -> PlaybackPosition?,
	_acceptSourceSample: (playback: Playback, sample: TimeSample) -> (),
	_getAcceptedSample: (playback: Playback) -> TimeSample?,
}

local Playback = {}
Playback.__index = Playback

local function noopRelease() end

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

local function validateAddressMode(mode: AddressMode): AddressMode
	assert(mode == "reconstruct" or mode == "skip", "Pulse address mode must be 'reconstruct' or 'skip'")
	return mode
end

local function asImpl(playback: Playback): PlaybackImpl
	return (playback :: unknown) :: PlaybackImpl
end

local function ConstructPlayback<ContextT>(sequence: Sequence<ContextT>, context: ContextT, options: PlaybackOptions?): Playback
	local config: PlaybackOptions = options or {}
	local speed = config.playbackSpeed or 1
	local initialMode = validateInitialMode(config.initialMode)
	assert(isFinite(speed), "Pulse playbackSpeed must be finite")
	local storedSequence = (sequence :: unknown) :: StoredSequence
	local initial = SequenceRuntime.validateAddress(storedSequence, config.position or { timePosition = 0 })
	local self: PlaybackImpl = (
		setmetatable({
			_sequence = storedSequence,
			_context = context,
			_status = "idle" :: Status,
			_completion = nil,
			_playbackSpeed = speed,
			_anchorSource = 0,
			_anchorSequence = initial.unwrappedTimePosition,
			_acceptedSample = nil,
			_resumePending = false,
			_position = initial,
			_initialPosition = initial,
			_initialMode = initialMode,
			_boundaryState = nil,
			_direction = nil,
			_cleanup = {},
			_endedBindings = {},
			_loopedBindings = {},
			_operations = {},
			_busy = false,
			_finishing = false,
			_deliveringEnded = false,
			_terminalRequest = nil,
			_workCount = 0,
		}, Playback) :: unknown
	) :: PlaybackImpl
	return self
end

function Playback.play(self: PlaybackImpl, sample: TimeSample): Playback
	if self._status ~= "idle" or self._finishing then
		return self
	end
	local accepted = Runtime.copySample(sample)
	self._status = "playing"
	self._acceptedSample = accepted
	self._anchorSource = accepted.position
	self._anchorSequence = self._initialPosition.unwrappedTimePosition
	self._position = self._initialPosition

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
		initialized = Traversal.emitAddress(self, "initial" :: AddressCause, self._initialMode, nil)
	end
	if initialized then
		initialized = Runtime.runSamples(self)
	end
	if initialized then
		Runtime.finalizeAddress(self)
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

function Playback.evaluate(self: PlaybackImpl, sample: TimeSample): boolean
	local accepted = Runtime.copySample(sample)
	if self._status ~= "playing" or self._finishing or self._terminalRequest ~= nil then
		return false
	end
	Runtime.enqueue(self, {
		kind = "evaluate" :: "evaluate",
		sample = accepted,
	})
	return true
end

function Playback.pause(self: PlaybackImpl)
	if self._status == "playing" and not self._finishing and self._terminalRequest == nil then
		Runtime.enqueue(self, {
			kind = "pause" :: "pause",
		})
	end
end

function Playback.resume(self: PlaybackImpl)
	if self._status == "paused" and not self._finishing and self._terminalRequest == nil then
		Runtime.enqueue(self, {
			kind = "resume" :: "resume",
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
		Runtime.enqueue(self, {
			kind = "speed" :: "speed",
			speed = speed,
		})
	end
end

function Playback.getPlaybackSpeed(self: PlaybackImpl): number
	return self._playbackSpeed
end

function Playback.seek(self: PlaybackImpl, address: SequenceAddress, mode: AddressMode): boolean
	local validatedMode = validateAddressMode(mode)
	local validated = SequenceRuntime.validateAddress(self._sequence, address)
	if (self._status ~= "playing" and self._status ~= "paused") or self._finishing or self._terminalRequest ~= nil then
		return false
	end
	Runtime.enqueue(self, {
		kind = "seek" :: "seek",
		address = {
			timePosition = validated.timePosition,
			loopIndex = validated.loopIndex,
		},
		mode = validatedMode :: AddressMode,
	})
	return true
end

function Playback.getPosition(self: PlaybackImpl): PlaybackPosition
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

local function fail(playback: Playback, reason: string)
	Lifecycle.requestTerminal(asImpl(playback), "failed", reason)
end

local function getTraversalForecast(playback: Playback): TraversalForecast
	return Runtime.getTraversalForecast(asImpl(playback))
end

local function validateAddress(playback: Playback, address: SequenceAddress): SequenceAddress
	local validated = SequenceRuntime.validateAddress(asImpl(playback)._sequence, address)
	return {
		timePosition = validated.timePosition,
		loopIndex = validated.loopIndex,
	}
end

local function projectSourcePosition(playback: Playback, sourcePosition: number): PlaybackPosition?
	return Runtime.projectSourcePosition(asImpl(playback), sourcePosition)
end

local function acceptSourceSample(playback: Playback, sample: TimeSample)
	Runtime.acceptSourceSample(asImpl(playback), sample)
end

local function getAcceptedSample(playback: Playback): TimeSample?
	return Runtime.getAcceptedSample(asImpl(playback))
end

local module: PlaybackModule = {
	new = ConstructPlayback,
	_fail = fail,
	_getTraversalForecast = getTraversalForecast,
	_validateAddress = validateAddress,
	_projectSourcePosition = projectSourcePosition,
	_acceptSourceSample = acceptSourceSample,
	_getAcceptedSample = getAcceptedSample,
}

return module
