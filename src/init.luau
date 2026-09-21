--!strict
--!optimize 2

local PlaybackDefinitions = require(script.pulse.types.def.playback.shared.playbackDefinitions)
local PlaybackVocabulary = require(script.pulse.common.playback.shared.playbackVocabulary)
local PlaybackControlTypes = require(script.pulse.types.ports.components.playback.shared.playbackControl)
local PlaybackTypes = require(script.pulse.types.components.playback.shared.playback)
local SequenceTypes = require(script.pulse.types.components.sequence.shared.sequence)
local SequenceBuilderTypes = require(script.pulse.types.components.sequence.shared.sequenceBuilder)
local ClockDriverTypes = require(script.pulse.types.managers.clockDriver.shared.clockDriver)
local DrivenPlaybackTypes = require(script.pulse.types.managers.clockDriver.shared.clockDriver.drivenPlayback)
local ProviderClockTypes = require(script.pulse.types.ports.components.clock.shared.providerClock)
local SequenceBuilder = require(script.pulse.components.sequence.shared.sequenceBuilder)
local Sequence = require(script.pulse.components.sequence.shared.sequence)
local Playback = require(script.pulse.components.playback.shared.playback)
local ClockDriver = require(script.pulse.managers.clockDriver.shared.clockDriver)

export type Release = PlaybackDefinitions.Release
export type TraversalDirection = PlaybackVocabulary.TraversalDirection
export type AddressMode = PlaybackVocabulary.AddressMode
export type AddressCause = PlaybackVocabulary.AddressCause
export type TimeSample = PlaybackDefinitions.TimeSample
export type SequenceAddress = PlaybackDefinitions.SequenceAddress
export type PlaybackPosition = PlaybackDefinitions.PlaybackPosition
export type SampleInfo = PlaybackDefinitions.SampleInfo
export type AddressInfo = PlaybackDefinitions.AddressInfo
export type LoopChange = PlaybackDefinitions.LoopChange
export type ActiveStatus = PlaybackVocabulary.ActiveStatus
export type TerminalStatus = PlaybackVocabulary.TerminalStatus
export type Status = PlaybackVocabulary.Status
export type Completion = PlaybackDefinitions.Completion
export type PlaybackControl = PlaybackControlTypes.PlaybackControl
export type Event<ContextT> = SequenceTypes.Event<ContextT>
export type Sample<ContextT> = SequenceTypes.Sample<ContextT>
export type SequenceDefinition<ContextT> = SequenceTypes.SequenceDefinition<ContextT>
export type Sequence<ContextT> = SequenceTypes.Sequence<ContextT>
export type SequenceBuilder<ContextT> = SequenceBuilderTypes.SequenceBuilder<ContextT>
export type EndedCallback = PlaybackTypes.EndedCallback
export type LoopedCallback = PlaybackTypes.LoopedCallback
export type PlaybackOptions = PlaybackTypes.PlaybackOptions
export type Playback = PlaybackTypes.Playback
export type ProviderClock<PhaseInputT, DirectionTokenT> = ProviderClockTypes.ProviderClock<PhaseInputT, DirectionTokenT>
export type DirectionTokens<DirectionTokenT> = ProviderClockTypes.DirectionTokens<DirectionTokenT>
export type DriverDiscontinuityMode = ClockDriverTypes.DriverDiscontinuityMode
export type ClockDriverAttachmentOptions = ClockDriverTypes.ClockDriverAttachmentOptions
export type DrivenPlayback = DrivenPlaybackTypes.DrivenPlayback
export type ClockDriver = ClockDriverTypes.ClockDriver

local Pulse = {}

function Pulse.sequence<ContextT>(definition: SequenceDefinition<ContextT>): Sequence<ContextT>
	return Sequence.new(definition)
end

function Pulse.builder<ContextT>(): SequenceBuilder<ContextT>
	return SequenceBuilder.new(Sequence.new)
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
