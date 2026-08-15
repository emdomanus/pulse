--!strict
--!optimize 2
--!native

local SequenceTypes = require(script.Parent.sequence)
local TemporalAdapterTypes = require(script.Parent.temporalAdapter)

export type Release = SequenceTypes.Release
export type TraversalDirection = SequenceTypes.TraversalDirection
export type AddressPolicy = SequenceTypes.AddressPolicy
export type SequenceAddress = SequenceTypes.SequenceAddress
export type PlaybackPosition = SequenceTypes.PlaybackPosition
export type LoopChange = SequenceTypes.LoopChange
export type ActiveStatus = SequenceTypes.ActiveStatus
export type TerminalStatus = SequenceTypes.TerminalStatus
export type Status = SequenceTypes.Status
export type Completion = SequenceTypes.Completion
export type PlaybackContext = SequenceTypes.PlaybackContext
export type Sequence = SequenceTypes.Sequence
export type TemporalAdapter = TemporalAdapterTypes.TemporalAdapter
export type ClockSample = TemporalAdapterTypes.ClockSample
export type ClockChange = TemporalAdapterTypes.ClockChange
export type ScheduledTaskId = TemporalAdapterTypes.ScheduledTaskId
export type ReachedCallback = TemporalAdapterTypes.ReachedCallback

export type EndedCallback = (completion: Completion) -> ()
export type LoopedCallback = (change: LoopChange) -> ()

export type Playback = PlaybackContext & {
	play: (self: Playback) -> Playback,
	onEnded: (self: Playback, callback: EndedCallback) -> Release,
	onLooped: (self: Playback, callback: LoopedCallback) -> Release,
	isAlive: (self: Playback) -> boolean,
	getCompletion: (self: Playback) -> Completion?,
}

export type PlaybackOptions = {
	playbackSpeed: number?,
	position: SequenceAddress?,
}

export type EndedBinding = {
	callback: EndedCallback?,
	active: boolean,
}

export type LoopedBinding = {
	callback: LoopedCallback?,
	active: boolean,
}

export type ClockChangeOperation = {
	kind: "clockChange",
	change: ClockChange,
	sample: ClockSample,
	clockSerial: number,
}

export type PhaseOperation = {
	kind: "phase",
	sample: ClockSample,
	clockSerial: number,
}

export type ReachedOperation = {
	kind: "reached",
	sample: ClockSample,
	clockSerial: number,
}

export type PauseOperation = {
	kind: "pause",
	sample: ClockSample,
	clockSerial: number,
}

export type ResumeOperation = {
	kind: "resume",
	sample: ClockSample,
	clockSerial: number,
}

export type SpeedOperation = {
	kind: "speed",
	speed: number,
	sample: ClockSample,
	clockSerial: number,
}

export type SeekOperation = {
	kind: "seek",
	address: SequenceAddress,
	sample: ClockSample,
	clockSerial: number,
}

export type Operation =
	ClockChangeOperation
	| PhaseOperation
	| ReachedOperation
	| PauseOperation
	| ResumeOperation
	| SpeedOperation
	| SeekOperation

export type TerminalRequest = {
	status: TerminalStatus,
	reason: string?,
}

export type BoundaryState = "before" | "after"

export type PlaybackImpl = Playback & TemporalAdapterTypes.PlaybackAttachment & {
	_sequence: Sequence,
	_adapter: TemporalAdapter,
	_status: Status,
	_completion: Completion?,
	_playbackSpeed: number,
	_anchorClock: number,
	_anchorSequence: number,
	_clockRate: number,
	_position: number,
	_initialPosition: number,
	_boundaryState: BoundaryState?,
	_direction: TraversalDirection?,
	_scheduledId: ScheduledTaskId?,
	_scheduledDirection: TraversalDirection?,
	_scheduledBoundary: number?,
	_attached: boolean,
	_updating: boolean,
	_updateCursor: number,
	_cleanup: { () -> () },
	_endedBindings: { EndedBinding },
	_loopedBindings: { LoopedBinding },
	_operations: { Operation },
	_busy: boolean,
	_finishing: boolean,
	_deliveringEnded: boolean,
	_terminalRequest: TerminalRequest?,
	_reachedCallback: ReachedCallback,
	_workCount: number,
	_appliedClockSerial: number,
}

return {}
