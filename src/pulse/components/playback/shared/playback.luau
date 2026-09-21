--!strict
--!optimize 2
--!native

local PlaybackTraversalTypes =
	require(script.Parent.Parent.Parent.Parent.types.components.playback.shared.playbackTraversal)
local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.types.def.playback.shared.playbackDefinitions)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback.shared.playback)
local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence.shared.sequence)
local PlaybackVocabulary = require(script.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)
local PlaybackControlTypes =
	require(script.Parent.Parent.Parent.Parent.types.ports.components.playback.shared.playbackControl)

type AddressCause = PlaybackVocabulary.AddressCause
type AddressMode = PlaybackVocabulary.AddressMode
type Completion = PlaybackDefinitions.Completion
type EndedBinding = PlaybackTypes.EndedBinding
type EndedCallback = PlaybackTypes.EndedCallback
type LoopedBinding = PlaybackTypes.LoopedBinding
type LoopedCallback = PlaybackTypes.LoopedCallback
type Playback = PlaybackTypes.Playback
type PlaybackImpl = PlaybackTypes.PlaybackImpl
type PlaybackOptions = PlaybackTypes.PlaybackOptions
type PlaybackPosition = PlaybackDefinitions.PlaybackPosition
type TraversalForecast = PlaybackTraversalTypes.TraversalForecast
type SequenceAddress = PlaybackDefinitions.SequenceAddress
type Sequence<ContextT> = SequenceTypes.Sequence<ContextT>
type Status = PlaybackVocabulary.Status
type StoredSequence = SequenceTypes.StoredSequence
type TerminalRequest = PlaybackTypes.TerminalRequest
type TimeSample = PlaybackDefinitions.TimeSample
type TerminalStatus = PlaybackVocabulary.TerminalStatus
type AddressInfo = PlaybackDefinitions.AddressInfo
type BoundaryState = PlaybackTypes.BoundaryState
type LoopChange = PlaybackDefinitions.LoopChange
type PlaybackControl = PlaybackControlTypes.PlaybackControl
type SequenceBoundary = SequenceTypes.SequenceBoundary
type TraversalDirection = PlaybackVocabulary.TraversalDirection
type Operation = PlaybackTypes.Operation
type SampleInfo = PlaybackDefinitions.SampleInfo

type PlaybackModule = {
	new: <ContextT>(sequence: Sequence<ContextT>, context: ContextT, options: PlaybackOptions?) -> Playback,
}

local MAX_RECONCILIATION_WORK = 4_096

local function noopRelease() end

local function publicPosition(position: PlaybackPosition): PlaybackPosition
	return {
		timePosition = position.timePosition,
		loopIndex = position.loopIndex,
		unwrappedTimePosition = position.unwrappedTimePosition,
	}
end

local function isFinite(value: number): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validateInitialMode(mode: AddressMode?): AddressMode
	local resolved: AddressMode = if mode == nil then "reconstruct" :: AddressMode else mode
	assert(resolved == "reconstruct" or resolved == "skip", "Pulse initialMode must be 'reconstruct' or 'skip'")
	return resolved
end

local function validateAddressMode(mode: AddressMode): AddressMode
	assert(mode == "reconstruct" or mode == "skip", "Pulse address mode must be 'reconstruct' or 'skip'")
	return mode
end

local function disposeGeneration(self: PlaybackImpl): boolean
	local pending = self._cleanup
	self._cleanup = {}
	local succeeded = true
	local workCount = 0
	while #pending > 0 do
		workCount += 1
		if workCount > MAX_RECONCILIATION_WORK then
			self._cleanup = {}
			return false
		end
		local cleanup = table.remove(pending)
		assert(cleanup ~= nil, "Pulse cleanup stack invariant failed")
		if not pcall(cleanup) then
			succeeded = false
		end
		for _, nested in self._cleanup do
			table.insert(pending, nested)
		end
		self._cleanup = {}
	end
	return succeeded
end

local function emitEnded(self: PlaybackImpl, completion: Completion)
	local bindings = table.clone(self._endedBindings)
	self._endedBindings = {}
	self._loopedBindings = {}
	self._deliveringEnded = true
	for _, binding in bindings do
		local callback = binding.callback
		if binding.active and callback ~= nil then
			pcall(callback, completion)
		end
	end
	self._deliveringEnded = false
end

