--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local SequenceTypes = require(script.Parent.sequence)
local TemporalAdapterTypes = require(script.Parent.Parent.managers.temporalAdapter)

type ClockChange = TemporalAdapterTypes.ClockChange
type ClockSample = TemporalAdapterTypes.ClockSample
type Completion = DefTypes.Completion
type LoopChange = DefTypes.LoopChange
type PlaybackContext = DefTypes.PlaybackContext
type PlaybackPosition = DefTypes.PlaybackPosition
type ReachedCallback = TemporalAdapterTypes.ReachedCallback
type Release = DefTypes.Release
type ScheduledTaskId = TemporalAdapterTypes.ScheduledTaskId
type StoredSequence = SequenceTypes.StoredSequence
type SequenceAddress = DefTypes.SequenceAddress
type SequenceBoundary = SequenceTypes.SequenceBoundary
type Status = DefTypes.Status
type TemporalAdapter = TemporalAdapterTypes.TemporalAdapter
type TerminalStatus = DefTypes.TerminalStatus
type TraversalDirection = DefTypes.TraversalDirection

export type EndedCallback = (completion: Completion) -> ()
export type EndedBinding = {
	callback: EndedCallback?,
	active: boolean,
}

export type LoopedCallback = (change: LoopChange) -> ()
export type LoopedBinding = {
	callback: LoopedCallback?,
	active: boolean,
}

export type PlaybackOptions = {
	playbackSpeed: number?,
	position: SequenceAddress?,
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

export type Playback = PlaybackContext & {
	play: (self: Playback) -> Playback,
	onEnded: (self: Playback, callback: EndedCallback) -> Release,
	onLooped: (self: Playback, callback: LoopedCallback) -> Release,
	isAlive: (self: Playback) -> boolean,
	getCompletion: (self: Playback) -> Completion?,
}

export type PlaybackImpl = Playback & TemporalAdapterTypes.PlaybackSink & {
	_sequence: StoredSequence,
	_context: unknown,
	_adapter: TemporalAdapter,
	_status: Status,
	_completion: Completion?,
	_playbackSpeed: number,
	_anchorClock: number,
	_anchorSequence: number,
	_clockRate: number,
	_position: PlaybackPosition,
	_initialPosition: PlaybackPosition,
	_boundaryState: BoundaryState?,
	_direction: TraversalDirection?,
	_scheduledId: ScheduledTaskId?,
	_scheduledDirection: TraversalDirection?,
	_scheduledBoundary: SequenceBoundary?,
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
