--!strict
--!optimize 2

local ClockDriverVocabulary =
	require(script.Parent.Parent.Parent.Parent.Parent.common.clockDriver.shared.clockDriverVocabulary)

local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.def.playback.shared.playbackDefinitions)
local PlaybackVocabulary = require(script.Parent.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.components.playback.shared.playback)
local ProviderClockTypes = require(script.Parent.Parent.Parent.Parent.ports.components.clock.shared.providerClock)
local DrivenPlaybackTypes = require(script.drivenPlayback)
local ClockDriverCommandsTypes =
	require(script.Parent.Parent.Parent.Parent.ports.managers.clockDriver.shared.clockDriverCommands)
local ClockDriverNotifications = require(script.clockDriverNotifications)

type AddressMode = PlaybackVocabulary.AddressMode
type Completion = PlaybackDefinitions.Completion
type Playback = PlaybackTypes.Playback
type PlaybackDriven = PlaybackTypes.PlaybackDriven
type PlaybackPosition = PlaybackDefinitions.PlaybackPosition
type Release = PlaybackDefinitions.Release
type SequenceAddress = PlaybackDefinitions.SequenceAddress
type Status = PlaybackVocabulary.Status
type TimeSample = PlaybackDefinitions.TimeSample
type TraversalDirection = PlaybackVocabulary.TraversalDirection
type ScheduledTaskId = ProviderClockTypes.ScheduledTaskId
type DrivenPlayback = DrivenPlaybackTypes.DrivenPlayback
type ClockDriverCommands<AttachmentT> = ClockDriverCommandsTypes.ClockDriverCommands<AttachmentT>
type ClockDriverNotification = ClockDriverNotifications.ClockDriverNotification<DrivenPlayback>
type StoredProviderClock = ProviderClockTypes.StoredProviderClock
type DirectionTokens<DirectionTokenT> = ProviderClockTypes.DirectionTokens<DirectionTokenT>
type RawClockChangedCallback = ProviderClockTypes.RawClockChangedCallback
type PhaseCallback = ProviderClockTypes.PhaseCallback

export type DriverDiscontinuityMode = ClockDriverVocabulary.DriverDiscontinuityMode

export type ClockDriverAttachmentOptions = {
	discontinuityMode: DriverDiscontinuityMode,
}

export type ClockDriver = {
	attach: (self: ClockDriver, playback: Playback, options: ClockDriverAttachmentOptions) -> DrivenPlayback,
	deconstruct: (self: ClockDriver) -> (),
	isDestroyed: (self: ClockDriver) -> boolean,
}

export type ClockDriverImpl = ClockDriver & ClockDriverCommands<DrivenPlayback> & {
	_providerClock: StoredProviderClock,
	_phase: unknown,
	_directions: DirectionTokens<unknown>,
	_destroyed: boolean,
	_drivenPlaybacks: { DrivenPlayback },
	_drivenPlaybackMembership: { [DrivenPlayback]: true },
	_active: { DrivenPlayback },
	_activeMembership: { [DrivenPlayback]: true },
	_phaseDrivenPlaybacks: { DrivenPlayback },
	_phaseMembership: { [DrivenPlayback]: true },
	_changedRelease: Release?,
	_phaseRelease: Release?,
	_changedCallback: RawClockChangedCallback,
	_phaseCallback: PhaseCallback,
	_dispatchDrivenPlaybacks: { DrivenPlayback },
	_notifications: { ClockDriverNotification },
	_notifying: boolean,
	_lastSample: TimeSample,
	_sampleScratch: TimeSample,
}

return {}
