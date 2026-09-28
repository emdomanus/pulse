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
	read pause: (self: PlaybackControl) -> (),
	read resume: (self: PlaybackControl) -> (),
	read setPlaybackSpeed: (self: PlaybackControl, speed: number) -> (),
	read getPlaybackSpeed: (self: PlaybackControl) -> number,
	read seek: (self: PlaybackControl, address: SequenceAddress, mode: AddressMode) -> boolean,
	read getPosition: (self: PlaybackControl) -> PlaybackPosition,
	read writePositionInto: (self: PlaybackControl, output: PlaybackPosition) -> (),
	read getStatus: (self: PlaybackControl) -> Status,
	read addCleanup: (self: PlaybackControl, cleanup: () -> ()) -> (),
	read cancel: (self: PlaybackControl, reason: string?) -> (),
	read deconstruct: (self: PlaybackControl) -> (),
}

return {}