local function finish(self: PlaybackImpl, status: TerminalStatus, reason: string?)
	if self._completion ~= nil or self._finishing then
		return
	end
	self._finishing = true
	if not disposeGeneration(self) and status ~= "failed" then
		status = "failed" :: TerminalStatus
		reason = "cleanupFailed"
	end
	self._context = nil
	local completion: Completion = table.freeze({
		status = status,
		reason = reason,
	})
	self._completion = completion
	self._status = status
	self._operations = {}
	self._finishing = false
	emitEnded(self, completion)
end

local function requestTerminal(self: PlaybackImpl, status: TerminalStatus, reason: string?)
	if self._completion ~= nil or self._terminalRequest ~= nil or self._finishing then
		return
	end
	if self._busy then
		self._terminalRequest = {
			status = status,
			reason = reason,
		}
		self._operations = {}
		return
	end
	finish(self, status, reason)
end

local function asControl(self: PlaybackImpl): PlaybackControl
	return (self :: unknown) :: PlaybackControl
end

local function invokeEvent(self: PlaybackImpl, callback: (PlaybackControl, unknown) -> ()): boolean
	self._workCount += 1
	if self._workCount > MAX_RECONCILIATION_WORK then
		requestTerminal(self, "failed", "catchUpLimitExceeded")
		return false
	end
	if not pcall(callback, asControl(self), self._context) then
		requestTerminal(self, "failed", "callbackFailed")
		return false
	end
	return self._terminalRequest == nil and self._completion == nil
end

local function emitAddress(self: PlaybackImpl, cause: AddressCause, mode: AddressMode, from: PlaybackPosition?): boolean
	local authored = self._sequence:getOnAddress()
	if authored == nil then
		return true
	end
	self._workCount += 1
	if self._workCount > MAX_RECONCILIATION_WORK then
		requestTerminal(self, "failed", "catchUpLimitExceeded")
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
		requestTerminal(self, "failed", "callbackFailed")
		return false
	end
	return self._terminalRequest == nil and self._completion == nil
end

local function emitLoop(self: PlaybackImpl, change: LoopChange): boolean
	local immutableChange: LoopChange = table.freeze(change)
	self._workCount += 1
	if self._workCount > MAX_RECONCILIATION_WORK then
		requestTerminal(self, "failed", "catchUpLimitExceeded")
		return false
	end
	local authored = self._sequence:getOnLoop()
	if authored ~= nil and not pcall(authored, asControl(self), immutableChange, self._context) then
		requestTerminal(self, "failed", "callbackFailed")
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
	local first, last = self._sequence:eventRangeAt(timePosition)
	if forward then
		for index = first, last do
			local event = self._sequence:getEvent(index)
			if not invokeEvent(self, event.run) then
				return false
			end
		end
	else
		for index = last, first, -1 do
			local reverse = self._sequence:getEvent(index).reverse
			if reverse ~= nil and not invokeEvent(self, reverse) then
				return false
			end
		end
	end
	return true
end

local function completeForwardJoin(self: PlaybackImpl): boolean
	local boundary = self._position
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
	local nextBoundary = self._sequence:boundaryAt(nextPosition)
	if nextBoundary == nil then
		requestTerminal(self, "failed", "numericOverflow")
		return false
	end
	self._position = nextBoundary
	if not runEventsAt(self, 0, true) then
		return false
	end
	self._direction = "forward"
	self._boundaryState = "after"
	return true
end

local function completeBackwardJoin(self: PlaybackImpl): boolean
	local boundary = self._position
	local duration = self._sequence:getDuration()
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
	local previousBoundary = self._sequence:boundaryAt(previousPosition)
	if previousBoundary == nil then
		requestTerminal(self, "failed", "numericOverflow")
		return false
	end
	self._position = previousBoundary
	if not runEventsAt(self, duration, false) then
		return false
	end
	self._direction = "backward"
	self._boundaryState = "before"
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
		self._direction = "forward"
		self._boundaryState = "forwardJoinPending"
		return completeForwardJoin(self)
	elseif looping and not forward and boundary.timePosition == 0 and initial ~= true then
		if not runEventsAt(self, 0, false) then
			return false
		end
		self._direction = "backward"
		self._boundaryState = "backwardJoinPending"
		return completeBackwardJoin(self)
	else
		if not runEventsAt(self, boundary.timePosition, forward) then
			return false
		end
	end
	self._boundaryState = if forward then "after" :: BoundaryState else "before" :: BoundaryState
	return true
