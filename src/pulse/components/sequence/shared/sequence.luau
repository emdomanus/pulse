--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local Types = require(script.Parent.Parent.Parent.Parent.types.components.sequence)

type AddressPolicy = DefTypes.AddressPolicy
type Builder = Types.Builder
type BuilderImpl = Types.BuilderImpl
type CompiledEvent = Types.CompiledEvent
type CompiledUpdate = Types.CompiledUpdate
type Event = Types.Event
type EventCallback = Types.EventCallback
type LoopChange = DefTypes.LoopChange
type PlaybackContext = DefTypes.PlaybackContext
type PlaybackPosition = DefTypes.PlaybackPosition
type Sequence = Types.Sequence
type SequenceAddress = DefTypes.SequenceAddress
type SequenceBoundary = Types.SequenceBoundary
type SequenceDefinition = Types.SequenceDefinition
type SequenceImpl = Types.SequenceImpl
type TraversalDirection = DefTypes.TraversalDirection
type Update = Types.Update

type SequenceModule = {
	compile: (definition: SequenceDefinition) -> Sequence,
	builder: () -> Builder,
	_validateAddress: (sequence: Sequence, address: SequenceAddress) -> PlaybackPosition,
	_positionAt: (sequence: Sequence, unwrappedTimePosition: number) -> PlaybackPosition,
	_nextBoundary: (
		sequence: Sequence,
		position: PlaybackPosition,
		direction: TraversalDirection
	) -> SequenceBoundary?,
	_boundaryAt: (sequence: Sequence, position: PlaybackPosition) -> SequenceBoundary?,
	_eventRangeAt: (sequence: Sequence, localTimePosition: number) -> (number, number),
	_getEvent: (sequence: Sequence, index: number) -> CompiledEvent,
	_getUpdates: (sequence: Sequence) -> { CompiledUpdate },
	_getOnPlay: (sequence: Sequence) -> EventCallback?,
	_getOnLoop: (sequence: Sequence) -> ((PlaybackContext, LoopChange) -> ())?,
}

local MAX_EXACT_INTEGER = 9_007_199_254_740_991
local SequenceMethods = {}
SequenceMethods.__index = SequenceMethods

local BuilderMethods = {}
BuilderMethods.__index = BuilderMethods

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

local function asSequenceImpl(sequence: Sequence): SequenceImpl
	return (sequence :: unknown) :: SequenceImpl
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

local function eventFirstAtOrAfter(events: { CompiledEvent }, target: number): number
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

local function eventFirstAfter(events: { CompiledEvent }, target: number): number
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

local Sequence = {}

function Sequence.compile(definition: SequenceDefinition): Sequence
	assertFinite(definition.duration, "duration")
	assert(definition.duration > 0, "Pulse duration must be greater than zero")
	assert(definition.onPlay == nil or type(definition.onPlay) == "function", "Pulse onPlay must be a callback")
	assert(definition.onLoop == nil or type(definition.onLoop) == "function", "Pulse onLoop must be a callback")

	local events = compileEvents(definition)
	local updates = compileUpdates(definition)
	local self: SequenceImpl = (
		setmetatable({
			_duration = definition.duration,
			_loop = definition.loop == true,
			_addressPolicy = validatePolicy(definition.addressPolicy),
			_events = events,
			_updates = updates,
			_boundaries = compileBoundaries(definition.duration, events, updates),
			_onPlay = definition.onPlay,
			_onLoop = definition.onLoop,
		}, SequenceMethods) :: unknown
	) :: SequenceImpl
	return table.freeze(self)
end

function SequenceMethods.getDuration(self: SequenceImpl): number
	return self._duration
end

function SequenceMethods.isLooping(self: SequenceImpl): boolean
	return self._loop
end

function SequenceMethods.getAddressPolicy(self: SequenceImpl): AddressPolicy
	return self._addressPolicy
end

function Sequence._positionAt(sequence: Sequence, unwrappedTimePosition: number): PlaybackPosition
	local self = asSequenceImpl(sequence)
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

function Sequence._validateAddress(sequence: Sequence, address: SequenceAddress): PlaybackPosition
	local self = asSequenceImpl(sequence)
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

local function composeBoundary(self: SequenceImpl, loopIndex: number, boundaryIndex: number): SequenceBoundary
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
	return {
		timePosition = localBoundary,
		loopIndex = loopIndex,
		unwrappedTimePosition = unwrappedTimePosition,
	}
end

