--!strict
--!optimize 2
--!native

local DefTypes = require(script.def)
local BuilderTypes = require(script.components.builder)
local ContextTypes = require(script.components.context)
local PlaybackTypes = require(script.components.playback)
local SequenceTypes = require(script.components.sequence)
local RuntimeManagerTypes = require(script.managers.runtimeManager)

export type Release = DefTypes.Release
export type ScheduledTaskId = DefTypes.ScheduledTaskId
export type ClockSample = DefTypes.ClockSample
export type ClockChange = DefTypes.ClockChange
export type ClockChangedCallback = DefTypes.ClockChangedCallback
export type PhaseCallback = DefTypes.PhaseCallback
export type ReachedCallback<DirectionT> = DefTypes.ReachedCallback<DirectionT>
export type ClockDirections<DirectionT> = DefTypes.ClockDirections<DirectionT>
export type Clock<PhaseT, DirectionT> = DefTypes.Clock<PhaseT, DirectionT>

export type RealTimeScheduler = DefTypes.RealTimeScheduler
export type RuntimeConfig = DefTypes.RuntimeConfig
export type SequenceAddress = DefTypes.SequenceAddress
export type PlaybackPosition = DefTypes.PlaybackPosition
export type TraversalDirection = DefTypes.TraversalDirection
export type AddressDirection = DefTypes.AddressDirection
export type LoopChange = DefTypes.LoopChange
export type Params = DefTypes.Params
export type StepId = DefTypes.StepId
export type ActiveStatus = DefTypes.ActiveStatus
export type TerminalStatus = DefTypes.TerminalStatus
export type Status = DefTypes.Status
export type Completion = DefTypes.Completion
export type AddressPolicy = DefTypes.AddressPolicy
export type AddressCause = DefTypes.AddressCause
export type StepChangeCause = DefTypes.StepChangeCause

export type Context<StepT = StepId> = ContextTypes.Context<StepT>
export type ReverseEventAction<StepT = StepId> = SequenceTypes.ReverseEventAction<StepT>
export type ReverseStepAction<StepT = StepId> = SequenceTypes.ReverseStepAction<StepT>
export type TransitionRule<StepT = StepId> = SequenceTypes.TransitionRule<StepT>
export type Step<StepT = StepId> = SequenceTypes.Step<StepT>
export type Steps<StepT = StepId> = SequenceTypes.Steps<StepT>
export type StepChange<StepT = StepId> = SequenceTypes.StepChange<StepT>
export type Event<StepT = StepId> = SequenceTypes.Event<StepT>
export type Update<StepT = StepId> = SequenceTypes.Update<StepT>
export type SignalHandler<StepT = StepId> = SequenceTypes.SignalHandler<StepT>
export type RebuildRequest = SequenceTypes.RebuildRequest
export type RebuildState<StepT = StepId> = SequenceTypes.RebuildState<StepT>
export type Definition<StepT = StepId> = SequenceTypes.Definition<StepT>
export type Sequence<StepT = StepId> = SequenceTypes.Sequence<StepT>
export type Builder<StepT = StepId> = BuilderTypes.Builder<StepT>

export type EndedCallback = PlaybackTypes.EndedCallback
export type LoopedCallback = PlaybackTypes.LoopedCallback
export type ParamChangedCallback = PlaybackTypes.ParamChangedCallback
export type SignaledCallback = PlaybackTypes.SignaledCallback
export type Playback<StepT = StepId> = PlaybackTypes.Playback<StepT>

export type PlaybackOptions<StepT, PhaseT, DirectionT> = RuntimeManagerTypes.PlaybackOptions<StepT, PhaseT, DirectionT>
export type Runtime = RuntimeManagerTypes.Runtime

return {}