end

local function prepareDirection(self: PlaybackImpl, direction: TraversalDirection): boolean
	local state = self._boundaryState
	if state == "forwardJoinPending" then
		self._direction = direction
		if direction == "forward" then
			return completeForwardJoin(self)
		end
		if not runEventsAt(self, self._position.timePosition, false) then
			return false
		end
		self._boundaryState = "before"
		return true
	elseif state == "backwardJoinPending" then
		self._direction = direction
		if direction == "backward" then
			return completeBackwardJoin(self)
		end
		if not runEventsAt(self, self._position.timePosition, true) then
			return false
		end
		self._boundaryState = "after"
		return true
	end
	if self._direction == direction then
		return true
	end
	self._direction = direction
	if state == nil then
		if self._sequence:isLooping() then
			if direction == "forward" and self._position.timePosition == self._sequence:getDuration() then
				self._boundaryState = "forwardJoinPending"
				return completeForwardJoin(self)
			elseif direction == "backward" and self._position.timePosition == 0 then
				self._boundaryState = "backwardJoinPending"
				return completeBackwardJoin(self)
			end
		end
		return true
	end
	if direction == "forward" and state == "before" then
		return processBoundary(self, self._position, direction)
	elseif direction == "backward" and state == "after" then
		return processBoundary(self, self._position, direction)
	end
	return true
end

local function prepareStationaryDirection(self: PlaybackImpl, direction: TraversalDirection): boolean
	local state = self._boundaryState
	local matchingPending = (state == "forwardJoinPending" and direction == "forward")
		or (state == "backwardJoinPending" and direction == "backward")
	if matchingPending then
		self._direction = direction
		return true
	elseif state == nil and self._sequence:isLooping() then
		self._direction = direction
		if direction == "forward" and self._position.timePosition == self._sequence:getDuration() then
			self._boundaryState = "forwardJoinPending"
		elseif direction == "backward" and self._position.timePosition == 0 then
			self._boundaryState = "backwardJoinPending"
		end
		return true
	end
	return prepareDirection(self, direction)
end

local function finalizeAddressDirection(self: PlaybackImpl, direction: TraversalDirection): boolean
	local state = self._boundaryState
	if state == "forwardJoinPending" then
		if direction == "forward" then
			self._direction = direction
			return true
		end
		self._direction = direction
		if not runEventsAt(self, self._position.timePosition, false) then
			return false
		end
		self._boundaryState = "before"
		return true
	elseif state == "backwardJoinPending" then
		if direction == "backward" then
			self._direction = direction
			return true
		end
		self._direction = direction
		if not runEventsAt(self, self._position.timePosition, true) then
			return false
		end
		self._boundaryState = "after"
		return true
	end
	if
		self._sequence:isLooping()
		and self._position.timePosition == 0
		and state == "after"
		and direction == "backward"
		and self._direction ~= direction
	then
		self._direction = direction
		if not runEventsAt(self, 0, false) then
			return false
		end
		self._boundaryState = "backwardJoinPending"
		return true
	end
	return prepareDirection(self, direction)
end

local function selectNextBoundary(self: PlaybackImpl, direction: TraversalDirection): SequenceBoundary?
	local ok, boundary = pcall(self._sequence.nextBoundary, self._sequence, self._position, direction)
	if not ok then
		requestTerminal(self, "failed", "numericOverflow")
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
			requestTerminal(self, "failed", "numericOverflow")
			return false
		end
		local exactDurationTarget = self._sequence:isLooping()
			and direction == "forward"
			and target.timePosition == self._sequence:getDuration()
			and boundary.timePosition == target.timePosition
			and boundary.loopIndex == target.loopIndex
			and boundary.unwrappedTimePosition == target.unwrappedTimePosition
		if exactDurationTarget then
			self._position = boundary
			self._direction = "forward"
			if not runEventsAt(self, boundary.timePosition, true) then
				return false
			end
			self._boundaryState = "forwardJoinPending"
			break
		else
			if not processBoundary(self, boundary, direction) then
				return false
			end
		end
	end

	if self._position.unwrappedTimePosition ~= target.unwrappedTimePosition then
		self._position = target
		self._boundaryState = nil
	end
	return true
end

