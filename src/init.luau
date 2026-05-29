--!strict
--!optimize 2
--!native

local Pulse = require(script.pulse)

export type Clock = Pulse.Clock
export type Phase<PhaseT> = Pulse.Phase<PhaseT>
export type PhaseName<PhaseT> = Pulse.PhaseName<PhaseT>
export type TempoHandle<PhaseT> = Pulse.TempoHandle<PhaseT>
export type HookHandle<T...> = Pulse.HookHandle<T...>

export type Status = Pulse.Status
export type CompletionReason = Pulse.CompletionReason
export type SeekMode = Pulse.SeekMode
export type Completion = Pulse.Completion
export type Params = Pulse.Params
export type StepId = Pulse.StepId
export type PlayRequest<StepT = StepId> = Pulse.PlayRequest<StepT>
export type RuntimeOptions<PhaseT> = Pulse.RuntimeOptions<PhaseT>
export type SeekRequest<StepT = StepId> = Pulse.SeekRequest<StepT>
export type TransitionRule<StepT = StepId> = Pulse.TransitionRule<StepT>
export type Context<StepT = StepId> = Pulse.Context<StepT>
export type CallbackContext = Pulse.CallbackContext
export type Step<StepT = StepId> = Pulse.Step<StepT>
export type Steps<StepT = StepId> = Pulse.Steps<StepT>
export type Event<StepT = StepId> = Pulse.Event<StepT>
export type Update<StepT = StepId> = Pulse.Update<StepT>
export type SignalHandler<StepT = StepId> = Pulse.SignalHandler<StepT>
export type Definition<StepT = StepId> = Pulse.Definition<StepT>
export type Sequence<StepT = StepId> = Pulse.Sequence<StepT>
export type Builder<StepT = StepId> = Pulse.Builder<StepT>
export type Playback<StepT = StepId> = Pulse.Playback<StepT>
export type Runtime<PhaseT> = Pulse.Runtime<PhaseT>
export type PulseService = Pulse.PulseService

return Pulse
