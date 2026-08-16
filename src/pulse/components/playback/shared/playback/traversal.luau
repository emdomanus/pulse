--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.def)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.components.playback)
local SequenceTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.components.sequence)
local SequenceRuntime = require(script.Parent.Parent.Parent.Parent.sequence.shared.sequence.runtime)
local Lifecycle = require(script.Parent.lifecycle)

type AddressPolicy = DefTypes.AddressPolicy
type AddressCause = DefTypes.AddressCause
type AddressInfo = DefTypes.AddressInfo
type AddressMode = DefTypes.AddressMode
type BoundaryState = PlaybackTypes.BoundaryState
type LoopChange = DefTypes.LoopChange
type PlaybackControl = DefTypes.PlaybackControl
type PlaybackImpl = PlaybackTypes.PlaybackImpl
type PlaybackPosition = DefTypes.PlaybackPosition
type SequenceBoundary = SequenceTypes.SequenceBoundary
type TraversalDirection = DefTypes.TraversalDirection

type TraversalModule = {
	emitAddress: (
		self: PlaybackImpl,
		cause: AddressCause,
		mode: AddressMode,
		from: PlaybackPosition?
	) -> boolean,
	reconcileTo: (self: PlaybackImpl, target: PlaybackPosition, direction: TraversalDirection) -> boolean,
	prepareDirection: (self: PlaybackImpl, direction: TraversalDirection) -> boolean,
	selectNextBoundary: (self: PlaybackImpl, direction: TraversalDirection) -> SequenceBoundary?,
	beginGeneration: (self: PlaybackImpl, target: PlaybackPosition, disposeCurrent: boolean) -> boolean,
	reconstructTo: (self: PlaybackImpl, target: PlaybackPosition, disposeCurrent: boolean) -> boolean,
	placeWithoutTraversal: (self: PlaybackImpl, target: PlaybackPosition, direction: TraversalDirection?) -> (),
	applyAddressTarget: (
		self: PlaybackImpl,
		target: PlaybackPosition,
		policy: AddressPolicy,
		reason: string,
		cause: AddressCause,
		direction: TraversalDirection?
	) -> boolean,
}

local MAX_RECONCILIATION_WORK = 4_096

local function asControl(self: PlaybackImpl): PlaybackControl
	return (self :: unknown) :: PlaybackControl
end

local function publicPosition(position: PlaybackPosition): PlaybackPosition
	return {
		timePosition = position.timePosition,
		loopIndex = position.loopIndex,
		unwrappedTimePosition = position.unwrappedTimePosition,
	}
end

local function invokeEvent(self: PlaybackImpl, callback: (PlaybackControl, unknown) -> ()): boolean
	self._workCount += 1
	if self._workCount > MAX_RECONCILIATION_WORK then
		Lifecycle.requestTerminal(self, "failed", "catchUpLimitExceeded")
		return false
	end
	if not pcall(callback, asControl(self), self._context) then
		Lifecycle.requestTerminal(self, "failed", "callbackFailed")
		return false
	end
	return self._terminalRequest == nil and self._completion == nil
end

local function emitAddress(self: PlaybackImpl, cause: AddressCause, mode: AddressMode, from: PlaybackPosition?): boolean
	local authored = SequenceRuntime.getOnAddress(self._sequence)
	if authored == nil then
		return true
	end
	self._workCount += 1
	if self._workCount > MAX_RECONCILIATION_WORK then
		Lifecycle.requestTerminal(self, "failed", "catchUpLimitExceeded")
		return false
	end
	local immutableFrom: PlaybackPosition? = if from == nil then nil else table.freeze(publicPosition(from))
	local immutableTarget: PlaybackPosition = table.freeze(publicPosition(self._position))
	local info: AddressInfo = table.freeze({
		cause = cause,
		mode = mode,
		from = immutableFrom,
		target = immutableTarget,
	})
	if not pcall(authored, asControl(self), info, self._context) then
		Lifecycle.requestTerminal(self, "failed", "callbackFailed")
		return false
	end
	return self._terminalRequest == nil and self._completion == nil
end

