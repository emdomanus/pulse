--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.def)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.components.playback)
local SequenceRuntime = require(script.Parent.Parent.Parent.Parent.sequence.shared.sequence.runtime)
local Lifecycle = require(script.Parent.lifecycle)
local Traversal = require(script.Parent.traversal)

type AddressCause = DefTypes.AddressCause
type AddressMode = DefTypes.AddressMode
type Operation = PlaybackTypes.Operation
type PlaybackControl = DefTypes.PlaybackControl
type PlaybackImpl = PlaybackTypes.PlaybackImpl
type PlaybackPosition = DefTypes.PlaybackPosition
type SampleInfo = DefTypes.SampleInfo
type TraversalForecast = PlaybackTypes.TraversalForecast
type SequenceAddress = DefTypes.SequenceAddress
type TerminalRequest = PlaybackTypes.TerminalRequest
type TimeSample = DefTypes.TimeSample
type TraversalDirection = DefTypes.TraversalDirection

type RuntimeModule = {
	copySample: (sample: TimeSample) -> TimeSample,
	derivePosition: (self: PlaybackImpl, sourcePosition: number) -> number?,
	desiredDirection: (self: PlaybackImpl) -> TraversalDirection?,
	runSamples: (self: PlaybackImpl) -> boolean,
	finalizeAddress: (self: PlaybackImpl) -> (),
	drainOperations: (self: PlaybackImpl) -> (),
	enqueue: (self: PlaybackImpl, operation: Operation) -> (),
	getTraversalForecast: (self: PlaybackImpl) -> TraversalForecast,
	projectSourcePosition: (self: PlaybackImpl, sourcePosition: number) -> PlaybackPosition?,
	acceptSourceSample: (self: PlaybackImpl, sample: TimeSample) -> (),
	getAcceptedSample: (self: PlaybackImpl) -> TimeSample?,
}

local MAX_RECONCILIATION_WORK = 4_096

local finish = Lifecycle.finish
local requestTerminal = Lifecycle.requestTerminal
local applyAddressTarget = Traversal.applyAddressTarget
local finalizeAddressDirection = Traversal.finalizeAddressDirection
local prepareDirection = Traversal.prepareDirection
local prepareStationaryDirection = Traversal.prepareStationaryDirection
local reconcileTo = Traversal.reconcileTo
local selectNextBoundary = Traversal.selectNextBoundary

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function copySample(sample: TimeSample): TimeSample
	assert(type(sample) == "table", "Pulse TimeSample must be a table")
	assert(isFinite(sample.position), "Pulse TimeSample position must be finite")
	assert(isFinite(sample.rate), "Pulse TimeSample rate must be finite")
	return {
		position = sample.position,
		rate = sample.rate,
	}
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

local function derivePosition(self: PlaybackImpl, sourcePositionValue: number): number?
	local delta = sourcePositionValue - self._anchorSource
	local position = self._anchorSequence + delta * self._playbackSpeed
	return if isFinite(delta) and isFinite(position) then position else nil
end

local function positionAt(self: PlaybackImpl, unwrappedTimePosition: number): PlaybackPosition?
	local ok, position = pcall(SequenceRuntime.positionAt, self._sequence, unwrappedTimePosition)
	if not ok then
		requestTerminal(self, "failed", "numericOverflow")
		return nil
	end
	return position
end

local function reanchor(self: PlaybackImpl, sample: TimeSample)
	self._anchorSource = sample.position
	self._anchorSequence = self._position.unwrappedTimePosition
end

local function desiredDirection(self: PlaybackImpl): TraversalDirection?
	local sample = self._acceptedSample
	return if sample == nil then nil else directionFor(sample.rate, self._playbackSpeed)
end

local function requiresPhaseEvaluation(self: PlaybackImpl): boolean
	local localPosition = self._position.timePosition
	local direction = desiredDirection(self)
	for _, sample in SequenceRuntime.getSamples(self._sequence) do
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
	local accepted = self._acceptedSample
	if accepted == nil then
		return true
	end
	local effectiveRate = accepted.rate * self._playbackSpeed
	if not isFinite(effectiveRate) then
		requestTerminal(self, "failed", "numericOverflow")
		return false
	end
	local immutablePosition: PlaybackPosition = table.freeze(publicPosition(self._position))
	local info: SampleInfo = table.freeze({
		position = immutablePosition,
		rate = effectiveRate,
	})
	local localPosition = self._position.timePosition
	for _, sample in SequenceRuntime.getSamples(self._sequence) do
		if localPosition >= sample.startTime and localPosition < sample.endTime then
			self._workCount += 1
			if self._workCount > MAX_RECONCILIATION_WORK then
				requestTerminal(self, "failed", "catchUpLimitExceeded")
				return false
			end
			if not pcall(sample.run, asControl(self), info, self._context) then
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

