--!strict
--!optimize 2
--!native

local DefTypes = require(script.def)
local BuilderTypes = require(script.components.builder)
local ContextTypes = require(script.components.context)
local PlaybackTypes = require(script.components.playback)
local SequenceTypes = require(script.components.sequence)
local RuntimeManagerTypes = require(script.managers.runtimeManager)
local PulseServiceTypes = require(script.services.pulseService)

export type Clock = DefTypes.Clock
export type Phase<PhaseT> = DefTypes.Phase<PhaseT>
export type PhaseName<PhaseT> = DefTypes.PhaseName<PhaseT>
export type Tempo<PhaseT> = DefTypes.Tempo<PhaseT>

export type Status = DefTypes.Status
export type CompletionReason = DefTypes.CompletionReason
export type SeekMode = DefTypes.SeekMode
export type Completion = DefTypes.Completion
export type Params = DefTypes.Params
export type StepId = DefTypes.StepId
export type PlayRequest<StepT = StepId> = DefTypes.PlayRequest<StepT>
export type RuntimeOptions<PhaseT> = DefTypes.RuntimeOptions<PhaseT>
export type SeekRequest<StepT = StepId> = DefTypes.SeekRequest<StepT>
export type CallbackMap<T...> = PlaybackTypes.CallbackMap<T...>
export type EndedCallback = PlaybackTypes.EndedCallback
export type LoopedCallback = PlaybackTypes.LoopedCallback
export type ParamChangedCallback = PlaybackTypes.ParamChangedCallback
export type SignaledCallback = PlaybackTypes.SignaledCallback
export type PlaybackCallbacks = PlaybackTypes.PlaybackCallbacks

export type Context<StepT = StepId> = ContextTypes.Context<StepT>
export type CallbackContext = SequenceTypes.CallbackContext
export type TransitionRule<StepT = StepId> = SequenceTypes.TransitionRule<StepT>
export type Step<StepT = StepId> = SequenceTypes.Step<StepT>
export type Steps<StepT = StepId> = SequenceTypes.Steps<StepT>
export type Event<StepT = StepId> = SequenceTypes.Event<StepT>
export type Update<StepT = StepId> = SequenceTypes.Update<StepT>
export type SignalHandler<StepT = StepId> = SequenceTypes.SignalHandler<StepT>
export type Definition<StepT = StepId> = SequenceTypes.Definition<StepT>
export type Sequence<StepT = StepId> = SequenceTypes.Sequence<StepT>
export type Builder<StepT = StepId> = BuilderTypes.Builder<StepT>
export type Playback<StepT = StepId> = PlaybackTypes.Playback<StepT>

export type Runtime<PhaseT> = RuntimeManagerTypes.Runtime<PhaseT>
export type PulseService = PulseServiceTypes.PulseService

return {}
