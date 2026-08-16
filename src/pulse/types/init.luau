--!strict
--!optimize 2
--!native

local DefTypes = require(script.def)
local SequenceTypes = require(script.components.sequence)
local PlaybackTypes = require(script.components.playback)
local TemporalAdapterTypes = require(script.managers.temporalAdapter)

export type Release = DefTypes.Release
export type TraversalDirection = DefTypes.TraversalDirection
export type AddressPolicy = DefTypes.AddressPolicy
export type SequenceAddress = DefTypes.SequenceAddress
export type PlaybackPosition = DefTypes.PlaybackPosition
export type LoopChange = DefTypes.LoopChange
export type ActiveStatus = DefTypes.ActiveStatus
export type TerminalStatus = DefTypes.TerminalStatus
export type Status = DefTypes.Status
export type Completion = DefTypes.Completion
export type PlaybackContext = DefTypes.PlaybackContext
export type Event<ContextT> = SequenceTypes.Event<ContextT>
export type Update<ContextT> = SequenceTypes.Update<ContextT>
export type SequenceDefinition<ContextT> = SequenceTypes.SequenceDefinition<ContextT>
export type Sequence<ContextT> = SequenceTypes.Sequence<ContextT>
export type Builder<ContextT> = SequenceTypes.Builder<ContextT>

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