local function evaluateSample(self: PlaybackImpl, sample: TimeSample)
	if self._status ~= "playing" then
		return
	end
	if self._resumePending then
		self._resumePending = false
		self._acceptedSample = sample
		reanchor(self, sample)
		local resumedDirection = desiredDirection(self)
		if resumedDirection ~= nil and not prepareStationaryDirection(self, resumedDirection :: TraversalDirection) then
			return
		end
		if runSamples(self) then
			completeIfOutward(self)
		end
		return
	end

	local targetCoordinate = derivePosition(self, sample.position)
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

	self._acceptedSample = sample
	reanchor(self, sample)
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
	local accepted = self._acceptedSample
	if accepted ~= nil then
		reanchor(self, accepted)
	end
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

local function applySeek(self: PlaybackImpl, address: SequenceAddress, mode: AddressMode)
	if self._status ~= "playing" and self._status ~= "paused" then
		return
	end
	local target = SequenceRuntime.validateAddress(self._sequence, address)
	if not applyAddressTarget(self, target, mode, "seek" :: AddressCause, desiredDirection(self)) then
		return
	end
	local accepted = self._acceptedSample
	if accepted ~= nil then
		reanchor(self, accepted)
	end
	if not runSamples(self) then
		return
	end
	if self._status == "playing" then
		finalizeAddress(self)
	end
end

local function applyOperation(self: PlaybackImpl, operation: Operation)
	if operation.kind == "evaluate" then
		evaluateSample(self, operation.sample)
	elseif operation.kind == "pause" then
		applyPause(self)
	elseif operation.kind == "resume" then
		applyResume(self)
	elseif operation.kind == "speed" then
		applySpeed(self, operation.speed)
	elseif operation.kind == "seek" then
		applySeek(self, operation.address, operation.mode)
	end
end

local function drainOperations(self: PlaybackImpl)
	if self._busy or self._completion ~= nil then
		return
	end
	self._busy = true
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

local function getTraversalForecast(self: PlaybackImpl): TraversalForecast
	if self._status ~= "playing" or self._acceptedSample == nil then
		return {
			phaseRequired = false,
			sourceBoundary = nil,
			sourceDirection = nil,
		}
	end
	if self._resumePending then
		return {
			phaseRequired = true,
			sourceBoundary = nil,
			sourceDirection = nil,
		}
	end
	local phaseRequired = requiresPhaseEvaluation(self)
	local direction = desiredDirection(self)
	local accepted = self._acceptedSample :: TimeSample
	local acceptedSourceDirection = sourceDirection(accepted.rate)
	if direction == nil or acceptedSourceDirection == nil then
		return {
			phaseRequired = phaseRequired,
			sourceBoundary = nil,
			sourceDirection = nil,
		}
	end
	local boundary = selectNextBoundary(self, direction :: TraversalDirection)
	if boundary == nil or self._terminalRequest ~= nil then
		return {
			phaseRequired = phaseRequired,
			sourceBoundary = nil,
			sourceDirection = nil,
		}
	end
	local sourceBoundaryValue = self._anchorSource
		+ (boundary.unwrappedTimePosition - self._anchorSequence) / self._playbackSpeed
	if not isFinite(sourceBoundaryValue) then
		requestTerminal(self, "failed", "numericOverflow")
		return {
			phaseRequired = false,
			sourceBoundary = nil,
			sourceDirection = nil,
		}
	end
	return {
		phaseRequired = phaseRequired,
		sourceBoundary = sourceBoundaryValue,
		sourceDirection = acceptedSourceDirection :: TraversalDirection,
	}
end

local function projectSourcePosition(self: PlaybackImpl, sourcePositionValue: number): PlaybackPosition?
	assert(isFinite(sourcePositionValue), "Pulse source position must be finite")
	local target = derivePosition(self, sourcePositionValue)
	if target == nil then
		requestTerminal(self, "failed", "numericOverflow")
		return nil
	end
	return positionAt(self, target)
end

local function acceptSourceSample(self: PlaybackImpl, sample: TimeSample)
	local accepted = copySample(sample)
	self._acceptedSample = accepted
	self._resumePending = false
	reanchor(self, accepted)
end

local function getAcceptedSample(self: PlaybackImpl): TimeSample?
	local accepted = self._acceptedSample
	return if accepted == nil
		then nil
		else {
			position = accepted.position,
			rate = accepted.rate,
		}
end

local module: RuntimeModule = {
	copySample = copySample,
	derivePosition = derivePosition,
	desiredDirection = desiredDirection,
	runSamples = runSamples,
	finalizeAddress = finalizeAddress,
	drainOperations = drainOperations,
	enqueue = enqueue,
	getTraversalForecast = getTraversalForecast,
	projectSourcePosition = projectSourcePosition,
	acceptSourceSample = acceptSourceSample,
	getAcceptedSample = getAcceptedSample,
}

return module
