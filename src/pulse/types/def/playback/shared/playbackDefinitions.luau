--!strict
--!optimize 2

local PlaybackVocabulary = require(script.Parent.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)

type TraversalDirection = PlaybackVocabulary.TraversalDirection
type AddressMode = PlaybackVocabulary.AddressMode
type AddressCause = PlaybackVocabulary.AddressCause
type TerminalStatus = PlaybackVocabulary.TerminalStatus

export type Release = () -> ()

export type TimeSample = {
	position: number,
	rate: number,
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

export type SampleInfo = {
	position: PlaybackPosition,
	rate: number,
}

export type AddressInfo = {
	cause: AddressCause,
	mode: AddressMode,
	from: PlaybackPosition?,
	target: PlaybackPosition,
}

export type LoopChange = {
	fromLoopIndex: number,
	toLoopIndex: number,
	direction: TraversalDirection,
}

export type Completion = {
	status: TerminalStatus,
	reason: string?,
}

return {}
