--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local PlaybackInternalTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback.internal)
local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence)

type Action<StepT> = PlaybackInternalTypes.Action<StepT>
type TimelineView<StepT> = PlaybackInternalTypes.TimelineView<StepT>
type SequenceImpl<StepT> = SequenceTypes.SequenceImpl<StepT>
type CompiledEvent<StepT> = SequenceTypes.CompiledEvent<StepT>

type TimelineModule = {
	actionsAt: <StepT>(sequence: SequenceImpl<StepT>, position: number) -> { Action<StepT> },
	loopActionStage: <StepT>(actions: { Action<StepT> }) -> number?,
	positionRecord: <StepT>(view: TimelineView<StepT>) -> DefTypes.PlaybackPosition,
	localTimePosition: <StepT>(view: TimelineView<StepT>) -> number,
	nextCheckpoint: <StepT>(
		sequence: SequenceImpl<StepT>,
		position: number,
		direction: DefTypes.TraversalDirection
	) -> number?,
}

local Timeline = {}

local function firstAtOrAfter<StepT>(events: { CompiledEvent<StepT> }, target: number): number
	local low = 1
	local high = #events + 1
	while low < high do
		local middle = math.floor((low + high) / 2)
		if middle <= #events and events[middle].definition.time < target then
			low = middle + 1
		else
			high = middle
		end
	end
	return low
end

local function firstAfter<StepT>(events: { CompiledEvent<StepT> }, target: number): number
	local low = 1
	local high = #events + 1
	while low < high do
		local middle = math.floor((low + high) / 2)
		if middle <= #events and events[middle].definition.time <= target then
			low = middle + 1
		else
			high = middle
		end
	end
	return low
end

local function lastBefore<StepT>(events: { CompiledEvent<StepT> }, target: number): number
	return firstAtOrAfter(events, target) - 1
end

local function appendEventsAt<StepT>(
	actions: { Action<StepT> },
	events: { CompiledEvent<StepT> },
	timePosition: number,
	loopIndex: number
)
	local index = firstAtOrAfter(events, timePosition)
	while index <= #events and events[index].definition.time == timePosition do
		table.insert(actions, {
			kind = "event",
			event = events[index],
			loopIndex = loopIndex,
			fromLoopIndex = loopIndex,
			toLoopIndex = loopIndex,
		})
		index += 1
	end
end

local function boundaryIndexAt(position: number, duration: number): number?
	local below = math.floor(position / duration)
	if position == below * duration then
		return below
	end
	local above = below + 1
	if position == above * duration then
		return above
	end
	return nil
end

function Timeline.actionsAt<StepT>(sequence: SequenceImpl<StepT>, position: number): { Action<StepT> }
	local actions: { Action<StepT> } = {}
	local duration = sequence.duration
	if not sequence.loop then
		appendEventsAt(actions, sequence._forwardEvents, position, 0)
		return actions
	end

	assert(duration ~= nil and duration > 0, "Pulse loop duration invariant failed")
	local boundaryIndex = boundaryIndexAt(position, duration)
	if boundaryIndex ~= nil then
		appendEventsAt(actions, sequence._forwardEvents, duration, boundaryIndex - 1)
		table.insert(actions, {
			kind = "loop",
			event = nil,
			loopIndex = boundaryIndex,
			fromLoopIndex = boundaryIndex - 1,
			toLoopIndex = boundaryIndex,
		})
		appendEventsAt(actions, sequence._forwardEvents, 0, boundaryIndex)
		return actions
	end

	local loopIndex = math.floor(position / duration)
	local localPosition = position - loopIndex * duration
	appendEventsAt(actions, sequence._forwardEvents, localPosition, loopIndex)
	return actions
end

function Timeline.loopActionStage<StepT>(actions: { Action<StepT> }): number?
	for index, action in actions do
		if action.kind == "loop" then
			return index
		end
	end
	return nil
end