local function emitLoop(self: PlaybackImpl, change: LoopChange): boolean
	local immutableChange: LoopChange = table.freeze(change)
	self._workCount += 1
	if self._workCount > MAX_RECONCILIATION_WORK then
		Lifecycle.requestTerminal(self, "failed", "catchUpLimitExceeded")
		return false
	end
	local authored = SequenceRuntime.getOnLoop(self._sequence)
	if authored ~= nil and not pcall(authored, asControl(self), immutableChange, self._context) then
		Lifecycle.requestTerminal(self, "failed", "callbackFailed")
		return false
	end
	if self._terminalRequest ~= nil then
		return false
	end
	local bindings = table.clone(self._loopedBindings)
	for _, binding in bindings do
		local callback = binding.callback
		if binding.active and callback ~= nil then
			pcall(callback, immutableChange)
			if self._terminalRequest ~= nil then
				return false
			end
		end
	end
	return self._completion == nil
end

local function runEventsAt(self: PlaybackImpl, timePosition: number, forward: boolean): boolean
	local first, last = SequenceRuntime.eventRangeAt(self._sequence, timePosition)
	if forward then
		for index = first, last do
			local event = SequenceRuntime.getEvent(self._sequence, index)
			if not invokeEvent(self, event.run) then
				return false
			end
		end
	else
		for index = last, first, -1 do
			local reverse = SequenceRuntime.getEvent(self._sequence, index).reverse
			if reverse ~= nil and not invokeEvent(self, reverse) then
				return false
			end
		end
	end
	return true
end

local function processBoundary(
	self: PlaybackImpl,
	boundary: SequenceBoundary,
	direction: TraversalDirection,
	initial: boolean?
): boolean
	self._position = boundary
	local duration = self._sequence:getDuration()
	local looping = self._sequence:isLooping()
	local forward = direction == "forward"
	if looping and forward and boundary.timePosition == duration and initial ~= true then
		if not runEventsAt(self, duration, true) then
			return false
		end
		local change: LoopChange = {
			fromLoopIndex = boundary.loopIndex,
			toLoopIndex = boundary.loopIndex + 1,
			direction = "forward",
		}
		if not emitLoop(self, change) then
			return false
		end
		local nextPosition: PlaybackPosition = {
			timePosition = 0,
			loopIndex = boundary.loopIndex + 1,
			unwrappedTimePosition = boundary.unwrappedTimePosition,
		}
		local nextBoundary = SequenceRuntime.boundaryAt(self._sequence, nextPosition)
		if nextBoundary == nil then
			Lifecycle.requestTerminal(self, "failed", "numericOverflow")
			return false
		end
		self._position = nextBoundary
		if not runEventsAt(self, 0, true) then
			return false
		end
	elseif looping and not forward and boundary.timePosition == 0 and initial ~= true then
		if not runEventsAt(self, 0, false) then
			return false
		end
		local change: LoopChange = {
			fromLoopIndex = boundary.loopIndex,
			toLoopIndex = boundary.loopIndex - 1,
			direction = "backward",
		}
		if not emitLoop(self, change) then
			return false
		end
		local previousPosition: PlaybackPosition = {
			timePosition = duration,
			loopIndex = boundary.loopIndex - 1,
			unwrappedTimePosition = boundary.unwrappedTimePosition,
		}
		local previousBoundary = SequenceRuntime.boundaryAt(self._sequence, previousPosition)
		if previousBoundary == nil then
			Lifecycle.requestTerminal(self, "failed", "numericOverflow")
			return false
		end
		self._position = previousBoundary
		if not runEventsAt(self, duration, false) then
			return false
		end
	else
		if not runEventsAt(self, boundary.timePosition, forward) then
			return false
		end
	end
	self._boundaryState = if forward then "after" :: BoundaryState else "before" :: BoundaryState
	return true
end

local function prepareDirection(self: PlaybackImpl, direction: TraversalDirection): boolean
	if self._direction == direction then
		return true
	end
	self._direction = direction
	if self._boundaryState == nil then
		return true
	end
	if direction == "forward" and self._boundaryState == "before" then
		return processBoundary(self, self._position, direction)
	elseif direction == "backward" and self._boundaryState == "after" then
		return processBoundary(self, self._position, direction)
	end
	return true
end

local function selectNextBoundary(self: PlaybackImpl, direction: TraversalDirection): SequenceBoundary?
	local ok, boundary = pcall(SequenceRuntime.nextBoundary, self._sequence, self._position, direction)
	if not ok then
		Lifecycle.requestTerminal(self, "failed", "numericOverflow")
		return nil
	end
	return boundary
