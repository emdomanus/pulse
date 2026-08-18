--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local PlaybackTypes = require(script.Parent.Parent.components.playback)

type AddressMode = DefTypes.AddressMode
type Completion = DefTypes.Completion
type LoopChange = DefTypes.LoopChange
type Playback = PlaybackTypes.Playback
type PlaybackPosition = DefTypes.PlaybackPosition
type Release = DefTypes.Release
type SequenceAddress = DefTypes.SequenceAddress
type Status = DefTypes.Status

export type ScheduledTaskId = number
export type DriverDiscontinuityMode = AddressMode | "cancel"

export type RawClockChangedCallback = (change: unknown) -> ()
export type PhaseCallback = (clockDt: number, now: number) -> ()
export type ReachedCallback = (now: number, direction: unknown) -> ()

type ProviderClockReader = {
	read: (self: ProviderClockReader) -> unknown,
	bindToChanged: (
		self: ProviderClockReader,
		callback: RawClockChangedCallback,
		runInitially: boolean?
	) -> Release,
	isDestroyed: (self: ProviderClockReader) -> boolean,
}

type ProviderClockScheduling<PhaseInputT, DirectionTokenT> = {
	bindToReached: (
		self: ProviderClockScheduling<PhaseInputT, DirectionTokenT>,
		position: number,
		direction: DirectionTokenT,
		callback: ReachedCallback,
		phase: PhaseInputT
	) -> ScheduledTaskId,
	cancel: (self: ProviderClockScheduling<PhaseInputT, DirectionTokenT>, id: ScheduledTaskId) -> boolean,
	rescheduleAt: (
		self: ProviderClockScheduling<PhaseInputT, DirectionTokenT>,
		id: ScheduledTaskId,
		runAt: number,
		phase: PhaseInputT
	) -> boolean,
	bindPhase: (
		self: ProviderClockScheduling<PhaseInputT, DirectionTokenT>,
		phase: PhaseInputT,
		callback: PhaseCallback
	) -> Release,
}

export type ProviderClock<PhaseInputT, DirectionTokenT> =
	ProviderClockReader
	& ProviderClockScheduling<PhaseInputT, DirectionTokenT>

export type StoredClock = ProviderClock<unknown, unknown>

export type DirectionTokens<DirectionTokenT> = {
	forward: DirectionTokenT,
	backward: DirectionTokenT,
}

export type ClockDriverAttachmentOptions = {
	discontinuityMode: DriverDiscontinuityMode,
}

export type DrivenPlayback = {
	play: (self: DrivenPlayback) -> DrivenPlayback,
	pause: (self: DrivenPlayback) -> (),
	resume: (self: DrivenPlayback) -> (),
	setPlaybackSpeed: (self: DrivenPlayback, speed: number) -> (),
	getPlaybackSpeed: (self: DrivenPlayback) -> number,
	seek: (self: DrivenPlayback, address: SequenceAddress, mode: AddressMode) -> boolean,
	getPosition: (self: DrivenPlayback) -> PlaybackPosition,
	getStatus: (self: DrivenPlayback) -> Status,
	addCleanup: (self: DrivenPlayback, cleanup: () -> ()) -> (),
	cancel: (self: DrivenPlayback, reason: string?) -> (),
	destroy: (self: DrivenPlayback) -> (),
	onEnded: (self: DrivenPlayback, callback: (completion: Completion) -> ()) -> Release,
	onLooped: (self: DrivenPlayback, callback: (change: LoopChange) -> ()) -> Release,
	isAlive: (self: DrivenPlayback) -> boolean,
	getCompletion: (self: DrivenPlayback) -> Completion?,
	detach: (self: DrivenPlayback) -> Playback,
}

export type ClockDriver = {
	attach: (self: ClockDriver, playback: Playback, options: ClockDriverAttachmentOptions) -> DrivenPlayback,
	destroy: (self: ClockDriver) -> (),
	isDestroyed: (self: ClockDriver) -> boolean,
}

return {}