local function beginGeneration(self: PlaybackImpl, target: PlaybackPosition, disposeCurrent: boolean): boolean
	if disposeCurrent and not disposeGeneration(self) then
		requestTerminal(self, "failed", "cleanupFailed")
		return false
	end
	if self._terminalRequest ~= nil or self._completion ~= nil then
		return false
	end
	self._position = target
	local onPlay = self._sequence:getOnPlay()
	if onPlay ~= nil and not invokeEvent(self, onPlay) then
		return false
	end
	return true
end

local function reconstructTo(self: PlaybackImpl, target: PlaybackPosition, disposeCurrent: boolean): boolean
	if not beginGeneration(self, target, disposeCurrent) then
		return false
	end
	local base = self._sequence:validateAddress({
		timePosition = 0,
		loopIndex = target.loopIndex,
	})
	local baseBoundary = self._sequence:boundaryAt(base)
	if baseBoundary == nil then
		requestTerminal(self, "failed", "numericOverflow")
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
	return true
end

local function placeWithoutTraversal(self: PlaybackImpl, target: PlaybackPosition, direction: TraversalDirection?)
	local boundary = self._sequence:boundaryAt(target)
	self._position = boundary or target
	if boundary ~= nil and direction ~= nil then
		if
			self._sequence:isLooping()
			and direction == "forward"
			and target.timePosition == self._sequence:getDuration()
		then
			self._boundaryState = "forwardJoinPending"
		elseif self._sequence:isLooping() and direction == "backward" and target.timePosition == 0 then
			self._boundaryState = "backwardJoinPending"
		else
			self._boundaryState = if direction == "forward" then "after" else "before"
		end
	else
		self._boundaryState = nil
	end
	self._direction = direction
end

local function applyAddressTarget(
	self: PlaybackImpl,
	target: PlaybackPosition,
	mode: AddressMode,
	cause: AddressCause,
	direction: TraversalDirection?
): boolean
	local from = publicPosition(self._position)
	if mode == "reconstruct" then
		if not reconstructTo(self, target, true) then
			return false
		end
		return emitAddress(self, cause, "reconstruct" :: AddressMode, from)
	end
	placeWithoutTraversal(self, target, direction)
	return emitAddress(self, cause, "skip" :: AddressMode, from)
end

local function readSample(sample: TimeSample): (number, number)
	assert(type(sample) == "table", "Pulse TimeSample must be a table")
	local position = sample.position
	assert(isFinite(position), "Pulse TimeSample position must be finite")
	local rate = sample.rate
	assert(isFinite(rate), "Pulse TimeSample rate must be finite")
	return position, rate
end

local function directionFor(rate: number, speed: number): TraversalDirection?
	if rate == 0 or speed == 0 then
		return nil
	end
	return if (rate > 0) == (speed > 0) then "forward" :: TraversalDirection else "backward" :: TraversalDirection
end

local function sourceDirection(rate: number): TraversalDirection?
	if rate > 0 then
		return "forward" :: TraversalDirection
	elseif rate < 0 then
		return "backward" :: TraversalDirection
	end
	return nil
end

local function derivePosition(self: PlaybackImpl, sourcePositionValue: number): number?
	local delta = sourcePositionValue - self._anchorSource
	local position = self._anchorSequence + delta * self._playbackSpeed
	return if isFinite(delta) and isFinite(position) then position else nil
end

local function positionAt(self: PlaybackImpl, unwrappedTimePosition: number): PlaybackPosition?
	local ok, position = pcall(self._sequence.positionAt, self._sequence, unwrappedTimePosition)
	if not ok then
		requestTerminal(self, "failed", "numericOverflow")
		return nil
	end
	return position
end

local function acceptSampleValues(self: PlaybackImpl, sourcePosition: number, sourceRate: number)
	-- Keep the pair present together: no callbacks or yields between these writes.
	self._acceptedSourcePosition, self._acceptedSourceRate = sourcePosition, sourceRate
end

local function reanchor(self: PlaybackImpl)
	local sourcePosition = self._acceptedSourcePosition
	if sourcePosition ~= nil then
		self._anchorSource = sourcePosition
		self._anchorSequence = self._position.unwrappedTimePosition
	end
end

local function desiredDirection(self: PlaybackImpl): TraversalDirection?
	local sourceRate = self._acceptedSourceRate
	return if sourceRate ~= nil then directionFor(sourceRate, self._playbackSpeed) else nil
end

