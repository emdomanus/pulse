--!strict
--!optimize 2
--!native

local ClockDriverVocabulary =
	require(script.Parent.Parent.Parent.Parent.common.clockDriver.shared.clockDriverVocabulary)

local DrivenPlaybackTypes =
	require(script.Parent.Parent.Parent.Parent.types.managers.clockDriver.shared.clockDriver.drivenPlayback)
local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.types.def.playback.shared.playbackDefinitions)
local PlaybackVocabulary = require(script.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback.shared.playback)
local ClockDriverCommandsTypes =
	require(script.Parent.Parent.Parent.Parent.types.ports.managers.clockDriver.shared.clockDriverCommands)
local ClockDriverNotifications =
	require(script.Parent.Parent.Parent.Parent.types.managers.clockDriver.shared.clockDriver.clockDriverNotifications)

type DrivenPlayback = DrivenPlaybackTypes.DrivenPlayback
type DrivenPlaybackImpl = DrivenPlaybackTypes.DrivenPlaybackImpl
type Playback = PlaybackTypes.Playback
type PlaybackDriven = PlaybackTypes.PlaybackDriven
type ClockDriverCommands<AttachmentT> = ClockDriverCommandsTypes.ClockDriverCommands<AttachmentT>
type DriverDiscontinuityMode = ClockDriverVocabulary.DriverDiscontinuityMode
type ClockDriverControlKind = ClockDriverVocabulary.ClockDriverControlKind
type ClockDriverControlNotification = ClockDriverNotifications.ClockDriverControlNotification<DrivenPlayback>
type AddressMode = PlaybackVocabulary.AddressMode
type Status = PlaybackVocabulary.Status
type SequenceAddress = PlaybackDefinitions.SequenceAddress
type PlaybackPosition = PlaybackDefinitions.PlaybackPosition
type Completion = PlaybackDefinitions.Completion
type Release = PlaybackDefinitions.Release
type EndedCallback = PlaybackTypes.EndedCallback
type LoopedCallback = PlaybackTypes.LoopedCallback

type DrivenPlaybackModule = {
	new: (
		clockDriverCommands: ClockDriverCommands<DrivenPlayback>,
		playback: PlaybackDriven,
		mode: DriverDiscontinuityMode
	) -> DrivenPlaybackImpl,
}

local function isFinite(value: number): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validateAddressMode(mode: AddressMode): AddressMode
	assert(mode == "skip" or mode == "reconstruct", "Pulse address mode must be 'reconstruct' or 'skip'")
	return mode
end

local function control(self: DrivenPlaybackImpl, operation: ClockDriverControlKind): ClockDriverControlNotification
	local notification: ClockDriverControlNotification = {
		kind = "control" :: "control",
		drivenPlayback = (self :: unknown) :: DrivenPlayback,
		operation = operation,
		result = nil,
	}
	self._clockDriverCommands:submitControl(notification)
	return notification
end

local DrivenPlayback = {}
DrivenPlayback.__index = DrivenPlayback

function DrivenPlayback.new(
	clockDriverCommands: ClockDriverCommands<DrivenPlayback>,
	playback: PlaybackDriven,
	mode: DriverDiscontinuityMode
): DrivenPlaybackImpl
	local drivenPlayback: DrivenPlaybackImpl
	drivenPlayback = (
		setmetatable({
			_clockDriverCommands = clockDriverCommands,
			_playback = playback,
			_discontinuityMode = mode,
			_attached = true,
			_active = false,
			_scheduledId = nil,
			_scheduledSourcePosition = nil,
			_scheduledDirection = nil,
			_taskGeneration = 0,
			_forecast = { phaseRequired = false, sourceBoundary = nil, sourceDirection = nil },
			_reachedSample = nil,
			_endedRelease = nil,
		}, DrivenPlayback) :: unknown
	) :: DrivenPlaybackImpl
	return drivenPlayback
end

