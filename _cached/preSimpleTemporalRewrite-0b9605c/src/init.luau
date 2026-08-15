--!strict
--!optimize 2
--!native

local Pulse = require(script.pulse)

export type Release = Pulse.Release
export type ScheduledTaskId = Pulse.ScheduledTaskId
export type ClockSample = Pulse.ClockSample
export type ClockChange = Pulse.ClockChange
export type ClockChangedCallback = Pulse.ClockChangedCallback
export type PhaseCallback = Pulse.PhaseCallback
export type ReachedCallback<DirectionT> = Pulse.ReachedCallback<DirectionT>
export type ClockDirections<DirectionT> = Pulse.ClockDirections<DirectionT>
export type Clock<PhaseT, DirectionT> = Pulse.Clock<PhaseT, DirectionT>

export type RealTimeScheduler = Pulse.RealTimeScheduler
export type RuntimeConfig = Pulse.RuntimeConfig
export type SequenceAddress = Pulse.SequenceAddress
export type PlaybackPosition = Pulse.PlaybackPosition
export type TraversalDirection = Pulse.TraversalDirection
export type AddressDirection = Pulse.AddressDirection
export type LoopChange = Pulse.LoopChange
export type Params = Pulse.Params
export type StepId = Pulse.StepId
export type ActiveStatus = Pulse.ActiveStatus
export type TerminalStatus = Pulse.TerminalStatus
export type Status = Pulse.Status
export type Completion = Pulse.Completion
export type AddressPolicy = Pulse.AddressPolicy
export type AddressCause = Pulse.AddressCause
export type StepChangeCause = Pulse.StepChangeCause

export type Context<StepT = StepId> = Pulse.Context<StepT>
export type ReverseEventAction<StepT = StepId> = Pulse.ReverseEventAction<StepT>
export type ReverseStepAction<StepT = StepId> = Pulse.ReverseStepAction<StepT>
export type TransitionRule<StepT = StepId> = Pulse.TransitionRule<StepT>
export type Step<StepT = StepId> = Pulse.Step<StepT>
export type Steps<StepT = StepId> = Pulse.Steps<StepT>
export type StepChange<StepT = StepId> = Pulse.StepChange<StepT>
export type Event<StepT = StepId> = Pulse.Event<StepT>
export type Update<StepT = StepId> = Pulse.Update<StepT>
export type SignalHandler<StepT = StepId> = Pulse.SignalHandler<StepT>
export type RebuildRequest = Pulse.RebuildRequest
export type RebuildState<StepT = StepId> = Pulse.RebuildState<StepT>
export type Definition<StepT = StepId> = Pulse.Definition<StepT>
export type Sequence<StepT = StepId> = Pulse.Sequence<StepT>
export type Builder<StepT = StepId> = Pulse.Builder<StepT>

export type EndedCallback = Pulse.EndedCallback
export type LoopedCallback = Pulse.LoopedCallback
export type ParamChangedCallback = Pulse.ParamChangedCallback
export type SignaledCallback = Pulse.SignaledCallback
export type Playback<StepT = StepId> = Pulse.Playback<StepT>

export type PlaybackOptions<StepT, PhaseT, DirectionT> = Pulse.PlaybackOptions<StepT, PhaseT, DirectionT>
export type Runtime = Pulse.Runtime

return Pulse
