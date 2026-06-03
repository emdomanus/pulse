--!strict
--!optimize 2
--!native

local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence)

export type StepId = SequenceTypes.StepId
export type Definition<StepT = StepId> = SequenceTypes.Definition<StepT>
export type Sequence<StepT = StepId> = SequenceTypes.Sequence<StepT>
type SequenceImpl<StepT = StepId> = SequenceTypes.SequenceImpl<StepT>

local Sequence = {}

local function compile<StepT>(_definition: Definition<StepT>, ownsDefinition: boolean): Sequence<StepT>
	local definition = _definition
	local events: { SequenceTypes.Event<StepT> } = {}
	if definition.events then
		events = if ownsDefinition then definition.events else table.clone(definition.events)
	end

	local indexedEvents = table.create(#events)

	if definition.loop == true then
		assert(
			definition.duration ~= nil and definition.duration > 0,
			"Pulse looped sequences require a positive duration"
		)
	end

	for index, event in events do
		indexedEvents[index] = {
			event = event,
			index = index,
		}
	end

	table.sort(indexedEvents, function(left, right)
		if left.event.time == right.event.time then
			return left.index < right.index
		end

		return left.event.time < right.event.time
	end)

	for index, record in indexedEvents do
		events[index] = record.event
	end

	local defaultParams: SequenceTypes.Params = {}
	if definition.params then
		defaultParams = if ownsDefinition then definition.params else table.clone(definition.params)
	end

	local steps: SequenceTypes.Steps<StepT> = {}
	if definition.steps then
		steps = if ownsDefinition then definition.steps else table.clone(definition.steps)
	end

	local transitions: { SequenceTypes.TransitionRule<StepT> } = {}
	if definition.transitions then
		transitions = if ownsDefinition then definition.transitions else table.clone(definition.transitions)
	end

	local updates: { SequenceTypes.Update<StepT> } = {}
	if definition.updates then
		updates = if ownsDefinition then definition.updates else table.clone(definition.updates)
	end

	local signals: { [string]: SequenceTypes.SignalHandler<StepT> } = {}
	if definition.signals then
		signals = if ownsDefinition then definition.signals else table.clone(definition.signals)
	end
	local cleanupDelay = math.max(definition.cleanupDelay or 0, 0)
	local seekMode = definition.seekMode or "procedural"
	local loop = definition.loop == true

	local compiledDefinition: Definition<StepId> = if ownsDefinition then definition else table.clone(definition) :: any

	assert(compiledDefinition, "compiledDefinition expected at this point")
	compiledDefinition.events = events :: any
	compiledDefinition.params = defaultParams
	compiledDefinition.steps = steps :: any
	compiledDefinition.transitions = transitions :: any
	compiledDefinition.updates = updates
	compiledDefinition.signals = signals
	compiledDefinition.cleanupDelay = cleanupDelay
	compiledDefinition.seekMode = seekMode :: any
	compiledDefinition.loop = loop

	local impl: SequenceImpl<StepT> = {
		duration = definition.duration,
		cleanupDelay = cleanupDelay,
		seekMode = seekMode,
		loop = loop,
		defaultParams = defaultParams,
		steps = steps,
		transitions = transitions,
		events = events,
		updates = updates,
		signals = signals,
		definition = compiledDefinition,
		_sortedEvents = events,
	} :: any

	return impl
end

function Sequence.compile<StepT>(_definition: Definition<StepT>): Sequence<StepT>
	return compile(_definition, false)
end

function Sequence.compileOwned<StepT>(_definition: Definition<StepT>): Sequence<StepT>
	return compile(_definition, true)
end

return Sequence
