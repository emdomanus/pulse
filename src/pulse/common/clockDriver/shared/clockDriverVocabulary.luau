--!strict
--!optimize 2

local PlaybackVocabulary = require(script.Parent.Parent.Parent.playback.shared.playbackVocabulary)

type AddressMode = PlaybackVocabulary.AddressMode

export type DriverDiscontinuityMode = AddressMode | "cancel"
export type ClockDriverControlKind =
	"play"
	| "pause"
	| "resume"
	| "speed"
	| "seek"
	| "cleanup"
	| "cancel"
	| "deconstruct"
	| "detach"

return {}