function DrivenPlayback.play(self: DrivenPlaybackImpl): DrivenPlayback
	control(self, "play" :: ClockDriverControlKind)
	return self
end

function DrivenPlayback.pause(self: DrivenPlaybackImpl)
	control(self, "pause" :: ClockDriverControlKind)
end

function DrivenPlayback.resume(self: DrivenPlaybackImpl)
	control(self, "resume" :: ClockDriverControlKind)
end

function DrivenPlayback.setPlaybackSpeed(self: DrivenPlaybackImpl, speed: number)
	assert(isFinite(speed), "Pulse playbackSpeed must be finite")
	local notification: ClockDriverControlNotification = {
		kind = "control" :: "control",
		drivenPlayback = (self :: unknown) :: DrivenPlayback,
		operation = "speed" :: ClockDriverControlKind,
		speed = speed,
	}
	self._clockDriverCommands:submitControl(notification)
end

function DrivenPlayback.getPlaybackSpeed(self: DrivenPlaybackImpl): number
	return self._playback:getPlaybackSpeed()
end

function DrivenPlayback.seek(self: DrivenPlaybackImpl, address: SequenceAddress, mode: AddressMode): boolean
	local validatedAddress = self._playback:validateAddress(address)
	local validatedMode: AddressMode = validateAddressMode(mode)
	local notification: ClockDriverControlNotification = {
		kind = "control" :: "control",
		drivenPlayback = (self :: unknown) :: DrivenPlayback,
		operation = "seek" :: ClockDriverControlKind,
		address = validatedAddress,
		mode = validatedMode,
		result = self._attached and self._playback:isAlive(),
	}
	self._clockDriverCommands:submitControl(notification)
	return notification.result == true
end

function DrivenPlayback.getPosition(self: DrivenPlaybackImpl): PlaybackPosition
	return self._playback:getPosition()
end

function DrivenPlayback.writePositionInto(self: DrivenPlaybackImpl, output: PlaybackPosition)
	self._playback:writePositionInto(output)
end

function DrivenPlayback.getStatus(self: DrivenPlaybackImpl): Status
	return self._playback:getStatus()
end

function DrivenPlayback.addCleanup(self: DrivenPlaybackImpl, cleanup: () -> ())
	assert(type(cleanup) == "function", "Pulse cleanup must be a callback")
	self._clockDriverCommands:submitControl({
		kind = "control" :: "control",
		drivenPlayback = (self :: unknown) :: DrivenPlayback,
		operation = "cleanup" :: ClockDriverControlKind,
		cleanup = cleanup,
	})
end

function DrivenPlayback.cancel(self: DrivenPlaybackImpl, reason: string?)
	local notification: ClockDriverControlNotification = {
		kind = "control" :: "control",
		drivenPlayback = (self :: unknown) :: DrivenPlayback,
		operation = "cancel" :: ClockDriverControlKind,
		reason = reason,
	}
	self._clockDriverCommands:submitControl(notification)
end

function DrivenPlayback.deconstruct(self: DrivenPlaybackImpl)
	control(self, "deconstruct" :: ClockDriverControlKind)
end

function DrivenPlayback.onEnded(self: DrivenPlaybackImpl, callback: EndedCallback): Release
	return self._playback:onEnded(callback)
end

function DrivenPlayback.onLooped(self: DrivenPlaybackImpl, callback: LoopedCallback): Release
	return self._playback:onLooped(callback)
end

function DrivenPlayback.isAlive(self: DrivenPlaybackImpl): boolean
	return self._playback:isAlive()
end

function DrivenPlayback.getCompletion(self: DrivenPlaybackImpl): Completion?
	return self._playback:getCompletion()
end

function DrivenPlayback.detach(self: DrivenPlaybackImpl): Playback
	control(self, "detach" :: ClockDriverControlKind)
	return self._playback
end

local module: DrivenPlaybackModule = { new = DrivenPlayback.new }

return module