function Sequence._nextBoundary(
	sequence: Sequence,
	position: PlaybackPosition,
	direction: TraversalDirection
): SequenceBoundary?
	local self = asSequenceImpl(sequence)
	local boundaries = self._boundaries
	if not self._loop then
		if direction == "forward" then
			local timePosition = boundaries[firstAfter(boundaries, position.timePosition)]
			return if timePosition == nil
				then nil
				else {
					timePosition = timePosition,
					loopIndex = 0,
					unwrappedTimePosition = timePosition,
				}
		end
		local timePosition = boundaries[firstAtOrAfter(boundaries, position.timePosition) - 1]
		return if timePosition == nil
			then nil
			else {
				timePosition = timePosition,
				loopIndex = 0,
				unwrappedTimePosition = timePosition,
			}
	end

	local loopIndex = position.loopIndex
	local localPosition = position.timePosition
	if direction == "forward" then
		local index = firstAfter(boundaries, localPosition)
		if index <= #boundaries then
			return composeBoundary(self, loopIndex, index)
		end
		return composeBoundary(self, loopIndex + 1, 2)
	end

	local index = firstAtOrAfter(boundaries, localPosition) - 1
	if index >= 1 then
		return composeBoundary(self, loopIndex, index)
	end
	local previousIndex = #boundaries - 1
	return composeBoundary(self, loopIndex - 1, previousIndex)
end

function Sequence._boundaryAt(sequence: Sequence, position: PlaybackPosition): SequenceBoundary?
	local self = asSequenceImpl(sequence)
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

function Sequence._eventRangeAt(sequence: Sequence, localTimePosition: number): (number, number)
	local events = asSequenceImpl(sequence)._events
	local first = eventFirstAtOrAfter(events, localTimePosition)
	local after = eventFirstAfter(events, localTimePosition)
	return first, after - 1
end

function Sequence._getEvent(sequence: Sequence, index: number): CompiledEvent
	local event = asSequenceImpl(sequence)._events[index]
	assert(event ~= nil, "Pulse event index is out of bounds")
	return event
end

function Sequence._getUpdates(sequence: Sequence): { CompiledUpdate }
	return asSequenceImpl(sequence)._updates
end

function Sequence._getOnPlay(sequence: Sequence): EventCallback?
	return asSequenceImpl(sequence)._onPlay
end

function Sequence._getOnLoop(sequence: Sequence): ((PlaybackContext, LoopChange) -> ())?
	return asSequenceImpl(sequence)._onLoop
end

function Sequence.builder(): Builder
	local self: BuilderImpl = (
		setmetatable({
			_duration = nil,
			_loop = false,
			_addressPolicy = "skip" :: AddressPolicy,
			_events = {},
			_updates = {},
			_onPlay = nil,
			_onLoop = nil,
		}, BuilderMethods) :: unknown
	) :: BuilderImpl
	return self
end

function BuilderMethods.duration(self: BuilderImpl, seconds: number): Builder
	self._duration = seconds
	return self
end

function BuilderMethods.loop(self: BuilderImpl, enabled: boolean?): Builder
	self._loop = if enabled == nil then true else enabled
	return self
end

function BuilderMethods.addressPolicy(self: BuilderImpl, policy: AddressPolicy): Builder
	self._addressPolicy = policy
	return self
end

function BuilderMethods.event(self: BuilderImpl, event: Event): Builder
	table.insert(self._events, {
		time = event.time,
		run = event.run,
		reverse = event.reverse,
	})
	return self
end

function BuilderMethods.update(self: BuilderImpl, update: Update): Builder
	table.insert(self._updates, {
		startTime = update.startTime,
		endTime = update.endTime,
		run = update.run,
	})
	return self
end

function BuilderMethods.onPlay(self: BuilderImpl, callback: EventCallback): Builder
	self._onPlay = callback
	return self
end

function BuilderMethods.onLoop(self: BuilderImpl, callback: (PlaybackContext, LoopChange) -> ()): Builder
	self._onLoop = callback
	return self
end

function BuilderMethods.compile(self: BuilderImpl): Sequence
	local duration = self._duration
	assert(duration ~= nil, "Pulse Builder requires duration before compile")
	return Sequence.compile({
		duration = duration,
		loop = self._loop,
		addressPolicy = self._addressPolicy,
		events = self._events,
		updates = self._updates,
		onPlay = self._onPlay,
		onLoop = self._onLoop,
	})
end

local module: SequenceModule = {
	compile = Sequence.compile,
	builder = Sequence.builder,
	_validateAddress = Sequence._validateAddress,
	_positionAt = Sequence._positionAt,
	_nextBoundary = Sequence._nextBoundary,
	_boundaryAt = Sequence._boundaryAt,
	_eventRangeAt = Sequence._eventRangeAt,
	_getEvent = Sequence._getEvent,
	_getUpdates = Sequence._getUpdates,
	_getOnPlay = Sequence._getOnPlay,
	_getOnLoop = Sequence._getOnLoop,
}

return module