function Timeline.positionRecord<StepT>(view: TimelineView<StepT>): DefTypes.PlaybackPosition
	local sequence = view._sequence
	local duration = sequence.duration
	if not sequence.loop then
		return {
			timePosition = view._position,
			loopIndex = 0,
			unwrappedTimePosition = view._position,
		}
	end

	assert(duration ~= nil and duration > 0, "Pulse loop duration invariant failed")
	local boundaryIndex = boundaryIndexAt(view._position, duration)
	if boundaryIndex ~= nil then
		local actions = Timeline.actionsAt(sequence, view._position)
		local loopStage = Timeline.loopActionStage(actions)
		assert(loopStage ~= nil, "Pulse loop boundary action invariant failed")
		if view._boundaryStage < loopStage then
			return {
				timePosition = duration,
				loopIndex = boundaryIndex - 1,
				unwrappedTimePosition = view._position,
			}
		end
		return {
			timePosition = 0,
			loopIndex = boundaryIndex,
			unwrappedTimePosition = view._position,
		}
	end

	local loopIndex = math.floor(view._position / duration)
	return {
		timePosition = view._position - loopIndex * duration,
		loopIndex = loopIndex,
		unwrappedTimePosition = view._position,
	}
end

function Timeline.localTimePosition<StepT>(view: TimelineView<StepT>): number
	return Timeline.positionRecord(view).timePosition
end

local function nextEventCoordinate<StepT>(
	sequence: SequenceImpl<StepT>,
	position: number,
	direction: DefTypes.TraversalDirection
): number?
	local events = sequence._forwardEvents
	if #events == 0 then
		return nil
	end
	local duration = sequence.duration
	if not sequence.loop then
		if direction == "forward" then
			local index = firstAfter(events, position)
			return if index <= #events then events[index].definition.time else nil
		end
		local index = lastBefore(events, position)
		return if index >= 1 then events[index].definition.time else nil
	end

	assert(duration ~= nil and duration > 0, "Pulse loop duration invariant failed")
	local loopIndex = math.floor(position / duration)
	local localPosition = position - loopIndex * duration
	if direction == "forward" then
		local index = firstAfter(events, localPosition)
		if index <= #events then
			return loopIndex * duration + events[index].definition.time
		end
		local nextIndex = firstAfter(events, 0)
		if events[1].definition.time == 0 then
			nextIndex = 1
		end
		if nextIndex <= #events then
			return (loopIndex + 1) * duration + events[nextIndex].definition.time
		end
		return nil
	end

	local index = lastBefore(events, localPosition)
	if index >= 1 then
		return loopIndex * duration + events[index].definition.time
	end
	local previousIndex = lastBefore(events, duration)
	if previousIndex >= 1 then
		return (loopIndex - 1) * duration + events[previousIndex].definition.time
	end
	return nil
end

local function nextLoopBoundary<StepT>(
	sequence: SequenceImpl<StepT>,
	position: number,
	direction: DefTypes.TraversalDirection
): number?
	if not sequence.loop then
		return nil
	end
	local duration = sequence.duration
	assert(duration ~= nil and duration > 0, "Pulse loop duration invariant failed")
	local boundaryIndex = math.floor(position / duration)
	if direction == "forward" then
		return (boundaryIndex + 1) * duration
	end
	if position == boundaryIndex * duration then
		return (boundaryIndex - 1) * duration
	end
	return boundaryIndex * duration
end

function Timeline.nextCheckpoint<StepT>(
	sequence: SequenceImpl<StepT>,
	position: number,
	direction: DefTypes.TraversalDirection
): number?
	local eventCoordinate = nextEventCoordinate(sequence, position, direction)
	local boundaryCoordinate = nextLoopBoundary(sequence, position, direction)
	local selected = eventCoordinate
	if boundaryCoordinate ~= nil then
		if
			selected == nil
			or (direction == "forward" and boundaryCoordinate < selected)
			or (direction == "backward" and boundaryCoordinate > selected)
		then
			selected = boundaryCoordinate
		end
	end
	if not sequence.loop and sequence.duration ~= nil then
		local terminal = if direction == "forward" then sequence.duration else 0
		if (direction == "forward" and terminal > position) or (direction == "backward" and terminal < position) then
			if
				selected == nil
				or (direction == "forward" and terminal < selected)
				or (direction == "backward" and terminal > selected)
			then
				selected = terminal
			end
		end
	end
	return selected
end

local module: TimelineModule = {
	actionsAt = Timeline.actionsAt,
	loopActionStage = Timeline.loopActionStage,
	positionRecord = Timeline.positionRecord,
	localTimePosition = Timeline.localTimePosition,
	nextCheckpoint = Timeline.nextCheckpoint,
}

return module
