--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.def)
local Types = require(script.Parent.Parent.Parent.Parent.Parent.types.components.sequence)

type CompiledEvent = Types.CompiledEvent
type CompiledUpdate = Types.CompiledUpdate
type EventCallback = Types.EventCallback
type LoopChange = DefTypes.LoopChange
type PlaybackContext = DefTypes.PlaybackContext
type PlaybackPosition = DefTypes.PlaybackPosition
type Sequence = Types.Sequence
type SequenceAddress = DefTypes.SequenceAddress
type SequenceBoundary = Types.SequenceBoundary
type SequenceImpl = Types.SequenceImpl
type TraversalDirection = DefTypes.TraversalDirection

type RuntimeModule = {
	validateAddress: (sequence: Sequence, address: SequenceAddress) -> PlaybackPosition,
	positionAt: (sequence: Sequence, unwrappedTimePosition: number) -> PlaybackPosition,
	nextBoundary: (
		sequence: Sequence,
		position: PlaybackPosition,
		direction: TraversalDirection
	) -> SequenceBoundary?,
	boundaryAt: (sequence: Sequence, position: PlaybackPosition) -> SequenceBoundary?,
	eventRangeAt: (sequence: Sequence, localTimePosition: number) -> (number, number),
	getEvent: (sequence: Sequence, index: number) -> CompiledEvent,
	getUpdates: (sequence: Sequence) -> { CompiledUpdate },
	getOnPlay: (sequence: Sequence) -> EventCallback?,
	getOnLoop: (sequence: Sequence) -> ((PlaybackContext, LoopChange) -> ())?,
}

local MAX_EXACT_INTEGER = 9_007_199_254_740_991

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function assertFinite(value: number, label: string)
	assert(isFinite(value), `Pulse {label} must be finite`)
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

local function positionAt(sequence: Sequence, unwrappedTimePosition: number): PlaybackPosition
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

local function validateAddress(sequence: Sequence, address: SequenceAddress): PlaybackPosition
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

local function nextBoundary(
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

local function boundaryAt(sequence: Sequence, position: PlaybackPosition): SequenceBoundary?
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

local function eventRangeAt(sequence: Sequence, localTimePosition: number): (number, number)
	local events = asSequenceImpl(sequence)._events
	local first = eventFirstAtOrAfter(events, localTimePosition)
	local after = eventFirstAfter(events, localTimePosition)
	return first, after - 1
end

local function getEvent(sequence: Sequence, index: number): CompiledEvent
	local event = asSequenceImpl(sequence)._events[index]
	assert(event ~= nil, "Pulse event index is out of bounds")
	return event
end

local function getUpdates(sequence: Sequence): { CompiledUpdate }
	return asSequenceImpl(sequence)._updates
end

local function getOnPlay(sequence: Sequence): EventCallback?
	return asSequenceImpl(sequence)._onPlay
end

local function getOnLoop(sequence: Sequence): ((PlaybackContext, LoopChange) -> ())?
	return asSequenceImpl(sequence)._onLoop
end

local module: RuntimeModule = {
	validateAddress = validateAddress,
	positionAt = positionAt,
	nextBoundary = nextBoundary,
	boundaryAt = boundaryAt,
	eventRangeAt = eventRangeAt,
	getEvent = getEvent,
	getUpdates = getUpdates,
	getOnPlay = getOnPlay,
	getOnLoop = getOnLoop,
}

return module
