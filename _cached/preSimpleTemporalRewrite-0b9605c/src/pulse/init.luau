--!strict
--!optimize 2
--!native

local Types = require(script.types)
local Builder = require(script.components.builder.shared.builder)
local RuntimeManager = require(script.managers.runtimeManager.shared.runtimeManager)
local Sequence = require(script.components.sequence.shared.sequence)

export type Release = Types.Release
export type ScheduledTaskId = Types.ScheduledTaskId
export type ClockSample = Types.ClockSample
export type ClockChange = Types.ClockChange
export type ClockChangedCallback = Types.ClockChangedCallback
export type PhaseCallback = Types.PhaseCallback
export type ReachedCallback<DirectionT> = Types.ReachedCallback<DirectionT>
export type ClockDirections<DirectionT> = Types.ClockDirections<DirectionT>
export type Clock<PhaseT, DirectionT> = Types.Clock<PhaseT, DirectionT>

export type RealTimeScheduler = Types.RealTimeScheduler
export type RuntimeConfig = Types.RuntimeConfig
export type SequenceAddress = Types.SequenceAddress
export type PlaybackPosition = Types.PlaybackPosition
export type TraversalDirection = Types.TraversalDirection
export type AddressDirection = Types.AddressDirection
export type LoopChange = Types.LoopChange
export type Params = Types.Params
export type StepId = Types.StepId
export type ActiveStatus = Types.ActiveStatus
export type TerminalStatus = Types.TerminalStatus
export type Status = Types.Status
export type Completion = Types.Completion
export type AddressPolicy = Types.AddressPolicy
export type AddressCause = Types.AddressCause
export type StepChangeCause = Types.StepChangeCause

export type Context<StepT = StepId> = Types.Context<StepT>
export type ReverseEventAction<StepT = StepId> = Types.ReverseEventAction<StepT>
export type ReverseStepAction<StepT = StepId> = Types.ReverseStepAction<StepT>
export type TransitionRule<StepT = StepId> = Types.TransitionRule<StepT>
export type Step<StepT = StepId> = Types.Step<StepT>
export type Steps<StepT = StepId> = Types.Steps<StepT>
export type StepChange<StepT = StepId> = Types.StepChange<StepT>
export type Event<StepT = StepId> = Types.Event<StepT>
export type Update<StepT = StepId> = Types.Update<StepT>
export type SignalHandler<StepT = StepId> = Types.SignalHandler<StepT>
export type RebuildRequest = Types.RebuildRequest
export type RebuildState<StepT = StepId> = Types.RebuildState<StepT>
export type Definition<StepT = StepId> = Types.Definition<StepT>
export type Sequence<StepT = StepId> = Types.Sequence<StepT>
export type Builder<StepT = StepId> = Types.Builder<StepT>

export type EndedCallback = Types.EndedCallback
export type LoopedCallback = Types.LoopedCallback
export type ParamChangedCallback = Types.ParamChangedCallback
export type SignaledCallback = Types.SignaledCallback
export type Playback<StepT = StepId> = Types.Playback<StepT>

export type PlaybackOptions<StepT, PhaseT, DirectionT> = Types.PlaybackOptions<StepT, PhaseT, DirectionT>
export type Runtime = Types.Runtime

local Pulse = {}

function Pulse.new(config: RuntimeConfig?): Runtime
	return RuntimeManager.new(config)
end

function Pulse.sequence<StepT>(definition: Definition<StepT>): Sequence<StepT>
	return Sequence.compile(definition)
end

function Pulse.builder<StepT>(): Builder<StepT>
	return Builder.new()
end

return Pulse
