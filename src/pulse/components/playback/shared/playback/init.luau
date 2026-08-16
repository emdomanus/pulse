--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback)
local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence)
local TemporalAdapterTypes = require(script.Parent.Parent.Parent.Parent.types.managers.temporalAdapter)
local SequenceRuntime = require(script.Parent.Parent.Parent.sequence.shared.sequence.runtime)
local Lifecycle = require(script.lifecycle)
local Runtime = require(script.runtime)

type AddressMode = DefTypes.AddressMode
type Playback = PlaybackTypes.Playback
type PlaybackImpl = PlaybackTypes.PlaybackImpl
type PlaybackOptions = PlaybackTypes.PlaybackOptions
type Sequence<ContextT> = SequenceTypes.Sequence<ContextT>
type Status = DefTypes.Status
type StoredSequence = SequenceTypes.StoredSequence
type TemporalAdapter = TemporalAdapterTypes.TemporalAdapter

type PlaybackModule = {
	new: <ContextT>(
		sequence: Sequence<ContextT>,
		adapter: TemporalAdapter,
		context: ContextT,
		options: PlaybackOptions?
	) -> Playback,
}

local Playback = {}
Playback.__index = Playback
Playback.play = Runtime.play
Playback.pause = Runtime.pause
Playback.resume = Runtime.resume
Playback.setPlaybackSpeed = Runtime.setPlaybackSpeed
Playback.getPlaybackSpeed = Runtime.getPlaybackSpeed
Playback.seek = Runtime.seek
Playback.getPosition = Runtime.getPosition
Playback.getStatus = Runtime.getStatus
Playback.addCleanup = Lifecycle.addCleanup
Playback.cancel = Lifecycle.cancel
Playback.destroy = Lifecycle.destroy
Playback.onEnded = Lifecycle.onEnded
Playback.onLooped = Lifecycle.onLooped
Playback.isAlive = Lifecycle.isAlive
Playback.getCompletion = Lifecycle.getCompletion
Playback._onAdapterClockChanged = Runtime.onAdapterClockChanged
Playback._onAdapterPhase = Runtime.onAdapterPhase
Playback._onAdapterDestroyed = Runtime.onAdapterDestroyed

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
	adapter: TemporalAdapter,
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

local module: PlaybackModule = {
	new = ConstructPlayback,
}

return module