local function requiresPhaseEvaluation(self: PlaybackImpl): boolean
	local localPosition = self._position.timePosition
	local direction = desiredDirection(self)
	for _, sample in self._sequence:getSamples() do
		if localPosition >= sample.startTime and localPosition < sample.endTime then
			return true
		end
		if direction == "backward" and localPosition == sample.endTime then
			return true
		end
	end
	return (self._boundaryState == "forwardJoinPending" and direction == "forward")
		or (self._boundaryState == "backwardJoinPending" and direction == "backward")
end

local function runSamples(self: PlaybackImpl): boolean
	local sourceRate = self._acceptedSourceRate
	if sourceRate == nil then
		return true
	end
	local effectiveRate = sourceRate * self._playbackSpeed
	if not isFinite(effectiveRate) then
		requestTerminal(self, "failed", "numericOverflow")
		return false
	end
	local info: SampleInfo? = nil
	local localPosition = self._position.timePosition
	for _, sample in self._sequence:getSamples() do
		if localPosition >= sample.startTime and localPosition < sample.endTime then
			self._workCount += 1
			if self._workCount > MAX_RECONCILIATION_WORK then
				requestTerminal(self, "failed", "catchUpLimitExceeded")
				return false
			end
			if info == nil then
				local immutablePosition: PlaybackPosition = table.freeze(publicPosition(self._position))
				info = table.freeze({ position = immutablePosition, rate = effectiveRate })
			end
			if not pcall(sample.run, asControl(self), info :: SampleInfo, self._context) then
				requestTerminal(self, "failed", "callbackFailed")
				return false
			end
			if self._terminalRequest ~= nil or self._completion ~= nil then
				return false
			end
		end
	end
	return true
end

local function completeIfOutward(self: PlaybackImpl)
	if self._sequence:isLooping() or self._status ~= "playing" then
		return
	end
	local duration = self._sequence:getDuration()
	if duration == 0 then
		requestTerminal(self, "completed", nil)
		return
	end
	local direction = desiredDirection(self)
	if
		(direction == "forward" and self._position.unwrappedTimePosition >= duration)
		or (direction == "backward" and self._position.unwrappedTimePosition <= 0)
	then
		requestTerminal(self, "completed", nil)
	end
end

local function finalizeAddress(self: PlaybackImpl)
	if self._terminalRequest ~= nil or self._completion ~= nil then
		return
	end
	local direction = desiredDirection(self)
	if direction ~= nil and not finalizeAddressDirection(self, direction :: TraversalDirection) then
		return
	end
	if self._terminalRequest == nil then
		completeIfOutward(self)
	end
end

local function evaluateSample(self: PlaybackImpl, sourcePosition: number, sourceRate: number)
	if self._status ~= "playing" then
		return
	end
	if self._resumePending then
		self._resumePending = false
		acceptSampleValues(self, sourcePosition, sourceRate)
		reanchor(self)
		local resumedDirection = desiredDirection(self)
		if resumedDirection ~= nil and not prepareStationaryDirection(self, resumedDirection :: TraversalDirection) then
			return
		end
		if runSamples(self) then
			completeIfOutward(self)
		end
		return
	end

	local targetCoordinate = derivePosition(self, sourcePosition)
	if targetCoordinate == nil then
		requestTerminal(self, "failed", "numericOverflow")
		return
	end
	local currentCoordinate = self._position.unwrappedTimePosition
	local moved = targetCoordinate ~= currentCoordinate
	if moved then
		local target = positionAt(self, targetCoordinate)
		if target == nil then
			return
		end
		local movement: TraversalDirection = if targetCoordinate > currentCoordinate
			then "forward" :: TraversalDirection
			else "backward" :: TraversalDirection
		if not reconcileTo(self, target, movement) then
			return
		end
	end

	acceptSampleValues(self, sourcePosition, sourceRate)
	reanchor(self)
	local expectedDirection = desiredDirection(self)
	if expectedDirection ~= nil then
		local prepared = if moved
			then prepareDirection(self, expectedDirection :: TraversalDirection)
			else prepareStationaryDirection(self, expectedDirection :: TraversalDirection)
		if not prepared then
			return
		end
	end
	if runSamples(self) then
		completeIfOutward(self)
	end
end

local function applyPause(self: PlaybackImpl)
	if self._status == "playing" then
		self._status = "paused"
		self._resumePending = false
	end
end

local function applyResume(self: PlaybackImpl)
	if self._status == "paused" then
		self._status = "playing"
		self._resumePending = true
	end
