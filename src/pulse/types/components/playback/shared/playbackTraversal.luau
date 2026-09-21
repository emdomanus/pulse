--!strict
--!optimize 2

local PlaybackVocabulary = require(script.Parent.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)

type TraversalDirection = PlaybackVocabulary.TraversalDirection

export type TraversalForecast = {
	phaseRequired: boolean,
	sourceBoundary: number?,
	sourceDirection: TraversalDirection?,
}

return {}
