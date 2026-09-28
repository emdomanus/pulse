--!strict
--!optimize 2

local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.Parent.def.playback.shared.playbackDefinitions)

type Release = PlaybackDefinitions.Release

export type ScheduledTaskId = number
export type RawClockChangedCallback = (change: unknown) -> ()
export type PhaseCallback = (clockDt: number, now: number) -> ()
export type ReachedCallback = (now: number, direction: unknown) -> ()

type ProviderClockReader = {
	read read: (self: ProviderClockReader) -> unknown,
	read bindToChanged: (
		self: ProviderClockReader,
		callback: RawClockChangedCallback,
		runInitially: boolean?
	) -> Release,
	read isDestroyed: (self: ProviderClockReader) -> boolean,
}

type ProviderClockScheduling<PhaseInputT, DirectionTokenT> = {
	read bindToReached: (
		self: ProviderClockScheduling<PhaseInputT, DirectionTokenT>,
		position: number,
		direction: DirectionTokenT,
		callback: ReachedCallback,
		phase: PhaseInputT
	) -> ScheduledTaskId,
	read cancel: (self: ProviderClockScheduling<PhaseInputT, DirectionTokenT>, id: ScheduledTaskId) -> boolean,
	read rescheduleAt: (
		self: ProviderClockScheduling<PhaseInputT, DirectionTokenT>,
		id: ScheduledTaskId,
		runAt: number,
		phase: PhaseInputT
	) -> boolean,
	read bindPhase: (
		self: ProviderClockScheduling<PhaseInputT, DirectionTokenT>,
		phase: PhaseInputT,
		callback: PhaseCallback
	) -> Release,
}

export type ProviderClock<PhaseInputT, DirectionTokenT> =
	ProviderClockReader
	& ProviderClockScheduling<PhaseInputT, DirectionTokenT>

export type StoredProviderClock = ProviderClock<unknown, unknown>

export type DirectionTokens<DirectionTokenT> = {
	forward: DirectionTokenT,
	backward: DirectionTokenT,
}

return {}