end

local function applySpeed(self: PlaybackImpl, speed: number)
	if self._status ~= "playing" and self._status ~= "paused" then
		return
	end
	self._playbackSpeed = speed
	reanchor(self)
	if self._status == "playing" and not self._resumePending then
		local direction = desiredDirection(self)
		if direction ~= nil then
			prepareStationaryDirection(self, direction :: TraversalDirection)
		end
		if self._terminalRequest == nil then
			completeIfOutward(self)
		end
	end
end

local function applySeek(self: PlaybackImpl, target: PlaybackPosition, mode: AddressMode)
	if self._status ~= "playing" and self._status ~= "paused" then
		return
	end
	if not applyAddressTarget(self, target, mode, "seek" :: AddressCause, desiredDirection(self)) then
		return
	end
	reanchor(self)
	if not runSamples(self) then
		return
	end
	if self._status == "playing" then
		finalizeAddress(self)
	end
end

local function applyOperation(self: PlaybackImpl, operation: Operation)
	if operation.kind == "evaluate" then
		evaluateSample(self, operation.position, operation.rate)
	elseif operation.kind == "pause" then
		applyPause(self)
	elseif operation.kind == "resume" then
		applyResume(self)
	elseif operation.kind == "speed" then
		applySpeed(self, operation.speed)
	elseif operation.kind == "seek" then
		applySeek(self, operation.target, operation.mode)
	end
end

local function drainBusyOperations(self: PlaybackImpl)
	while #self._operations > 0 and self._completion == nil and self._terminalRequest == nil do
		local operation = table.remove(self._operations, 1)
		assert(operation ~= nil, "Pulse operation queue invariant failed")
		if not pcall(applyOperation, self, operation) then
			requestTerminal(self, "failed", "operationFailed")
		end
	end
	local terminal: TerminalRequest? = self._terminalRequest
	self._terminalRequest = nil
	self._busy = false
	if terminal ~= nil then
		finish(self, terminal.status, terminal.reason)
	end
end

local function drainOperations(self: PlaybackImpl)
	if self._busy or self._completion ~= nil then
		return
	end
	self._busy = true
	drainBusyOperations(self)
end

local function enqueue(self: PlaybackImpl, operation: Operation)
	if self._completion ~= nil or self._finishing or self._terminalRequest ~= nil then
		return
	end
	if not self._busy then
		self._workCount = 0
	end
	table.insert(self._operations, operation)
	drainOperations(self)
end

local function evaluate(self: PlaybackImpl, sourcePosition: number, sourceRate: number)
	if self._completion ~= nil or self._finishing or self._terminalRequest ~= nil then
		return
	end
	if self._busy then
		enqueue(self, {
			kind = "evaluate" :: "evaluate",
			position = sourcePosition,
			rate = sourceRate,
		})
	else
		self._workCount = 0
		self._busy = true
		-- Enter the protected drain directly without allocating a queue record.
		if not pcall(evaluateSample, self, sourcePosition, sourceRate) then
			requestTerminal(self, "failed", "operationFailed")
		end
		drainBusyOperations(self)
	end
end

local Playback = {}
Playback.__index = Playback

local function ConstructPlayback<ContextT>(sequence: Sequence<ContextT>, context: ContextT, options: PlaybackOptions?): Playback
	local resolvedOptions: PlaybackOptions = options or {}
	local speed = resolvedOptions.playbackSpeed or 1
	local initialMode = validateInitialMode(resolvedOptions.initialMode)
	assert(isFinite(speed), "Pulse playbackSpeed must be finite")
	local storedSequence = (sequence :: unknown) :: StoredSequence
	local initial = storedSequence:validateAddress(resolvedOptions.position or { timePosition = 0 })
	local self: PlaybackImpl = (
		setmetatable({
			_sequence = storedSequence,
			_context = context,
			_status = "idle" :: Status,
			_completion = nil,
			_playbackSpeed = speed,
			_anchorSource = 0,
			_anchorSequence = initial.unwrappedTimePosition,
			_acceptedSourcePosition = nil,
			_acceptedSourceRate = nil,
			_resumePending = false,
			_position = initial,
			_forecastBoundary = { timePosition = 0, loopIndex = 0, unwrappedTimePosition = 0 },
			_initialPosition = initial,
			_initialMode = initialMode,
			_boundaryState = nil,
			_direction = nil,
			_cleanup = {},
			_endedBindings = {},
			_loopedBindings = {},
			_operations = {},
			_busy = false,
			_finishing = false,
			_deliveringEnded = false,
			_terminalRequest = nil,
			_workCount = 0,
		}, Playback) :: unknown
	) :: PlaybackImpl
	return self
