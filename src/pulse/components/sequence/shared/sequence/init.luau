--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local Types = require(script.Parent.Parent.Parent.Parent.types.components.sequence)
local BuilderModule = require(script.builder)
local Compiler = require(script.compiler)

type AddressPolicy = DefTypes.AddressPolicy
type Builder = Types.Builder
type Sequence = Types.Sequence
type SequenceDefinition = Types.SequenceDefinition
type SequenceImpl = Types.SequenceImpl
type SequenceState = Types.SequenceState

type SequenceModule = {
	new: (definition: SequenceDefinition) -> Sequence,
	builder: () -> Builder,
}

local Sequence = {}
Sequence.__index = Sequence

local function ConstructSequence(definition: SequenceDefinition): Sequence
	local state: SequenceState = Compiler.compile(definition)
	local self = (setmetatable(state, Sequence) :: unknown) :: SequenceImpl
	return table.freeze(self)
end

local function ConstructBuilder(): Builder
	return BuilderModule.new(ConstructSequence)
end

function Sequence.getDuration(self: SequenceImpl): number
	return self._duration
end

function Sequence.isLooping(self: SequenceImpl): boolean
	return self._loop
end

function Sequence.getAddressPolicy(self: SequenceImpl): AddressPolicy
	return self._addressPolicy
end

local module: SequenceModule = {
	new = ConstructSequence,
	builder = ConstructBuilder,
}

return module
