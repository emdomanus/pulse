--!strict
--!optimize 2
--!native

local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence.shared.sequence)
local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.types.def.playback.shared.playbackDefinitions)
local PlaybackVocabulary = require(script.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)

type Sequence<ContextT> = SequenceTypes.Sequence<ContextT>
type SequenceDefinition<ContextT> = SequenceTypes.SequenceDefinition<ContextT>
type SequenceImpl<ContextT> = SequenceTypes.SequenceImpl<ContextT>
type SequenceState<ContextT> = SequenceTypes.SequenceState<ContextT>
type StoredSequenceImpl = SequenceTypes.StoredSequenceImpl
type CompiledEvent<ContextT> = SequenceTypes.CompiledEvent<ContextT>
type CompiledSample<ContextT> = SequenceTypes.CompiledSample<ContextT>
type Event<ContextT> = SequenceTypes.Event<ContextT>
type Sample<ContextT> = SequenceTypes.Sample<ContextT>
type AddressCallback = SequenceTypes.AddressCallback<unknown>
type EventCallback = SequenceTypes.EventCallback<unknown>
type LoopCallback = SequenceTypes.LoopCallback<unknown>
type PlaybackPosition = PlaybackDefinitions.PlaybackPosition
type SequenceAddress = PlaybackDefinitions.SequenceAddress
type SequenceBoundary = SequenceTypes.SequenceBoundary
type StoredEvent = SequenceTypes.StoredEvent
type StoredSample = SequenceTypes.StoredSample
type TraversalDirection = PlaybackVocabulary.TraversalDirection

type SequenceModule = {
	new: <ContextT>(definition: SequenceDefinition<ContextT>) -> Sequence<ContextT>,
}

local MAX_EXACT_INTEGER = 9_007_199_254_740_991

local function isFinite(value: number): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function assertFinite(value: number, label: string)
	assert(isFinite(value), `Pulse {label} must be finite`)
end

local function preserveContextType<ContextT>(context: ContextT): ContextT
	-- Shared runtime value for Sequence's invariant ContextT brand; this allocates no per-Sequence closure.
	return context
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

local function eventLess<ContextT>(left: CompiledEvent<ContextT>, right: CompiledEvent<ContextT>): boolean
	if left.time == right.time then
		return left.authorIndex < right.authorIndex
	end
	return left.time < right.time
end

