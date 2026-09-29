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
type PlaybackPositionSnapshot = PlaybackDefinitions.PlaybackPositionSnapshot
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
type TraversalDirection = PlaybackVocabulary.TraversalDirection
type Operation = PlaybackTypes.Operation

type PlaybackModule = {
	new: <ContextT>(sequence: Sequence<ContextT>, context: ContextT, options: PlaybackOptions?) -> Playback,
}

local MAX_RECONCILIATION_WORK = 4_096

local function noopRelease() end

local function localPosition(self: PlaybackImpl): number
	local timePosition = self._sequence:positionComponents(self._position)
	return timePosition
end

local function publicPosition(self: PlaybackImpl, position: number): PlaybackPosition
	local timePosition, loopIndex = self._sequence:positionComponents(position)
	return {
		timePosition = timePosition,
		loopIndex = loopIndex,
		unwrappedTimePosition = position,
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

local function emitAddress(self: PlaybackImpl, cause: AddressCause, mode: AddressMode, from: number?): boolean
	local authored = self._sequence:getOnAddress()
	if authored == nil then
		return true
	end
	self._workCount += 1
	if self._workCount > MAX_RECONCILIATION_WORK then
		requestTerminal(self, "failed", "catchUpLimitExceeded")
		return false
	end
	local immutableFrom: PlaybackPositionSnapshot? = if from == nil
		then nil
		else table.freeze(publicPosition(self, from))
	local immutableTarget: PlaybackPositionSnapshot = table.freeze(publicPosition(self, self._position))
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
	local _, loopIndex = self._sequence:positionComponents(self._position)
	local change: LoopChange = {
		fromLoopIndex = loopIndex - 1,
		toLoopIndex = loopIndex,
		direction = "forward",
	}
	if not emitLoop(self, change) or not runEventsAt(self, 0, true) then
		return false
	end
	self._direction = "forward"
	self._boundaryState = "after"
	return true
end

local function completeBackwardJoin(self: PlaybackImpl): boolean
	local _, loopIndex = self._sequence:positionComponents(self._position)
	local change: LoopChange = {
		fromLoopIndex = loopIndex,
		toLoopIndex = loopIndex - 1,
		direction = "backward",
	}
	if not emitLoop(self, change) or not runEventsAt(self, self._sequence:getDuration(), false) then
		return false
	end
	self._direction = "backward"
	self._boundaryState = "before"
	return true
end

local function processBoundary(
	self: PlaybackImpl,
	boundaryTime: number,
	boundary: number,
	direction: TraversalDirection,
	initial: boolean?
): boolean
	self._position = boundary
	local duration = self._sequence:getDuration()
	local looping = self._sequence:isLooping()
	local forward = direction == "forward"
	if looping and forward and boundaryTime == duration and initial ~= true then
		if not runEventsAt(self, duration, true) then
			return false
		end
		self._direction = "forward"
		self._boundaryState = "forwardJoinPending"
		return completeForwardJoin(self)
	elseif looping and not forward and boundaryTime == 0 and initial ~= true then
		if not runEventsAt(self, 0, false) then
			return false
		end
		self._direction = "backward"
		self._boundaryState = "backwardJoinPending"
		return completeBackwardJoin(self)
	else
		if not runEventsAt(self, boundaryTime, forward) then
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
		if not runEventsAt(self, self._sequence:getDuration(), false) then
			return false
		end
		self._boundaryState = "before"
		return true
	elseif state == "backwardJoinPending" then
		self._direction = direction
		if direction == "backward" then
			return completeBackwardJoin(self)
		end
		if not runEventsAt(self, localPosition(self), true) then
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
		if self._sequence:isLooping() and direction == "backward" and localPosition(self) == 0 then
			self._boundaryState = "backwardJoinPending"
			return completeBackwardJoin(self)
		end
		return true
	end
	if direction == "forward" and state == "before" then
		local boundaryTime = localPosition(self)
		if self._sequence:isLooping() and boundaryTime == 0 and direction == "forward" then
			boundaryTime = self._sequence:getDuration()
		end
		return processBoundary(self, boundaryTime, self._position, direction)
	elseif direction == "backward" and state == "after" then
		local boundaryTime = localPosition(self)
		return processBoundary(self, boundaryTime, self._position, direction)
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
		if direction == "backward" and localPosition(self) == 0 then
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
		if not runEventsAt(self, self._sequence:getDuration(), false) then
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
		if not runEventsAt(self, localPosition(self), true) then
			return false
		end
		self._boundaryState = "after"
		return true
	end
	if
		self._sequence:isLooping()
		and localPosition(self) == 0
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

local function selectNextBoundary(self: PlaybackImpl, direction: TraversalDirection): (number?, number?)
	local ok, boundaryTime, boundary = pcall(self._sequence.nextBoundary, self._sequence, self._position, direction)
	if not ok then
		requestTerminal(self, "failed", "numericOverflow")
		return nil, nil
	end
	return boundaryTime, boundary
end

local function reconcileTo(self: PlaybackImpl, target: number, direction: TraversalDirection): boolean
	if not prepareDirection(self, direction) then
		return false
	end
	while true do
		local boundaryTime, boundary = selectNextBoundary(self, direction)
		if self._terminalRequest ~= nil then
			return false
		end
		if boundaryTime == nil or boundary == nil then
			break
		end
		local crossed = if direction == "forward" then boundary <= target else boundary >= target
		if not crossed then
			break
		end
		if
			(direction == "forward" and boundary <= self._position)
			or (direction == "backward" and boundary >= self._position)
		then
			requestTerminal(self, "failed", "numericOverflow")
			return false
		end
		if not processBoundary(self, boundaryTime, boundary, direction) then
			return false
		end
	end
	if self._position ~= target then
		self._position = target
		self._boundaryState = nil
	end
	return true
end

local function beginGeneration(self: PlaybackImpl, target: number, disposeCurrent: boolean): boolean
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

local function reconstructTo(self: PlaybackImpl, target: number, disposeCurrent: boolean): boolean
	if not beginGeneration(self, target, disposeCurrent) then
		return false
	end
	local _, loopIndex = self._sequence:positionComponents(target)
	local base = self._sequence:positionAt(loopIndex * self._sequence:getDuration())
	self._position = base
	self._direction = "forward"
	self._boundaryState = "before"
	if not processBoundary(self, 0, base, "forward", true) then
		return false
	end
	return target <= base or reconcileTo(self, target, "forward")
end

local function placeWithoutTraversal(self: PlaybackImpl, target: number, direction: TraversalDirection?)
	local boundaryTime = self._sequence:boundaryAt(target)
	self._position = target
	if boundaryTime ~= nil and direction ~= nil then
		if self._sequence:isLooping() and direction == "backward" and boundaryTime == 0 then
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
	target: number,
	mode: AddressMode,
	cause: AddressCause,
	direction: TraversalDirection?
): boolean
	local from = self._position
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

