--!strict
--!optimize 2
--!native

local Types = require(script.types)
local Sequence = require(script.components.sequence.shared.sequence)
local Playback = require(script.components.playback.shared.playback)
local TemporalAdapter = require(script.managers.temporalAdapter.shared.temporalAdapter)

export type Release = Types.Release
export type TraversalDirection = Types.TraversalDirection
export type AddressPolicy = Types.AddressPolicy
export type SequenceAddress = Types.SequenceAddress
export type PlaybackPosition = Types.PlaybackPosition
export type LoopChange = Types.LoopChange
export type ActiveStatus = Types.ActiveStatus
export type TerminalStatus = Types.TerminalStatus
export type Status = Types.Status
export type Completion = Types.Completion
export type PlaybackContext = Types.PlaybackContext
export type Event<ContextT> = Types.Event<ContextT>
export type Update<ContextT> = Types.Update<ContextT>
export type SequenceDefinition<ContextT> = Types.SequenceDefinition<ContextT>
export type Sequence<ContextT> = Types.Sequence<ContextT>
export type Builder<ContextT> = Types.Builder<ContextT>
export type EndedCallback = Types.EndedCallback
export type LoopedCallback = Types.LoopedCallback
export type PlaybackOptions = Types.PlaybackOptions
export type Playback = Types.Playback
export type ClockSample = Types.ClockSample
export type ClockChange = Types.ClockChange
export type ProviderClock<PhaseInputT, DirectionTokenT> = Types.ProviderClock<PhaseInputT, DirectionTokenT>
export type DirectionTokens<DirectionTokenT> = Types.DirectionTokens<DirectionTokenT>
export type TemporalAdapter = Types.TemporalAdapter

local Pulse = {}

function Pulse.sequence<ContextT>(definition: SequenceDefinition<ContextT>): Sequence<ContextT>
	return Sequence.new(definition)
end

function Pulse.builder<ContextT>(): Builder<ContextT>
	return Sequence.builder()
end

function Pulse.temporalAdapter<PhaseInputT, DirectionTokenT>(
	clock: ProviderClock<PhaseInputT, DirectionTokenT>,
	phase: PhaseInputT,
	directions: DirectionTokens<DirectionTokenT>
): TemporalAdapter
	return TemporalAdapter.new(clock, phase, directions)
end

function Pulse.playback<ContextT>(
	sequence: Sequence<ContextT>,
	adapter: TemporalAdapter,
	context: ContextT,
	options: PlaybackOptions?
): Playback
	return Playback.new(sequence, adapter, context, options)
end

return Pulse
