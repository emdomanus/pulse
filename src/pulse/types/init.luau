--!strict
--!optimize 2
--!native

local SequenceTypes = require(script.sequence)
local PlaybackTypes = require(script.playback)
local TemporalAdapterTypes = require(script.temporalAdapter)

export type Release = SequenceTypes.Release
export type TraversalDirection = SequenceTypes.TraversalDirection
export type AddressPolicy = SequenceTypes.AddressPolicy
export type SequenceAddress = SequenceTypes.SequenceAddress
export type PlaybackPosition = SequenceTypes.PlaybackPosition
export type LoopChange = SequenceTypes.LoopChange
export type ActiveStatus = SequenceTypes.ActiveStatus
export type TerminalStatus = SequenceTypes.TerminalStatus
export type Status = SequenceTypes.Status
export type Completion = SequenceTypes.Completion
export type PlaybackContext = SequenceTypes.PlaybackContext
export type Event = SequenceTypes.Event
export type Update = SequenceTypes.Update
export type SequenceDefinition = SequenceTypes.SequenceDefinition
export type Sequence = SequenceTypes.Sequence
export type Builder = SequenceTypes.Builder

export type EndedCallback = PlaybackTypes.EndedCallback
export type LoopedCallback = PlaybackTypes.LoopedCallback
export type PlaybackOptions = PlaybackTypes.PlaybackOptions
export type Playback = PlaybackTypes.Playback

export type ClockSample = TemporalAdapterTypes.ClockSample
export type ClockChange = TemporalAdapterTypes.ClockChange
export type ProviderClock<PhaseInputT, DirectionTokenT> = TemporalAdapterTypes.ProviderClock<
	PhaseInputT,
	DirectionTokenT
>
export type DirectionTokens<DirectionTokenT> = TemporalAdapterTypes.DirectionTokens<DirectionTokenT>
export type TemporalAdapter = TemporalAdapterTypes.TemporalAdapter

return {}
