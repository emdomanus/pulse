--!strict
--!optimize 2
--!native

local TempoModule = require(script.Parent.Parent.Parent.externalPackages.tempo)

export type Clock = TempoModule.Clock
export type Phase<PhaseT> = TempoModule.Phase<PhaseT>
export type PhaseName<PhaseT> = TempoModule.PhaseName<PhaseT>
export type Tempo<PhaseT> = TempoModule.Tempo<PhaseT>

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
	tempo: Tempo<PhaseT>,
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
