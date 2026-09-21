--!strict
--!optimize 2

local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.Parent.def.playback.shared.playbackDefinitions)
local PlaybackVocabulary =
	require(script.Parent.Parent.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)

type SequenceAddress = PlaybackDefinitions.SequenceAddress
type PlaybackPosition = PlaybackDefinitions.PlaybackPosition
type Status = PlaybackVocabulary.Status
type AddressMode = PlaybackVocabulary.AddressMode

export type PlaybackControl = {
	pause: (self: PlaybackControl) -> (),
	resume: (self: PlaybackControl) -> (),
	setPlaybackSpeed: (self: PlaybackControl, speed: number) -> (),
	getPlaybackSpeed: (self: PlaybackControl) -> number,
	seek: (self: PlaybackControl, address: SequenceAddress, mode: AddressMode) -> boolean,
	getPosition: (self: PlaybackControl) -> PlaybackPosition,
	writePositionInto: (self: PlaybackControl, output: PlaybackPosition) -> (),
	getStatus: (self: PlaybackControl) -> Status,
	addCleanup: (self: PlaybackControl, cleanup: () -> ()) -> (),
	cancel: (self: PlaybackControl, reason: string?) -> (),
	deconstruct: (self: PlaybackControl) -> (),
}

return {}