local function compileEvents<ContextT>(definition: SequenceDefinition<ContextT>): { CompiledEvent<ContextT> }
	local source: { Event<ContextT> } = definition.events or {}
	assertDenseArray(source, "events")
	local events: { CompiledEvent<ContextT> } = table.create(#source)
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
		local compiled: CompiledEvent<ContextT> = table.freeze({
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

local function compileSamples<ContextT>(definition: SequenceDefinition<ContextT>): { CompiledSample<ContextT> }
	local source: { Sample<ContextT> } = definition.samples or {}
	assertDenseArray(source, "samples")
	local samples: { CompiledSample<ContextT> } = table.create(#source)
	for authorIndex, sample in source do
		local startTime = sample.startTime or 0
		local endTime = if sample.endTime == nil then definition.duration else sample.endTime
		assertFinite(startTime, `sample #{authorIndex} startTime`)
		assertFinite(endTime, `sample #{authorIndex} endTime`)
		assert(
			startTime >= 0 and startTime < endTime and endTime <= definition.duration,
			`Pulse sample #{authorIndex} interval must satisfy 0 <= startTime < endTime <= duration`
		)
		assert(type(sample.run) == "function", `Pulse sample #{authorIndex} run must be a callback`)
		local compiled: CompiledSample<ContextT> = table.freeze({
			startTime = startTime,
			endTime = endTime,
			authorIndex = authorIndex,
			run = sample.run,
		})
		table.insert(samples, compiled)
	end
	return table.freeze(samples)
end

local function compileBoundaries<ContextT>(
	duration: number,
	events: { CompiledEvent<ContextT> },
	samples: { CompiledSample<ContextT> }
): { number }
	local candidates: { number } = { 0, duration }
	for _, event in events do
		table.insert(candidates, event.time)
	end
	for _, sample in samples do
		table.insert(candidates, sample.startTime)
		table.insert(candidates, sample.endTime)
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

local function compileDefinition<ContextT>(definition: SequenceDefinition<ContextT>): SequenceState<ContextT>
	assertFinite(definition.duration, "duration")
	assert(definition.duration >= 0, "Pulse duration must be nonnegative")
	assert(not definition.loop or definition.duration > 0, "Pulse looping sequences require duration greater than zero")
	assert(definition.onPlay == nil or type(definition.onPlay) == "function", "Pulse onPlay must be a callback")
	assert(
		definition.onAddress == nil or type(definition.onAddress) == "function",
		"Pulse onAddress must be a callback"
	)
	assert(definition.onLoop == nil or type(definition.onLoop) == "function", "Pulse onLoop must be a callback")

	local events = compileEvents(definition)
	local samples = compileSamples(definition)
	local contextType: (ContextT) -> ContextT = preserveContextType
	return {
		_contextType = contextType,
		_duration = definition.duration,
		_loop = definition.loop == true,
		_events = events,
		_samples = samples,
		_boundaries = compileBoundaries(definition.duration, events, samples),
		_onPlay = definition.onPlay,
		_onAddress = definition.onAddress,
		_onLoop = definition.onLoop,
	}
end

local function firstAtOrAfter(values: { number }, target: number): number
	local low = 1
	local high = #values + 1
	while low < high do
		local middle = math.floor((low + high) / 2)
		if middle <= #values and values[middle] < target then
			low = middle + 1
		else
			high = middle
		end
	end
	return low
end

local function firstAfter(values: { number }, target: number): number
	local low = 1
	local high = #values + 1
	while low < high do
		local middle = math.floor((low + high) / 2)
		if middle <= #values and values[middle] <= target then
			low = middle + 1
		else
			high = middle
		end
	end
	return low
end

local function eventFirstAtOrAfter(events: { StoredEvent }, target: number): number
	local low = 1
	local high = #events + 1
	while low < high do
		local middle = math.floor((low + high) / 2)
		if middle <= #events and events[middle].time < target then
			low = middle + 1
		else
			high = middle
		end
	end
	return low
end

local function eventFirstAfter(events: { StoredEvent }, target: number): number
	local low = 1
	local high = #events + 1
	while low < high do
		local middle = math.floor((low + high) / 2)
		if middle <= #events and events[middle].time <= target then
			low = middle + 1
		else
			high = middle
		end
	end
	return low
end

local function writeBoundary(
	timePosition: number,
	loopIndex: number,
	unwrappedTimePosition: number,
	output: SequenceBoundary?
): SequenceBoundary
	if output ~= nil then
		output.timePosition = timePosition
		output.loopIndex = loopIndex
		output.unwrappedTimePosition = unwrappedTimePosition
		return output
	end
	return { timePosition = timePosition, loopIndex = loopIndex, unwrappedTimePosition = unwrappedTimePosition }
end

local function composeBoundary(
	self: StoredSequenceImpl,
	loopIndex: number,
	boundaryIndex: number,
	output: SequenceBoundary?
): SequenceBoundary
	local localBoundary = self._boundaries[boundaryIndex]
	assert(localBoundary ~= nil, "Pulse loop boundary index is out of bounds")
	assert(
		loopIndex % 1 == 0 and math.abs(loopIndex) <= MAX_EXACT_INTEGER,
		"Pulse loop boundary exceeds exactly representable loop identity"
	)
	assert(
		(localBoundary ~= self._duration or loopIndex < MAX_EXACT_INTEGER)
			and (localBoundary ~= 0 or loopIndex > -MAX_EXACT_INTEGER),
		"Pulse loop boundary crosses outside exactly representable loop identity"
	)
	local unwrappedTimePosition = loopIndex * self._duration + localBoundary
	assertFinite(unwrappedTimePosition, "loop boundary unwrappedTimePosition")
	local previousBoundary = self._boundaries[boundaryIndex - 1]
	if previousBoundary ~= nil then
		local previousCoordinate = loopIndex * self._duration + previousBoundary
		assertFinite(previousCoordinate, "previous loop boundary unwrappedTimePosition")
		assert(previousCoordinate < unwrappedTimePosition, "Pulse adjacent loop boundary coordinates collide")
	end
	local followingBoundary = self._boundaries[boundaryIndex + 1]
	if followingBoundary ~= nil then
		local followingCoordinate = loopIndex * self._duration + followingBoundary
		assertFinite(followingCoordinate, "following loop boundary unwrappedTimePosition")
		assert(unwrappedTimePosition < followingCoordinate, "Pulse adjacent loop boundary coordinates collide")
	end
	return writeBoundary(localBoundary, loopIndex, unwrappedTimePosition, output)
end

local function nextBoundary(
	self: StoredSequenceImpl,
	position: PlaybackPosition,
	direction: TraversalDirection,
	output: SequenceBoundary?
): SequenceBoundary?
	local boundaries = self._boundaries
	if not self._loop then
		if direction == "forward" then
			local timePosition = boundaries[firstAfter(boundaries, position.timePosition)]
			return if timePosition == nil then nil else writeBoundary(timePosition, 0, timePosition, output)
		end
		local timePosition = boundaries[firstAtOrAfter(boundaries, position.timePosition) - 1]
		return if timePosition == nil then nil else writeBoundary(timePosition, 0, timePosition, output)
	end

	local loopIndex = position.loopIndex
	local localPosition = position.timePosition
	if direction == "forward" then
		local index = firstAfter(boundaries, localPosition)
		if index <= #boundaries then
			return composeBoundary(self, loopIndex, index, output)
		end
		return composeBoundary(self, loopIndex + 1, 2, output)
	end

	local index = firstAtOrAfter(boundaries, localPosition) - 1
	if index >= 1 then
		return composeBoundary(self, loopIndex, index, output)
	end
	local previousIndex = #boundaries - 1
	return composeBoundary(self, loopIndex - 1, previousIndex, output)
end

local Sequence = {}
Sequence.__index = Sequence

local function ConstructSequence<ContextT>(definition: SequenceDefinition<ContextT>): Sequence<ContextT>
	local state: SequenceState<ContextT> = compileDefinition(definition)
	local self = (setmetatable(state, Sequence) :: unknown) :: SequenceImpl<ContextT>
	return table.freeze(self)
end

function Sequence.getDuration(self: StoredSequenceImpl): number
	return self._duration
end

function Sequence.isLooping(self: StoredSequenceImpl): boolean
	return self._loop
end

function Sequence.positionAt(self: StoredSequenceImpl, unwrappedTimePosition: number): PlaybackPosition
	assertFinite(unwrappedTimePosition, "unwrapped playback position")
	if not self._loop then
		local timePosition = math.clamp(unwrappedTimePosition, 0, self._duration)
		return {
			timePosition = timePosition,
			loopIndex = 0,
			unwrappedTimePosition = timePosition,
		}
	end

	local loopIndex = math.floor(unwrappedTimePosition / self._duration)
	assert(math.abs(loopIndex) <= MAX_EXACT_INTEGER, "Pulse loop position exceeds exactly representable loop identity")
	local timePosition = unwrappedTimePosition - loopIndex * self._duration
	if timePosition >= self._duration then
		loopIndex += 1
		timePosition = 0
	elseif timePosition < 0 then
		loopIndex -= 1
		timePosition += self._duration
	end
	assert(math.abs(loopIndex) <= MAX_EXACT_INTEGER, "Pulse loop position exceeds exactly representable loop identity")
	return {
		timePosition = timePosition,
		loopIndex = loopIndex,
		unwrappedTimePosition = unwrappedTimePosition,
	}
end

function Sequence.validateAddress(self: StoredSequenceImpl, address: SequenceAddress): PlaybackPosition
	assertFinite(address.timePosition, "address timePosition")
	assert(
		address.timePosition >= 0 and address.timePosition <= self._duration,
		"Pulse address timePosition must be within the sequence duration"
	)
	local loopIndex = address.loopIndex or 0
	assert(
		isFinite(loopIndex) and loopIndex % 1 == 0 and math.abs(loopIndex) <= MAX_EXACT_INTEGER,
		"Pulse address loopIndex must be an exactly representable finite integer"
	)
	assert(self._loop or loopIndex == 0, "Pulse non-looping sequences only accept loopIndex zero")

	local unwrapped = address.timePosition
	if self._loop then
		local loopStart = loopIndex * self._duration
		local loopEnd = loopStart + self._duration
		assertFinite(loopStart, "address loop start")
		assertFinite(loopEnd, "address loop end")
		unwrapped = loopStart + address.timePosition
		assertFinite(unwrapped, "address unwrappedTimePosition")
		assert(
			(address.timePosition == 0 or unwrapped > loopStart)
				and (address.timePosition == self._duration or unwrapped < loopEnd),
			"Pulse address must preserve a distinct coordinate within its exact loop identity"
		)
		return {
			timePosition = address.timePosition,
			loopIndex = loopIndex,
			unwrappedTimePosition = unwrapped,
		}
	end
	return {
		timePosition = address.timePosition,
		loopIndex = loopIndex,
		unwrappedTimePosition = unwrapped,
	}
end

function Sequence.nextBoundaryInto(
	self: StoredSequenceImpl,
	position: PlaybackPosition,
	direction: TraversalDirection,
	output: SequenceBoundary
): boolean
	return nextBoundary(self, position, direction, output) ~= nil
end

function Sequence.boundaryAt(self: StoredSequenceImpl, position: PlaybackPosition): SequenceBoundary?
	if
		not isFinite(position.timePosition)
		or not isFinite(position.unwrappedTimePosition)
		or not isFinite(position.loopIndex)
		or position.loopIndex % 1 ~= 0
		or math.abs(position.loopIndex) > MAX_EXACT_INTEGER
		or (not self._loop and position.loopIndex ~= 0)
	then
		return nil
	end
	local index = firstAtOrAfter(self._boundaries, position.timePosition)
	local timePosition = self._boundaries[index]
	if timePosition ~= position.timePosition then
		return nil
	end
	return {
		timePosition = timePosition,
		loopIndex = position.loopIndex,
		unwrappedTimePosition = position.unwrappedTimePosition,
	}
end

function Sequence.eventRangeAt(self: StoredSequenceImpl, localTimePosition: number): (number, number)
	local events = self._events
	local first = eventFirstAtOrAfter(events, localTimePosition)
	local after = eventFirstAfter(events, localTimePosition)
	return first, after - 1
end

function Sequence.getEvent(self: StoredSequenceImpl, index: number): StoredEvent
	local event = self._events[index]
	assert(event ~= nil, "Pulse event index is out of bounds")
	return event
end

function Sequence.getSamples(self: StoredSequenceImpl): { StoredSample }
	return self._samples
end

function Sequence.getOnPlay(self: StoredSequenceImpl): EventCallback?
	return self._onPlay
end

function Sequence.getOnAddress(self: StoredSequenceImpl): AddressCallback?
	return self._onAddress
end

function Sequence.getOnLoop(self: StoredSequenceImpl): LoopCallback?
	return self._onLoop
end

function Sequence.nextBoundary(
	self: StoredSequenceImpl,
	position: PlaybackPosition,
	direction: TraversalDirection
): SequenceBoundary?
	return nextBoundary(self, position, direction, nil)
end

local module: SequenceModule = {
	new = ConstructSequence,
}

return module
