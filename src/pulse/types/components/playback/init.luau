--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local SequenceTypes = require(script.Parent.sequence)

type AddressMode = DefTypes.AddressMode
type Completion = DefTypes.Completion
type LoopChange = DefTypes.LoopChange
type PlaybackControl = DefTypes.PlaybackControl
type PlaybackPosition = DefTypes.PlaybackPosition
type Release = DefTypes.Release
type SequenceAddress = DefTypes.SequenceAddress
type StoredSequence = SequenceTypes.StoredSequence
type Status = DefTypes.Status
type TerminalStatus = DefTypes.TerminalStatus
type TimeSample = DefTypes.TimeSample
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
	initialMode: AddressMode?,
}

export type EvaluateOperation = {
	kind: "evaluate",
	sample: TimeSample,
}

export type PauseOperation = {
	kind: "pause",
}

export type ResumeOperation = {
	kind: "resume",
}

export type SpeedOperation = {
	kind: "speed",
	speed: number,
}

export type SeekOperation = {
	kind: "seek",
	address: SequenceAddress,
	mode: AddressMode,
}

export type Operation = EvaluateOperation | PauseOperation | ResumeOperation | SpeedOperation | SeekOperation

export type TerminalRequest = {
	status: TerminalStatus,
	reason: string?,
}

export type BoundaryState = "before" | "after" | "forwardJoinPending" | "backwardJoinPending"

export type TraversalForecast = {
	phaseRequired: boolean,
	sourceBoundary: number?,
	sourceDirection: TraversalDirection?,
}

export type Playback = PlaybackControl & {
	play: (self: Playback, sample: TimeSample) -> Playback,
	evaluate: (self: Playback, sample: TimeSample) -> boolean,
	onEnded: (self: Playback, callback: EndedCallback) -> Release,
	onLooped: (self: Playback, callback: LoopedCallback) -> Release,
	isAlive: (self: Playback) -> boolean,
	getCompletion: (self: Playback) -> Completion?,
}

export type PlaybackImpl = Playback & {
	_sequence: StoredSequence,
	_context: unknown,
	_status: Status,
	_completion: Completion?,
	_playbackSpeed: number,
	_anchorSource: number,
	_anchorSequence: number,
	_acceptedSample: TimeSample?,
	_resumePending: boolean,
	_position: PlaybackPosition,
	_initialPosition: PlaybackPosition,
	_initialMode: AddressMode,
	_boundaryState: BoundaryState?,
	_direction: TraversalDirection?,
	_cleanup: { () -> () },
	_endedBindings: { EndedBinding },
	_loopedBindings: { LoopedBinding },
	_operations: { Operation },
	_busy: boolean,
	_finishing: boolean,
	_deliveringEnded: boolean,
	_terminalRequest: TerminalRequest?,
	_workCount: number,
}

return {}
