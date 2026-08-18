--!strict
--!optimize 2
--!native

local Pulse = require(script.pulse)

export type Release = Pulse.Release
export type TraversalDirection = Pulse.TraversalDirection
export type AddressMode = Pulse.AddressMode
export type AddressCause = Pulse.AddressCause
export type TimeSample = Pulse.TimeSample
export type SequenceAddress = Pulse.SequenceAddress
export type PlaybackPosition = Pulse.PlaybackPosition
export type SampleInfo = Pulse.SampleInfo
export type AddressInfo = Pulse.AddressInfo
export type LoopChange = Pulse.LoopChange
export type ActiveStatus = Pulse.ActiveStatus
export type TerminalStatus = Pulse.TerminalStatus
export type Status = Pulse.Status
export type Completion = Pulse.Completion
export type PlaybackControl = Pulse.PlaybackControl
export type Event<ContextT> = Pulse.Event<ContextT>
export type Sample<ContextT> = Pulse.Sample<ContextT>
export type SequenceDefinition<ContextT> = Pulse.SequenceDefinition<ContextT>
export type Sequence<ContextT> = Pulse.Sequence<ContextT>
export type Builder<ContextT> = Pulse.Builder<ContextT>
export type EndedCallback = Pulse.EndedCallback
export type LoopedCallback = Pulse.LoopedCallback
export type PlaybackOptions = Pulse.PlaybackOptions
export type Playback = Pulse.Playback
export type ProviderClock<PhaseInputT, DirectionTokenT> = Pulse.ProviderClock<PhaseInputT, DirectionTokenT>
export type DirectionTokens<DirectionTokenT> = Pulse.DirectionTokens<DirectionTokenT>
export type DriverDiscontinuityMode = Pulse.DriverDiscontinuityMode
export type ClockDriverAttachmentOptions = Pulse.ClockDriverAttachmentOptions
export type DrivenPlayback = Pulse.DrivenPlayback
export type ClockDriver = Pulse.ClockDriver

return Pulse
