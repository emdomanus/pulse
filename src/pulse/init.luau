--!strict
--!optimize 2
--!native

local Types = require(script.types)
local Components = require(script.components)
local Managers = require(script.managers)
local Services = require(script.services)
local PulseService = Services.pulseService
local Builder = Components.builder

export type Clock = Types.Clock
export type Phase<PhaseT> = Types.Phase<PhaseT>
export type PhaseName<PhaseT> = Types.PhaseName<PhaseT>
export type Tempo<PhaseT> = Types.Tempo<PhaseT>

export type Status = Types.Status
export type CompletionReason = Types.CompletionReason
export type SeekMode = Types.SeekMode
export type Completion = Types.Completion
export type Params = Types.Params
export type StepId = Types.StepId
export type PlayRequest<StepT = StepId> = Types.PlayRequest<StepT>
export type RuntimeOptions<PhaseT> = Types.RuntimeOptions<PhaseT>
export type SeekRequest<StepT = StepId> = Types.SeekRequest<StepT>
export type CallbackMap<T...> = Types.CallbackMap<T...>
export type EndedCallback = Types.EndedCallback
export type LoopedCallback = Types.LoopedCallback
export type ParamChangedCallback = Types.ParamChangedCallback
export type SignaledCallback = Types.SignaledCallback
export type PlaybackCallbacks = Types.PlaybackCallbacks
export type TransitionRule<StepT = StepId> = Types.TransitionRule<StepT>
export type Context<StepT = StepId> = Types.Context<StepT>
export type CallbackContext = Types.CallbackContext
export type Step<StepT = StepId> = Types.Step<StepT>
export type Steps<StepT = StepId> = Types.Steps<StepT>
export type Event<StepT = StepId> = Types.Event<StepT>
export type Update<StepT = StepId> = Types.Update<StepT>
export type SignalHandler<StepT = StepId> = Types.SignalHandler<StepT>
export type Definition<StepT = StepId> = Types.Definition<StepT>
export type Sequence<StepT = StepId> = Types.Sequence<StepT>
export type Builder<StepT = StepId> = Types.Builder<StepT>
export type Playback<StepT = StepId> = Types.Playback<StepT>
export type Runtime<PhaseT> = Types.Runtime<PhaseT>
export type PulseService = Types.PulseService

local Pulse = {}

Pulse.types = Types
Pulse.components = Components
Pulse.managers = Managers
Pulse.services = Services

function Pulse.sequence<StepT>(definition: Definition<StepT>): Sequence<StepT>
	return PulseService.sequence(definition)
end

function Pulse.define<StepT>(): Builder<StepT>
	return Builder.new()
end

Pulse.runtime = PulseService.runtime

return Pulse
