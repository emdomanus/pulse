--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local RuntimeManagerTypes = require(script.Parent.Parent.managers.runtimeManager)
local SequenceTypes = require(script.Parent.Parent.components.sequence)

export type StepId = DefTypes.StepId
export type RuntimeOptions<PhaseT> = DefTypes.RuntimeOptions<PhaseT>
export type Definition<StepT = StepId> = SequenceTypes.Definition<StepT>
export type Sequence<StepT = StepId> = SequenceTypes.Sequence<StepT>
export type Runtime<PhaseT> = RuntimeManagerTypes.Runtime<PhaseT>

export type PulseService = {
	sequence: <StepT>(definition: Definition<StepT>) -> Sequence<StepT>,
	runtime: {
		new: <PhaseT>(options: RuntimeOptions<PhaseT>) -> Runtime<PhaseT>,
	},
}

return {}
