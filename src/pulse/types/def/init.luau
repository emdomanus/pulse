--!strict
--!optimize 2
--!native

export type Release = () -> ()
export type ScheduledTaskId = number

export type ClockSample = {
	timePosition: number,
	rate: number,
}

export type ClockChange = {
	previousTimePosition: number?,
	currentTimePosition: number,
	discontinuous: boolean,
}

export type ClockChangedCallback = (change: ClockChange) -> ()
export type PhaseCallback = (clockDt: number, now: number) -> ()
export type ReachedCallback<DirectionT> = (now: number, direction: DirectionT) -> ()
type RawClockChangedCallback = (change: unknown) -> ()

export type ClockDirections<DirectionT> = {
	forward: DirectionT,
	backward: DirectionT,
}

-- Luau record returns are closed. The raw provider seam stays unknown so a
-- conforming clock may return richer provider-owned samples and changes.
-- Pulse validates both values immediately with the guards below.
type ClockReader = {
	read: (self: ClockReader) -> unknown,
	bindToChanged: (self: ClockReader, callback: RawClockChangedCallback, runInitially: boolean?) -> Release,
	isDestroyed: (self: ClockReader) -> boolean,
}

type ClockScheduling<PhaseT, DirectionT> = {
	bindToReached: (
		self: ClockScheduling<PhaseT, DirectionT>,
		timePosition: number,
		direction: DirectionT,
		callback: ReachedCallback<DirectionT>,
		phase: PhaseT
	) -> ScheduledTaskId,
	cancel: (self: ClockScheduling<PhaseT, DirectionT>, id: ScheduledTaskId) -> boolean,
	rescheduleAt: (
		self: ClockScheduling<PhaseT, DirectionT>,
		id: ScheduledTaskId,
		runAt: number,
		phase: PhaseT
	) -> boolean,
	bindPhase: (self: ClockScheduling<PhaseT, DirectionT>, phase: PhaseT, callback: PhaseCallback) -> Release,
}

export type Clock<PhaseT, DirectionT> = ClockReader & ClockScheduling<PhaseT, DirectionT>

export type RealTimeScheduler = {
	delay: (self: RealTimeScheduler, seconds: number, callback: () -> ()) -> Release,
}

export type RuntimeConfig = {
	realTimeScheduler: RealTimeScheduler?,
}

export type SequenceAddress = {
	timePosition: number,
	loopIndex: number?,
}

export type PlaybackPosition = {
	timePosition: number,
	loopIndex: number,
	unwrappedTimePosition: number,
}

export type TraversalDirection = "forward" | "backward"
export type AddressDirection = TraversalDirection | "stationary"

export type LoopChange = {
	fromLoopIndex: number,
	toLoopIndex: number,
	direction: TraversalDirection,
}

export type Params = { [string]: unknown }
export type StepId = string | number

export type ActiveStatus = "idle" | "playing" | "paused"
export type TerminalStatus = "completed" | "stopped" | "cancelled" | "destroyed" | "failed"
export type Status = ActiveStatus | TerminalStatus

export type Completion = {
	status: TerminalStatus,
	reason: string?,
	error: unknown?,
}

export type AddressPolicy = "cancel" | "skip" | "rebuild"
export type AddressCause = "initial" | "manualSeek" | "clockDiscontinuity"
export type StepChangeCause = "manual" | "event" | "rebuild"

local DefTypes = {}

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function DefTypes.assertClockSample(value: unknown): ClockSample
	assert(type(value) == "table", "Pulse clock read must return a table")
	local fields = value :: { [string]: unknown }
	local timePosition = fields.timePosition
	local rate = fields.rate
	assert(type(timePosition) == "number" and isFinite(timePosition), "Pulse clock timePosition must be finite")
	assert(type(rate) == "number" and isFinite(rate), "Pulse clock rate must be finite")
	return {
		timePosition = timePosition,
		rate = rate,
	}
end

function DefTypes.assertClockChange(value: unknown): ClockChange
	assert(type(value) == "table", "Pulse clock change must be a table")
	local fields = value :: { [string]: unknown }
	local previous = fields.previousTimePosition
	local current = fields.currentTimePosition
	local discontinuous = fields.discontinuous
	assert(previous == nil or type(previous) == "number", "Pulse clock previousTimePosition must be numeric")
	assert(type(current) == "number" and isFinite(current), "Pulse clock currentTimePosition must be finite")
	assert(type(discontinuous) == "boolean", "Pulse clock discontinuous must be boolean")

	local previousTimePosition: number? = nil
	if previous ~= nil then
		assert(isFinite(previous :: number), "Pulse clock previousTimePosition must be finite")
		previousTimePosition = previous :: number
	end

	return {
		previousTimePosition = previousTimePosition,
		currentTimePosition = current,
		discontinuous = discontinuous,
	}
end

return DefTypes
