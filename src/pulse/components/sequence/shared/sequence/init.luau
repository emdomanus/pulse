--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local Types = require(script.Parent.Parent.Parent.Parent.types.components.sequence)
local BuilderModule = require(script.builder)
local Compiler = require(script.compiler)

type AddressPolicy = DefTypes.AddressPolicy
type Builder<ContextT> = Types.Builder<ContextT>
type Sequence<ContextT> = Types.Sequence<ContextT>
type SequenceDefinition<ContextT> = Types.SequenceDefinition<ContextT>
type SequenceImpl<ContextT> = Types.SequenceImpl<ContextT>
type SequenceState<ContextT> = Types.SequenceState<ContextT>
type StoredSequenceImpl = Types.StoredSequenceImpl

type SequenceModule = {
	new: <ContextT>(definition: SequenceDefinition<ContextT>) -> Sequence<ContextT>,
	builder: <ContextT>() -> Builder<ContextT>,
}

local Sequence = {}
Sequence.__index = Sequence

local function ConstructSequence<ContextT>(definition: SequenceDefinition<ContextT>): Sequence<ContextT>
	local state: SequenceState<ContextT> = Compiler.compile(definition)
	local self = (setmetatable(state, Sequence) :: unknown) :: SequenceImpl<ContextT>
	return table.freeze(self)
end

local function ConstructBuilder<ContextT>(): Builder<ContextT>
	return BuilderModule.new(ConstructSequence)
end

function Sequence.getDuration(self: StoredSequenceImpl): number
	return self._duration
end

function Sequence.isLooping(self: StoredSequenceImpl): boolean
	return self._loop
end

function Sequence.getAddressPolicy(self: StoredSequenceImpl): AddressPolicy
	return self._addressPolicy
end

local module: SequenceModule = {
	new = ConstructSequence,
	builder = ConstructBuilder,
}

return module
