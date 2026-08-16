--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)

type Release = DefTypes.Release

export type ScheduledTaskId = number

export type ClockSample = {
	timePosition: number,
	rate: number,
	revision: number?,
}

export type ClockChange = {
	kind: string?,
	previousTimePosition: number?,
	currentTimePosition: number,
	discontinuous: boolean,
	revision: number?,
}

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
		timePosition: number,
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

export type PlaybackSink = {
	_onAdapterClockChanged: (
		self: PlaybackSink,
		change: ClockChange,
		sample: ClockSample,
		clockSerial: number
	) -> (),
	_onAdapterPhase: (self: PlaybackSink, sample: ClockSample, clockSerial: number) -> (),
	_onAdapterDestroyed: (self: PlaybackSink, reason: string) -> (),
}

export type ClockNotification = {
	kind: "clock",
	change: ClockChange,
	sample: ClockSample,
	clockSerial: number,
}

export type PhaseNotification = {
	kind: "phase",
	sample: ClockSample,
	clockSerial: number,
}

export type AdapterNotification = ClockNotification | PhaseNotification

export type TemporalAdapter = {
	destroy: (self: TemporalAdapter) -> (),
	isDestroyed: (self: TemporalAdapter) -> boolean,
}

export type TemporalAdapterImpl = TemporalAdapter & {
	_clock: StoredClock,
	_phase: unknown,
	_directions: DirectionTokens<unknown>,
	_destroyed: boolean,
	_attachments: { PlaybackSink },
	_attachmentMembership: { [PlaybackSink]: true },
	_updating: { PlaybackSink },
	_updatingMembership: { [PlaybackSink]: true },
	_changedRelease: Release?,
	_phaseRelease: Release?,
	_changedCallback: RawClockChangedCallback,
	_phaseCallback: PhaseCallback,
	_notifications: { AdapterNotification },
	_notifying: boolean,
	_clockSerial: number,
	_latestRevision: number?,
}

return {}