local function positionAt(self: PlaybackImpl, unwrappedTimePosition: number): number?
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
		self._anchorSequence = self._position
	end
end

local function desiredDirection(self: PlaybackImpl): TraversalDirection?
	local sourceRate = self._acceptedSourceRate
	return if sourceRate ~= nil then directionFor(sourceRate, self._playbackSpeed) else nil
end

local function requiresPhaseEvaluation(self: PlaybackImpl): boolean
	local timePosition = localPosition(self)
	local direction = desiredDirection(self)
	for _, sample in self._sequence:getSamples() do
		if timePosition >= sample.startTime and timePosition < sample.endTime then
			return true
		end
		if direction == "backward" and timePosition == sample.endTime then
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
	local timePosition = localPosition(self)
	for _, sample in self._sequence:getSamples() do
		if timePosition >= sample.startTime and timePosition < sample.endTime then
			self._workCount += 1
			if self._workCount > MAX_RECONCILIATION_WORK then
				requestTerminal(self, "failed", "catchUpLimitExceeded")
				return false
			end
			if not pcall(sample.run, asControl(self), timePosition, self._position, effectiveRate, self._context) then
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
	if (direction == "forward" and self._position >= duration) or (direction == "backward" and self._position <= 0) then
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
	local currentCoordinate = self._position
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

local function applySeek(self: PlaybackImpl, target: number, mode: AddressMode)
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
			_anchorSequence = initial,
			_acceptedSourcePosition = nil,
			_acceptedSourceRate = nil,
			_resumePending = false,
			_position = initial,
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
	self._anchorSequence = self._initialPosition
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
	return publicPosition(self, self._position)
end

function Playback.writePositionInto(self: PlaybackImpl, output: PlaybackPosition)
	local timePosition, loopIndex = self._sequence:positionComponents(self._position)
	output.timePosition = timePosition
	output.loopIndex = loopIndex
	output.unwrappedTimePosition = self._position
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
	local ok, _, boundary =
		pcall(self._sequence.nextBoundary, self._sequence, self._position, direction :: TraversalDirection)
	if not ok then
		requestTerminal(self, "failed", "numericOverflow")
		return
	end
	if boundary == nil or self._terminalRequest ~= nil then
		return
	end
	local sourceBoundary = self._anchorSource + (boundary - self._anchorSequence) / self._playbackSpeed
	if not isFinite(sourceBoundary) then
		output.phaseRequired = false
		requestTerminal(self, "failed", "numericOverflow")
		return
	end
	output.sourceBoundary = sourceBoundary
	output.sourceDirection = acceptedSourceDirection :: TraversalDirection
end

function Playback.validateAddress(self: PlaybackImpl, address: SequenceAddress): SequenceAddress
	return publicPosition(self, self._sequence:validateAddress(address))
end

function Playback.projectSourcePosition(self: PlaybackImpl, sourcePositionValue: number): PlaybackPosition?
	assert(isFinite(sourcePositionValue), "Pulse source position must be finite")
	local target = derivePosition(self, sourcePositionValue)
	if target == nil then
		requestTerminal(self, "failed", "numericOverflow")
		return nil
	end
	local position = positionAt(self, target)
	return if position == nil then nil else publicPosition(self, position)
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
