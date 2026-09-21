--!strict
--!optimize 2

local PlaybackTraversalTypes =
	require(script.Parent.Parent.Parent.Parent.Parent.components.playback.shared.playbackTraversal)
local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.Parent.def.playback.shared.playbackDefinitions)
local PlaybackVocabulary =
	require(script.Parent.Parent.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)

type SequenceAddress = PlaybackDefinitions.SequenceAddress
type PlaybackPosition = PlaybackDefinitions.PlaybackPosition
type TimeSample = PlaybackDefinitions.TimeSample
type TraversalDirection = PlaybackVocabulary.TraversalDirection

type TraversalForecast = PlaybackTraversalTypes.TraversalForecast

export type PlaybackDriver = {
	fail: (self: PlaybackDriver, reason: string) -> (),
	writeTraversalForecastInto: (self: PlaybackDriver, output: TraversalForecast) -> (),
	validateAddress: (self: PlaybackDriver, address: SequenceAddress) -> SequenceAddress,
	projectSourcePosition: (self: PlaybackDriver, sourcePosition: number) -> PlaybackPosition?,
	acceptSourceSample: (self: PlaybackDriver, sample: TimeSample) -> (),
	getAcceptedSample: (self: PlaybackDriver) -> TimeSample?,
}

return {}