end

local function reconcileTo(self: PlaybackImpl, target: PlaybackPosition, direction: TraversalDirection): boolean
	if not prepareDirection(self, direction) then
		return false
	end

	while true do
		local boundary = selectNextBoundary(self, direction)
		if self._terminalRequest ~= nil then
			return false
		end
		local crossed = boundary ~= nil
			and if direction == "forward"
				then boundary.unwrappedTimePosition <= target.unwrappedTimePosition
				else boundary.unwrappedTimePosition >= target.unwrappedTimePosition
		if not crossed or boundary == nil then
			break
		end
		if
			(direction == "forward" and boundary.unwrappedTimePosition <= self._position.unwrappedTimePosition)
			or (direction == "backward" and boundary.unwrappedTimePosition >= self._position.unwrappedTimePosition)
		then
			Lifecycle.requestTerminal(self, "failed", "numericOverflow")
			return false
		end
		if not processBoundary(self, boundary, direction) then
			return false
		end
	end

	if self._position.unwrappedTimePosition ~= target.unwrappedTimePosition then
		self._position = target
		self._boundaryState = nil
	end
	return true
end

local function beginGeneration(self: PlaybackImpl, target: PlaybackPosition, disposeCurrent: boolean): boolean
	if disposeCurrent and not Lifecycle.disposeGeneration(self) then
		Lifecycle.requestTerminal(self, "failed", "cleanupFailed")
		return false
	end
	if self._terminalRequest ~= nil or self._completion ~= nil then
		return false
	end
	self._position = target
	local onPlay = SequenceRuntime.getOnPlay(self._sequence)
	if onPlay ~= nil and not invokeEvent(self, onPlay) then
		return false
	end
	return true
end

local function reconstructTo(self: PlaybackImpl, target: PlaybackPosition, disposeCurrent: boolean): boolean
	if not beginGeneration(self, target, disposeCurrent) then
		return false
	end
	local base = SequenceRuntime.validateAddress(self._sequence, {
		timePosition = 0,
		loopIndex = target.loopIndex,
	})
	local baseBoundary = SequenceRuntime.boundaryAt(self._sequence, base)
	if baseBoundary == nil then
		Lifecycle.requestTerminal(self, "failed", "numericOverflow")
		return false
	end
	self._position = baseBoundary
	self._direction = "forward"
	self._boundaryState = "before"
	if not processBoundary(self, baseBoundary, "forward", true) then
		return false
	end
	if target.unwrappedTimePosition > base.unwrappedTimePosition and not reconcileTo(self, target, "forward") then
		return false
	end
	self._updateCursor = self._position.unwrappedTimePosition
	return true
end

local function placeWithoutTraversal(self: PlaybackImpl, target: PlaybackPosition, direction: TraversalDirection?)
	local boundary = SequenceRuntime.boundaryAt(self._sequence, target)
	self._position = boundary or target
	if boundary ~= nil and direction ~= nil then
		self._boundaryState = if direction == "forward" then "after" else "before"
	else
		self._boundaryState = nil
	end
	self._updateCursor = self._position.unwrappedTimePosition
end

local function applyAddressTarget(
	self: PlaybackImpl,
	target: PlaybackPosition,
	policy: AddressPolicy,
	reason: string,
	cause: AddressCause,
	direction: TraversalDirection?
): boolean
	if policy == "cancel" then
		Lifecycle.requestTerminal(self, "cancelled", reason)
		return false
	end

	local from = publicPosition(self._position)
	if policy == "rebuild" then
		if not reconstructTo(self, target, true) then
			return false
		end
		return emitAddress(self, cause, "reconstruct" :: AddressMode, from)
	else
		placeWithoutTraversal(self, target, direction)
		return emitAddress(self, cause, "skip" :: AddressMode, from)
	end
end

local module: TraversalModule = {
	emitAddress = emitAddress,
	reconcileTo = reconcileTo,
	prepareDirection = prepareDirection,
	selectNextBoundary = selectNextBoundary,
	beginGeneration = beginGeneration,
	reconstructTo = reconstructTo,
	placeWithoutTraversal = placeWithoutTraversal,
	applyAddressTarget = applyAddressTarget,
}

return module
