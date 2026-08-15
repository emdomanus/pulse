--!strict
--!optimize 2
--!native

export type Release = () -> ()
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

export type DirectionTokens<DirectionTokenT> = {
	forward: DirectionTokenT,
	backward: DirectionTokenT,
}

export type PlaybackAttachment = {
	_onAdapterClockChanged: (
		self: PlaybackAttachment,
		change: ClockChange,
		sample: ClockSample,
		clockSerial: number
	) -> (),
	_onAdapterPhase: (self: PlaybackAttachment, sample: ClockSample, clockSerial: number) -> (),
	_onAdapterDestroyed: (self: PlaybackAttachment, reason: string) -> (),
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

export type ErasedDirectionTokens = {
	forward: unknown,
	backward: unknown,
}

export type ErasedClockReader = {
	read: (self: ErasedClockReader) -> unknown,
	bindToChanged: (
		self: ErasedClockReader,
		callback: RawClockChangedCallback,
		runInitially: boolean?
	) -> Release,
	isDestroyed: (self: ErasedClockReader) -> boolean,
}

export type ErasedClockScheduling = {
	bindToReached: (
		self: ErasedClockScheduling,
		timePosition: number,
		direction: unknown,
		callback: ReachedCallback,
		phase: unknown
	) -> ScheduledTaskId,
	cancel: (self: ErasedClockScheduling, id: ScheduledTaskId) -> boolean,
	rescheduleAt: (self: ErasedClockScheduling, id: ScheduledTaskId, runAt: number, phase: unknown) -> boolean,
	bindPhase: (self: ErasedClockScheduling, phase: unknown, callback: PhaseCallback) -> Release,
}

export type ErasedClock = ErasedClockReader & ErasedClockScheduling

export type TemporalAdapterImpl = TemporalAdapter & {
	_clock: ErasedClock,
	_phase: unknown,
	_directions: ErasedDirectionTokens,
	_destroyed: boolean,
	_attachments: { PlaybackAttachment },
	_updating: { PlaybackAttachment },
	_changedRelease: Release?,
	_phaseRelease: Release?,
	_changedCallback: RawClockChangedCallback,
	_phaseCallback: PhaseCallback,
	_notifications: { AdapterNotification },
	_notifying: boolean,
	_clockSerial: number,
	_latestRevision: number?,
}

local TemporalAdapterTypes = {}

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function TemporalAdapterTypes.assertClockSample(value: unknown): ClockSample
	assert(type(value) == "table", "Pulse clock read must return a table")
	local fields = value :: { [string]: unknown }
	local timePosition = fields.timePosition
	local rate = fields.rate
	local revision = fields.revision
	assert(type(timePosition) == "number" and isFinite(timePosition), "Pulse clock timePosition must be finite")
	assert(type(rate) == "number" and isFinite(rate), "Pulse clock rate must be finite")
	assert(
		revision == nil or (type(revision) == "number" and isFinite(revision)),
		"Pulse clock revision must be finite"
	)
	return {
		timePosition = timePosition,
		rate = rate,
		revision = revision :: number?,
	}
end

function TemporalAdapterTypes.assertClockChange(value: unknown): ClockChange
	assert(type(value) == "table", "Pulse clock change must be a table")
	local fields = value :: { [string]: unknown }
	local kind = fields.kind
	local previous = fields.previousTimePosition
	local current = fields.currentTimePosition
	local discontinuous = fields.discontinuous
	local currentMapping = fields.current
	local revision: number? = nil
	if currentMapping ~= nil then
		assert(type(currentMapping) == "table", "Pulse clock change current mapping must be a table")
		local rawRevision = (currentMapping :: { [string]: unknown }).revision
		assert(
			rawRevision == nil or (type(rawRevision) == "number" and isFinite(rawRevision)),
			"Pulse clock change revision must be finite"
		)
		revision = rawRevision :: number?
	end
	assert(kind == nil or type(kind) == "string", "Pulse clock change kind must be a string")
	assert(
		previous == nil or (type(previous) == "number" and isFinite(previous)),
		"Pulse clock previousTimePosition must be finite"
	)
	assert(type(current) == "number" and isFinite(current), "Pulse clock currentTimePosition must be finite")
	assert(type(discontinuous) == "boolean", "Pulse clock discontinuous must be boolean")
	return {
		kind = kind :: string?,
		previousTimePosition = previous :: number?,
		currentTimePosition = current,
		discontinuous = discontinuous,
		revision = revision,
	}
end

return TemporalAdapterTypes
