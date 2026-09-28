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
	read timePosition: number,
	read loopIndex: number?,
}

export type PlaybackPosition = {
	timePosition: number,
	loopIndex: number,
	unwrappedTimePosition: number,
}

-- Callback payloads are frozen; writePositionInto still accepts mutable PlaybackPosition.
export type PlaybackPositionSnapshot = {
	read timePosition: number,
	read loopIndex: number,
	read unwrappedTimePosition: number,
}

export type SampleInfo = {
	read position: PlaybackPositionSnapshot,
	read rate: number,
}

export type AddressInfo = {
	read cause: AddressCause,
	read mode: AddressMode,
	read from: PlaybackPositionSnapshot?,
	read target: PlaybackPositionSnapshot,
}

export type LoopChange = {
	read fromLoopIndex: number,
	read toLoopIndex: number,
	read direction: TraversalDirection,
}

export type Completion = {
	read status: TerminalStatus,
	read reason: string?,
}

return {}
