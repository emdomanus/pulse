--!strict
--!optimize 2
--!native

local DefTypes = require(script.def)
local SequenceTypes = require(script.components.sequence)
local PlaybackTypes = require(script.components.playback)
local ClockDriverTypes = require(script.managers.clockDriver)

export type Release = DefTypes.Release
export type TraversalDirection = DefTypes.TraversalDirection
export type AddressMode = DefTypes.AddressMode
export type AddressCause = DefTypes.AddressCause
export type TimeSample = DefTypes.TimeSample
export type SequenceAddress = DefTypes.SequenceAddress
export type PlaybackPosition = DefTypes.PlaybackPosition
export type SampleInfo = DefTypes.SampleInfo
export type AddressInfo = DefTypes.AddressInfo
export type LoopChange = DefTypes.LoopChange
export type ActiveStatus = DefTypes.ActiveStatus
export type TerminalStatus = DefTypes.TerminalStatus
export type Status = DefTypes.Status
export type Completion = DefTypes.Completion
export type PlaybackControl = DefTypes.PlaybackControl
export type Event<ContextT> = SequenceTypes.Event<ContextT>
export type Sample<ContextT> = SequenceTypes.Sample<ContextT>
export type SequenceDefinition<ContextT> = SequenceTypes.SequenceDefinition<ContextT>
export type Sequence<ContextT> = SequenceTypes.Sequence<ContextT>
export type Builder<ContextT> = SequenceTypes.Builder<ContextT>

export type EndedCallback = PlaybackTypes.EndedCallback
export type LoopedCallback = PlaybackTypes.LoopedCallback
export type PlaybackOptions = PlaybackTypes.PlaybackOptions
export type Playback = PlaybackTypes.Playback

export type ProviderClock<PhaseInputT, DirectionTokenT> = ClockDriverTypes.ProviderClock<PhaseInputT, DirectionTokenT>
export type DirectionTokens<DirectionTokenT> = ClockDriverTypes.DirectionTokens<DirectionTokenT>
export type DriverDiscontinuityMode = ClockDriverTypes.DriverDiscontinuityMode
export type ClockDriverAttachmentOptions = ClockDriverTypes.ClockDriverAttachmentOptions
export type DrivenPlayback = ClockDriverTypes.DrivenPlayback
export type ClockDriver = ClockDriverTypes.ClockDriver

return {}
