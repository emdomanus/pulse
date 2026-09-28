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
	read fail: (self: PlaybackDriver, reason: string) -> (),
	read writeTraversalForecastInto: (self: PlaybackDriver, output: TraversalForecast) -> (),
	read validateAddress: (self: PlaybackDriver, address: SequenceAddress) -> SequenceAddress,
	read projectSourcePosition: (self: PlaybackDriver, sourcePosition: number) -> PlaybackPosition?,
	read acceptSourceSample: (self: PlaybackDriver, sample: TimeSample) -> (),
	read getAcceptedSample: (self: PlaybackDriver) -> TimeSample?,
}

return {}
