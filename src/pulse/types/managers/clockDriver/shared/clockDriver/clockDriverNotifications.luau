--!strict
--!optimize 2

local ClockDriverVocabulary =
	require(script.Parent.Parent.Parent.Parent.Parent.Parent.common.clockDriver.shared.clockDriverVocabulary)

local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.Parent.def.playback.shared.playbackDefinitions)
local PlaybackVocabulary =
	require(script.Parent.Parent.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)

type TimeSample = PlaybackDefinitions.TimeSample
type SequenceAddress = PlaybackDefinitions.SequenceAddress
type AddressMode = PlaybackVocabulary.AddressMode

export type ProviderClockChange = {
	kind: string?,
	previousPosition: number?,
	currentPosition: number,
	discontinuous: boolean,
}

type ClockDriverControlKind = ClockDriverVocabulary.ClockDriverControlKind

export type ClockDriverClockNotification = {
	kind: "clock",
	change: ProviderClockChange,
	previousSample: TimeSample,
	sample: TimeSample,
}

export type ClockDriverPhaseNotification = {
	kind: "phase",
	sample: TimeSample,
}

export type ClockDriverReachedNotification<AttachmentT> = {
	kind: "reached",
	drivenPlayback: AttachmentT,
	generation: number,
	direction: unknown,
}

export type ClockDriverControlNotification<AttachmentT> = {
	kind: "control",
	drivenPlayback: AttachmentT,
	operation: ClockDriverControlKind,
	speed: number?,
	address: SequenceAddress?,
	mode: AddressMode?,
	cleanup: (() -> ())?,
	reason: string?,
	result: boolean?,
}

export type ClockDriverNotification<AttachmentT> =
	ClockDriverClockNotification
	| ClockDriverPhaseNotification
	| ClockDriverReachedNotification<AttachmentT>
	| ClockDriverControlNotification<AttachmentT>

return {}