end

function Playback.play(self: PlaybackImpl, sample: TimeSample): Playback
	if self._status ~= "idle" or self._finishing then
		return self
	end
	local sourcePosition, sourceRate = readSample(sample)
	self._status = "playing"
	acceptSampleValues(self, sourcePosition, sourceRate)
	self._anchorSource = sourcePosition
	self._anchorSequence = self._initialPosition.unwrappedTimePosition
	self._position = self._initialPosition

	self._busy = true
	self._workCount = 0
	local initialized: boolean
	if self._initialMode == "reconstruct" then
		initialized = reconstructTo(self, self._initialPosition, false)
	else
		initialized = beginGeneration(self, self._initialPosition, false)
		if initialized then
			placeWithoutTraversal(self, self._initialPosition, desiredDirection(self))
		end
	end
	if initialized then
		initialized = emitAddress(self, "initial" :: AddressCause, self._initialMode, nil)
	end
	if initialized then
		initialized = runSamples(self)
	end
	if initialized then
		finalizeAddress(self)
	end

	local terminal: TerminalRequest? = self._terminalRequest
	self._terminalRequest = nil
	self._busy = false
	if terminal ~= nil then
		finish(self, terminal.status, terminal.reason)
	else
		drainOperations(self)
	end
	return self
end

function Playback.evaluate(self: PlaybackImpl, sample: TimeSample): boolean
	local sourcePosition, sourceRate = readSample(sample)
	if self._status ~= "playing" or self._finishing or self._terminalRequest ~= nil then
		return false
	end
	evaluate(self, sourcePosition, sourceRate)
	return true
end

function Playback.pause(self: PlaybackImpl)
	if self._status == "playing" and not self._finishing and self._terminalRequest == nil then
		enqueue(self, {
			kind = "pause" :: "pause",
		})
	end
end

function Playback.resume(self: PlaybackImpl)
	if self._status == "paused" and not self._finishing and self._terminalRequest == nil then
		enqueue(self, {
			kind = "resume" :: "resume",
		})
	end
end

function Playback.setPlaybackSpeed(self: PlaybackImpl, speed: number)
	assert(isFinite(speed), "Pulse playbackSpeed must be finite")
	if
		(self._status == "playing" or self._status == "paused")
		and not self._finishing
		and self._terminalRequest == nil
	then
		enqueue(self, {
			kind = "speed" :: "speed",
			speed = speed,
		})
	end
end

function Playback.getPlaybackSpeed(self: PlaybackImpl): number
	return self._playbackSpeed
end

function Playback.seek(self: PlaybackImpl, address: SequenceAddress, mode: AddressMode): boolean
	local validatedMode = validateAddressMode(mode)
	local validated = self._sequence:validateAddress(address)
	if (self._status ~= "playing" and self._status ~= "paused") or self._finishing or self._terminalRequest ~= nil then
		return false
	end
	enqueue(self, {
		kind = "seek" :: "seek",
		target = validated,
		mode = validatedMode :: AddressMode,
	})
	return true
end

function Playback.getPosition(self: PlaybackImpl): PlaybackPosition
	return publicPosition(self._position)
end

function Playback.writePositionInto(self: PlaybackImpl, output: PlaybackPosition)
	local position = self._position
	output.timePosition = position.timePosition
	output.loopIndex = position.loopIndex
	output.unwrappedTimePosition = position.unwrappedTimePosition
end

function Playback.getStatus(self: PlaybackImpl): Status
	return self._status
end

function Playback.addCleanup(self: PlaybackImpl, cleanup: () -> ())
	assert(type(cleanup) == "function", "Pulse cleanup must be a callback")
	if self._completion ~= nil then
		if self._finishing then
			return
		end
		self._finishing = true
		pcall(cleanup)
		self._finishing = false
		return
	end
	table.insert(self._cleanup, cleanup)
end

function Playback.cancel(self: PlaybackImpl, reason: string?)
	requestTerminal(self, "cancelled", reason)
end

