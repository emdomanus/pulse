--!strict
--!optimize 2
--!native

local AdvancedUtils = require(script.Parent.Parent.Parent.externalPackages.advancedUtils)
local Tempo = require(script.Parent.Parent.Parent.externalPackages.tempo)

export type Clock = Tempo.Clock
export type Phase<PhaseT> = Tempo.Phase<PhaseT>
export type PhaseName<PhaseT> = Tempo.PhaseName<PhaseT>
export type TempoHandle<PhaseT> = Tempo.TempoHandle<PhaseT>
export type HookHandle<T...> = AdvancedUtils.HookHandle<T...>

export type Status =
	"idle"
	| "playing"
	| "paused"
	| "stopping"
	| "completed"
	| "stopped"
	| "cancelled"
	| "destroyed"
	| "failed"

export type CompletionReason =
	"completed"
	| "stopped"
	| "cancelled"
	| "destroyed"
	| "failed"
	| string

export type SeekMode =
	"none"
	| "forward"
	| "procedural"

export type Completion = {
	reason: CompletionReason,
	status: Status,
	error: any?,
}

export type Params = { [string]: any }
export type StepId = string | number

export type PlayRequest<StepT = StepId> = {
	params: Params?,
	playbackSpeed: number?,
	timePosition: number?,
	step: StepT?,
	autoPlay: boolean?,
}

export type RuntimeOptions<PhaseT> = {
	tempo: TempoHandle<PhaseT>,
	phase: Phase<PhaseName<PhaseT>> | PhaseName<PhaseT>?,
}

export type SeekRequest<StepT = StepId> = {
	timePosition: number?,
	step: StepT?,
	mode: SeekMode?,
	replay: boolean?,
	payload: any?,
}

return {}
