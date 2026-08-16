--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.def)
local Types = require(script.Parent.Parent.Parent.Parent.Parent.types.components.sequence)

type AddressPolicy = DefTypes.AddressPolicy
type CompiledEvent = Types.CompiledEvent
type CompiledUpdate = Types.CompiledUpdate
type Event = Types.Event
type SequenceDefinition = Types.SequenceDefinition
type SequenceState = Types.SequenceState
type Update = Types.Update

type CompilerModule = {
	compile: (definition: SequenceDefinition) -> SequenceState,
}

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function assertFinite(value: number, label: string)
	assert(isFinite(value), `Pulse {label} must be finite`)
end

local function assertDenseArray<T>(values: { T }, label: string)
	local count = 0
	for index in values do
		assert(
			type(index) == "number" and index >= 1 and index % 1 == 0,
			`Pulse {label} must use positive integer keys`
		)
		count += 1
	end
	for index = 1, count do
		assert(values[index] ~= nil, `Pulse {label} must be a dense array`)
	end
end

local function eventLess(left: CompiledEvent, right: CompiledEvent): boolean
	if left.time == right.time then
		return left.authorIndex < right.authorIndex
	end
	return left.time < right.time
end

local function validatePolicy(policy: AddressPolicy?): AddressPolicy
	local resolved: AddressPolicy = if policy == nil then "skip" :: AddressPolicy else policy
	assert(
		resolved == "skip" or resolved == "rebuild" or resolved == "cancel",
		"Pulse addressPolicy must be 'skip', 'rebuild', or 'cancel'"
	)
	return resolved
end

local function compileEvents(definition: SequenceDefinition): { CompiledEvent }
	local source: { Event } = definition.events or {}
	assertDenseArray(source, "events")
	local events: { CompiledEvent } = table.create(#source)
	for authorIndex, event in source do
		assertFinite(event.time, `event #{authorIndex} time`)
		assert(
			event.time >= 0 and event.time <= definition.duration,
			`Pulse event #{authorIndex} time must be within the sequence duration`
		)
		assert(type(event.run) == "function", `Pulse event #{authorIndex} run must be a callback`)
		assert(
			event.reverse == nil or type(event.reverse) == "function",
			`Pulse event #{authorIndex} reverse must be a callback`
		)
		local compiled: CompiledEvent = table.freeze({
			time = event.time,
			authorIndex = authorIndex,
			run = event.run,
			reverse = event.reverse,
		})
		table.insert(events, compiled)
	end
	table.sort(events, eventLess)
	return table.freeze(events)
end

local function compileUpdates(definition: SequenceDefinition): { CompiledUpdate }
	local source: { Update } = definition.updates or {}
	assertDenseArray(source, "updates")
	local updates: { CompiledUpdate } = table.create(#source)
	for authorIndex, update in source do
		local startTime = update.startTime or 0
		local endTime = if update.endTime == nil then definition.duration else update.endTime
		assertFinite(startTime, `update #{authorIndex} startTime`)
		assertFinite(endTime, `update #{authorIndex} endTime`)
		assert(
			startTime >= 0 and startTime < endTime and endTime <= definition.duration,
			`Pulse update #{authorIndex} interval must satisfy 0 <= startTime < endTime <= duration`
		)
		assert(type(update.run) == "function", `Pulse update #{authorIndex} run must be a callback`)
		local compiled: CompiledUpdate = table.freeze({
			startTime = startTime,
			endTime = endTime,
			authorIndex = authorIndex,
			run = update.run,
		})
		table.insert(updates, compiled)
	end
	return table.freeze(updates)
end

local function compileBoundaries(duration: number, events: { CompiledEvent }, updates: { CompiledUpdate }): { number }
	local candidates: { number } = { 0, duration }
	for _, event in events do
		table.insert(candidates, event.time)
	end
	for _, update in updates do
		table.insert(candidates, update.startTime)
		table.insert(candidates, update.endTime)
	end
	table.sort(candidates)

	local boundaries: { number } = {}
	for _, candidate in candidates do
		if boundaries[#boundaries] ~= candidate then
			table.insert(boundaries, candidate)
		end
	end
	return table.freeze(boundaries)
end

local function compileDefinition(definition: SequenceDefinition): SequenceState
	assertFinite(definition.duration, "duration")
	assert(definition.duration > 0, "Pulse duration must be greater than zero")
	assert(definition.onPlay == nil or type(definition.onPlay) == "function", "Pulse onPlay must be a callback")
	assert(definition.onLoop == nil or type(definition.onLoop) == "function", "Pulse onLoop must be a callback")

	local events = compileEvents(definition)
	local updates = compileUpdates(definition)
	return {
		_duration = definition.duration,
		_loop = definition.loop == true,
		_addressPolicy = validatePolicy(definition.addressPolicy),
		_events = events,
		_updates = updates,
		_boundaries = compileBoundaries(definition.duration, events, updates),
		_onPlay = definition.onPlay,
		_onLoop = definition.onLoop,
	}
end

local module: CompilerModule = {
	compile = compileDefinition,
}

return module