function Playback.deconstruct(self: PlaybackImpl)
	if self._completion ~= nil then
		self._endedBindings = {}
		self._loopedBindings = {}
		return
	end
	requestTerminal(self, "destroyed", nil)
end

function Playback.onEnded(self: PlaybackImpl, callback: EndedCallback): () -> ()
	local completion = self._completion
	if completion ~= nil then
		if self._deliveringEnded then
			return noopRelease
		end
		self._deliveringEnded = true
		pcall(callback, completion)
		self._deliveringEnded = false
		return noopRelease
	end
	local binding: EndedBinding = {
		callback = callback,
		active = true,
	}
	table.insert(self._endedBindings, binding)
	return function()
		if not binding.active then
			return
		end
		binding.active = false
		binding.callback = nil
		for index, candidate in self._endedBindings do
			if candidate == binding then
				table.remove(self._endedBindings, index)
				break
			end
		end
	end
end

function Playback.onLooped(self: PlaybackImpl, callback: LoopedCallback): () -> ()
	if self._completion ~= nil or self._finishing then
		return noopRelease
	end
	local binding: LoopedBinding = {
		callback = callback,
		active = true,
	}
	table.insert(self._loopedBindings, binding)
	return function()
		if not binding.active then
			return
		end
		binding.active = false
		binding.callback = nil
		for index, candidate in self._loopedBindings do
			if candidate == binding then
				table.remove(self._loopedBindings, index)
				break
			end
		end
	end
end

function Playback.isAlive(self: PlaybackImpl): boolean
	return self._completion == nil
end

function Playback.getCompletion(self: PlaybackImpl): Completion?
	return self._completion
end

function Playback.fail(self: PlaybackImpl, reason: string)
	requestTerminal(self, "failed", reason)
end

function Playback.writeTraversalForecastInto(self: PlaybackImpl, output: TraversalForecast)
	-- The drivenPlayback owns this output; reset absent fields so stale deadlines cannot survive.
	output.phaseRequired = false
	output.sourceBoundary = nil
	output.sourceDirection = nil
	local sourceRate = self._acceptedSourceRate
	if self._status ~= "playing" or sourceRate == nil then
		return
	end
	if self._resumePending then
		output.phaseRequired = true
		return
	end
	output.phaseRequired = requiresPhaseEvaluation(self)
	local direction = desiredDirection(self)
	local acceptedSourceDirection = sourceDirection(sourceRate)
	if direction == nil or acceptedSourceDirection == nil then
		return
	end
	local boundary = self._forecastBoundary
	local ok, found = pcall(
		self._sequence.nextBoundaryInto,
		self._sequence,
		self._position,
		direction :: TraversalDirection,
		boundary
	)
	if not ok then
		requestTerminal(self, "failed", "numericOverflow")
		return
	end
	if not found or self._terminalRequest ~= nil then
		return
	end
	local sourceBoundary = self._anchorSource
		+ (boundary.unwrappedTimePosition - self._anchorSequence) / self._playbackSpeed
	if not isFinite(sourceBoundary) then
		output.phaseRequired = false
		requestTerminal(self, "failed", "numericOverflow")
		return
	end
	output.sourceBoundary = sourceBoundary
	output.sourceDirection = acceptedSourceDirection :: TraversalDirection
end

function Playback.validateAddress(self: PlaybackImpl, address: SequenceAddress): SequenceAddress
	return self._sequence:validateAddress(address)
end

function Playback.projectSourcePosition(self: PlaybackImpl, sourcePositionValue: number): PlaybackPosition?
	assert(isFinite(sourcePositionValue), "Pulse source position must be finite")
	local target = derivePosition(self, sourcePositionValue)
	if target == nil then
		requestTerminal(self, "failed", "numericOverflow")
		return nil
	end
	return positionAt(self, target)
end

function Playback.acceptSourceSample(self: PlaybackImpl, sample: TimeSample)
	local sourcePosition, sourceRate = readSample(sample)
	acceptSampleValues(self, sourcePosition, sourceRate)
	self._resumePending = false
	reanchor(self)
end

function Playback.getAcceptedSample(self: PlaybackImpl): TimeSample?
	local sourcePosition = self._acceptedSourcePosition
	local sourceRate = self._acceptedSourceRate
	return if sourcePosition == nil or sourceRate == nil
		then nil
		else {
			position = sourcePosition,
			rate = sourceRate,
		}
end

local module: PlaybackModule = {
	new = ConstructPlayback,
}

return module
