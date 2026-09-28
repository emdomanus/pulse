--!strict
--!optimize 2

local PlaybackTraversalTypes =
	require(script.Parent.Parent.Parent.Parent.Parent.components.playback.shared.playbackTraversal)
local ClockDriverVocabulary =
	require(script.Parent.Parent.Parent.Parent.Parent.Parent.common.clockDriver.shared.clockDriverVocabulary)

local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.Parent.def.playback.shared.playbackDefinitions)
local PlaybackVocabulary =
	require(script.Parent.Parent.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.Parent.components.playback.shared.playback)
local ProviderClockTypes =
	require(script.Parent.Parent.Parent.Parent.Parent.ports.components.clock.shared.providerClock)
local ClockDriverCommandsTypes =
	require(script.Parent.Parent.Parent.Parent.Parent.ports.managers.clockDriver.shared.clockDriverCommands)

type AddressMode = PlaybackVocabulary.AddressMode
type LoopChange = PlaybackDefinitions.LoopChange
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
type ClockDriverCommands<AttachmentT> = ClockDriverCommandsTypes.ClockDriverCommands<AttachmentT>
type TraversalForecast = PlaybackTraversalTypes.TraversalForecast
type DriverDiscontinuityMode = ClockDriverVocabulary.DriverDiscontinuityMode

export type DrivenPlayback = {
	read play: (self: DrivenPlayback) -> DrivenPlayback,
	read pause: (self: DrivenPlayback) -> (),
	read resume: (self: DrivenPlayback) -> (),
	read setPlaybackSpeed: (self: DrivenPlayback, speed: number) -> (),
	read getPlaybackSpeed: (self: DrivenPlayback) -> number,
	read seek: (self: DrivenPlayback, address: SequenceAddress, mode: AddressMode) -> boolean,
	read getPosition: (self: DrivenPlayback) -> PlaybackPosition,
	read writePositionInto: (self: DrivenPlayback, output: PlaybackPosition) -> (),
	read getStatus: (self: DrivenPlayback) -> Status,
	read addCleanup: (self: DrivenPlayback, cleanup: () -> ()) -> (),
	read cancel: (self: DrivenPlayback, reason: string?) -> (),
	read deconstruct: (self: DrivenPlayback) -> (),
	read onEnded: (self: DrivenPlayback, callback: (completion: Completion) -> ()) -> Release,
	read onLooped: (self: DrivenPlayback, callback: (change: LoopChange) -> ()) -> Release,
	read isAlive: (self: DrivenPlayback) -> boolean,
	read getCompletion: (self: DrivenPlayback) -> Completion?,
	read detach: (self: DrivenPlayback) -> Playback,
}

export type DrivenPlaybackImpl = DrivenPlayback & {
	_clockDriverCommands: ClockDriverCommands<DrivenPlayback>,
	_playback: PlaybackDriven,
	_discontinuityMode: DriverDiscontinuityMode,
	_attached: boolean,
	_active: boolean,
	_scheduledId: ScheduledTaskId?,
	_scheduledSourcePosition: number?,
	_scheduledDirection: TraversalDirection?,
	_taskGeneration: number,
	_forecast: TraversalForecast,
	_reachedSample: TimeSample?,
	_endedRelease: Release?,
}

return {}
