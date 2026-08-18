--!strict
--!optimize 2
--!native

local Types = require(script.types)
local Sequence = require(script.components.sequence.shared.sequence)
local Playback = require(script.components.playback.shared.playback)
local ClockDriver = require(script.managers.clockDriver.shared.clockDriver)

export type Release = Types.Release
export type TraversalDirection = Types.TraversalDirection
export type AddressMode = Types.AddressMode
export type AddressCause = Types.AddressCause
export type TimeSample = Types.TimeSample
export type SequenceAddress = Types.SequenceAddress
export type PlaybackPosition = Types.PlaybackPosition
export type SampleInfo = Types.SampleInfo
export type AddressInfo = Types.AddressInfo
export type LoopChange = Types.LoopChange
export type ActiveStatus = Types.ActiveStatus
export type TerminalStatus = Types.TerminalStatus
export type Status = Types.Status
export type Completion = Types.Completion
export type PlaybackControl = Types.PlaybackControl
export type Event<ContextT> = Types.Event<ContextT>
export type Sample<ContextT> = Types.Sample<ContextT>
export type SequenceDefinition<ContextT> = Types.SequenceDefinition<ContextT>
export type Sequence<ContextT> = Types.Sequence<ContextT>
export type Builder<ContextT> = Types.Builder<ContextT>
export type EndedCallback = Types.EndedCallback
export type LoopedCallback = Types.LoopedCallback
export type PlaybackOptions = Types.PlaybackOptions
export type Playback = Types.Playback
export type ProviderClock<PhaseInputT, DirectionTokenT> = Types.ProviderClock<PhaseInputT, DirectionTokenT>
export type DirectionTokens<DirectionTokenT> = Types.DirectionTokens<DirectionTokenT>
export type DriverDiscontinuityMode = Types.DriverDiscontinuityMode
export type ClockDriverAttachmentOptions = Types.ClockDriverAttachmentOptions
export type DrivenPlayback = Types.DrivenPlayback
export type ClockDriver = Types.ClockDriver

local Pulse = {}

function Pulse.sequence<ContextT>(definition: SequenceDefinition<ContextT>): Sequence<ContextT>
	return Sequence.new(definition)
end

function Pulse.builder<ContextT>(): Builder<ContextT>
	return Sequence.builder()
end

function Pulse.clockDriver<PhaseInputT, DirectionTokenT>(
	clock: ProviderClock<PhaseInputT, DirectionTokenT>,
	phase: PhaseInputT,
	directions: DirectionTokens<DirectionTokenT>
): ClockDriver
	return ClockDriver.new(clock, phase, directions)
end

function Pulse.playback<ContextT>(sequence: Sequence<ContextT>, context: ContextT, options: PlaybackOptions?): Playback
	return Playback.new(sequence, context, options)
end

return Pulse
