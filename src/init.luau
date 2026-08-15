--!strict
--!optimize 2
--!native

local Pulse = require(script.pulse)

export type Release = Pulse.Release
export type TraversalDirection = Pulse.TraversalDirection
export type AddressPolicy = Pulse.AddressPolicy
export type SequenceAddress = Pulse.SequenceAddress
export type PlaybackPosition = Pulse.PlaybackPosition
export type LoopChange = Pulse.LoopChange
export type ActiveStatus = Pulse.ActiveStatus
export type TerminalStatus = Pulse.TerminalStatus
export type Status = Pulse.Status
export type Completion = Pulse.Completion
export type PlaybackContext = Pulse.PlaybackContext
export type Event = Pulse.Event
export type Update = Pulse.Update
export type SequenceDefinition = Pulse.SequenceDefinition
export type Sequence = Pulse.Sequence
export type Builder = Pulse.Builder
export type EndedCallback = Pulse.EndedCallback
export type LoopedCallback = Pulse.LoopedCallback
export type PlaybackOptions = Pulse.PlaybackOptions
export type Playback = Pulse.Playback
export type ClockSample = Pulse.ClockSample
export type ClockChange = Pulse.ClockChange
export type ProviderClock<PhaseInputT, DirectionTokenT> = Pulse.ProviderClock<PhaseInputT, DirectionTokenT>
export type DirectionTokens<DirectionTokenT> = Pulse.DirectionTokens<DirectionTokenT>
export type TemporalAdapter = Pulse.TemporalAdapter

return Pulse
