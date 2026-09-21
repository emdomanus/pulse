--!strict
--!optimize 2

local PlaybackDriverTypes = require(script.Parent.Parent.Parent.Parent.ports.components.playback.shared.playbackDriver)
local PlaybackControlTypes =
	require(script.Parent.Parent.Parent.Parent.ports.components.playback.shared.playbackControl)
local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.def.playback.shared.playbackDefinitions)
local SequenceTypes = require(script.Parent.Parent.Parent.sequence.shared.sequence)
local PlaybackVocabulary = require(script.Parent.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)

type AddressMode = PlaybackVocabulary.AddressMode
type Completion = PlaybackDefinitions.Completion
type LoopChange = PlaybackDefinitions.LoopChange
type PlaybackControl = PlaybackControlTypes.PlaybackControl
type PlaybackDriver = PlaybackDriverTypes.PlaybackDriver
type PlaybackPosition = PlaybackDefinitions.PlaybackPosition
type Release = PlaybackDefinitions.Release
type SequenceAddress = PlaybackDefinitions.SequenceAddress
type StoredSequence = SequenceTypes.StoredSequence
type Status = PlaybackVocabulary.Status
type TerminalStatus = PlaybackVocabulary.TerminalStatus
type TimeSample = PlaybackDefinitions.TimeSample
type TraversalDirection = PlaybackVocabulary.TraversalDirection

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
	position: number,
	rate: number,
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
	target: PlaybackPosition,
	mode: AddressMode,
}

export type Operation = EvaluateOperation | PauseOperation | ResumeOperation | SpeedOperation | SeekOperation

export type TerminalRequest = {
	status: TerminalStatus,
	reason: string?,
}

export type BoundaryState = "before" | "after" | "forwardJoinPending" | "backwardJoinPending"

export type Playback = PlaybackControl & {
	play: (self: Playback, sample: TimeSample) -> Playback,
	evaluate: (self: Playback, sample: TimeSample) -> boolean,
	onEnded: (self: Playback, callback: EndedCallback) -> Release,
	onLooped: (self: Playback, callback: LoopedCallback) -> Release,
	isAlive: (self: Playback) -> boolean,
	getCompletion: (self: Playback) -> Completion?,
}

export type PlaybackDriven = Playback & PlaybackDriver

export type PlaybackImpl = PlaybackDriven & {
	_sequence: StoredSequence,
	_context: unknown,
	_status: Status,
	_completion: Completion?,
	_playbackSpeed: number,
	_anchorSource: number,
	_anchorSequence: number,
	_acceptedSourcePosition: number?,
	_acceptedSourceRate: number?,
	_resumePending: boolean,
	_position: PlaybackPosition,
	_forecastBoundary: PlaybackPosition,
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
