--!strict
--!optimize 2
--!native

local PulseServiceTypes = require(script.Parent.Parent.types.services.pulseService)
local Sequence = require(script.Parent.Parent.components.sequence)
local RuntimeManager = require(script.Parent.Parent.managers.runtimeManager)

export type StepId = PulseServiceTypes.StepId
export type Definition<StepT = StepId> = PulseServiceTypes.Definition<StepT>
export type Sequence<StepT = StepId> = PulseServiceTypes.Sequence<StepT>
export type Runtime<PhaseT> = PulseServiceTypes.Runtime<PhaseT>

local PulseService = {}

function PulseService.sequence<StepT>(definition: Definition<StepT>): Sequence<StepT>
	return Sequence.compile(definition)
end

PulseService.Runtime = {
	new = RuntimeManager.new,
}

return PulseService
