--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.def)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.components.playback)
local TemporalAdapterTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.managers.temporalAdapter)
local SequenceRuntime = require(script.Parent.Parent.Parent.Parent.sequence.shared.sequence.runtime)
local TemporalAdapter =
	require(script.Parent.Parent.Parent.Parent.Parent.managers.temporalAdapter.shared.temporalAdapter)
local Lifecycle = require(script.Parent.lifecycle)
local Traversal = require(script.Parent.traversal)

type AddressCause = DefTypes.AddressCause
type ClockChange = TemporalAdapterTypes.ClockChange
type ClockSample = TemporalAdapterTypes.ClockSample
type Operation = PlaybackTypes.Operation
type PlaybackControl = DefTypes.PlaybackControl
type PlaybackImpl = PlaybackTypes.PlaybackImpl
type PlaybackPosition = DefTypes.PlaybackPosition
type PlaybackSink = TemporalAdapterTypes.PlaybackSink
type SequenceAddress = DefTypes.SequenceAddress
type TerminalRequest = PlaybackTypes.TerminalRequest
type TraversalDirection = DefTypes.TraversalDirection

type RuntimeModule = {
	derivePosition: (self: PlaybackImpl, clockPosition: number) -> number?,
	reanchor: (self: PlaybackImpl, sample: ClockSample) -> (),
	desiredDirection: (self: PlaybackImpl) -> TraversalDirection?,
	snapshotClock: (self: PlaybackImpl) -> (ClockSample?, number),
	refreshOwnership: (self: PlaybackImpl, preserveTask: boolean) -> (),
	drainOperations: (self: PlaybackImpl) -> (),
	enqueue: (self: PlaybackImpl, operation: Operation) -> (),
	onReached: (self: PlaybackImpl) -> (),
}

local MAX_RECONCILIATION_WORK = 4_096
local DEADLINE_ABSOLUTE_EPSILON = 1e-9
local DEADLINE_RELATIVE_EPSILON = 4.440892098500626e-16

-- Primitive and direction helpers

local cancelScheduled = Lifecycle.cancelScheduled
local stopUpdating = Lifecycle.stopUpdating
local detach = Lifecycle.detach
local finish = Lifecycle.finish
local requestTerminal = Lifecycle.requestTerminal
local reconcileTo = Traversal.reconcileTo
local prepareDirection = Traversal.prepareDirection
local selectNextBoundary = Traversal.selectNextBoundary
local applyAddressTarget = Traversal.applyAddressTarget

local refreshOwnership: (self: PlaybackImpl, preserveTask: boolean) -> ()
local runPhaseUpdates: (self: PlaybackImpl, fromPosition: number, toPosition: number) -> ()
local reconcileSample: (self: PlaybackImpl, sample: ClockSample, preserveTask: boolean, refreshAfter: boolean?) -> ()

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function directionFor(rate: number, speed: number): TraversalDirection?
	if rate == 0 or speed == 0 then
		return nil
	end
	return if (rate > 0) == (speed > 0) then "forward" :: TraversalDirection else "backward" :: TraversalDirection
end

local function clockDirection(rate: number): TraversalDirection?
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

local function asPlaybackSink(self: PlaybackImpl): PlaybackSink
	return self
end

local function advanceTo(self: PlaybackImpl, target: PlaybackPosition, direction: TraversalDirection): boolean
	local duration = self._sequence:getDuration()
	local targetCoordinate = target.unwrappedTimePosition
	local completes = not self._sequence:isLooping()
		and (
			(direction == "forward" and targetCoordinate >= duration)
			or (direction == "backward" and targetCoordinate <= 0)
		)
	if not reconcileTo(self, target, direction) then
		return false
	end
	local fromPosition = self._updateCursor
	local toPosition = self._position.unwrappedTimePosition
	self._updateCursor = toPosition
	if fromPosition ~= toPosition then
		runPhaseUpdates(self, fromPosition, toPosition)
		if self._terminalRequest ~= nil or self._completion ~= nil then
			return false
		end
	end
	if completes then
		requestTerminal(self, "completed", nil)
		return false
	end
	return true
end

-- Anchors and scheduling

local function derivePosition(self: PlaybackImpl, clockPosition: number): number?
	local delta = clockPosition - self._anchorClock
	local position = self._anchorSequence + delta * self._playbackSpeed
	return if isFinite(delta) and isFinite(position) then position else nil
end

local function reanchor(self: PlaybackImpl, sample: ClockSample)
	self._anchorClock = sample.timePosition
	self._anchorSequence = self._position.unwrappedTimePosition
	self._clockRate = sample.rate
end

local function positionAt(self: PlaybackImpl, unwrappedTimePosition: number): PlaybackPosition?
	local ok, position = pcall(SequenceRuntime.positionAt, self._sequence, unwrappedTimePosition)
	if not ok then
		requestTerminal(self, "failed", "numericOverflow")
		return nil
	end
	return position
end

local function desiredDirection(self: PlaybackImpl): TraversalDirection?
	return directionFor(self._clockRate, self._playbackSpeed)
end

local function snapshotClock(self: PlaybackImpl): (ClockSample?, number)
	local sample, clockSerial = TemporalAdapter._snapshot(self._adapter)
	if sample == nil then
		requestTerminal(self, "failed", "clockReadFailed")
	end
	return sample, clockSerial
end

local function updateLocalPosition(self: PlaybackImpl, direction: TraversalDirection): number
	if self._sequence:isLooping() and self._position.timePosition == 0 and direction == "backward" then
		return self._sequence:getDuration()
	end
	return self._position.timePosition
end

local function hasActiveUpdate(self: PlaybackImpl, direction: TraversalDirection): boolean
	local localPosition = updateLocalPosition(self, direction)
	for _, update in SequenceRuntime.getUpdates(self._sequence) do
		if direction == "forward" then
			if localPosition >= update.startTime and localPosition < update.endTime then
				return true
			end
		elseif localPosition > update.startTime and localPosition <= update.endTime then
			return true
		end
	end
	return false
end

local function refreshUpdating(self: PlaybackImpl)
	local direction: TraversalDirection? = desiredDirection(self)
	local shouldUpdate = self._status == "playing"
		and direction ~= nil
		and hasActiveUpdate(self, direction :: TraversalDirection)
	if shouldUpdate == self._updating then
		return
	end
	if shouldUpdate then
		if not TemporalAdapter._setUpdating(self._adapter, asPlaybackSink(self), true) then
			requestTerminal(self, "failed", "phaseBindFailed")
			return
		end
		self._updating = true
		self._updateCursor = self._position.unwrappedTimePosition
	else
		stopUpdating(self)
	end
end

local function scheduleNext(self: PlaybackImpl, preserveTask: boolean)
	local attempts = 0
	while self._status == "playing" and self._terminalRequest == nil do
		attempts += 1
		if attempts > MAX_RECONCILIATION_WORK then
			requestTerminal(self, "failed", "catchUpLimitExceeded")
			return
		end
		local direction: TraversalDirection? = desiredDirection(self)
		if direction == nil then
			cancelScheduled(self)
			return
		end
		local activeDirection: TraversalDirection = if direction == "forward"
			then "forward" :: TraversalDirection
			else "backward" :: TraversalDirection
		local nextBoundary = selectNextBoundary(self, activeDirection)
		if self._terminalRequest ~= nil then
			return
		end
		if nextBoundary == nil then
			requestTerminal(self, "completed", nil)
			return
		end
		local nextCoordinate = nextBoundary.unwrappedTimePosition
		local currentCoordinate = self._position.unwrappedTimePosition
		if
			(activeDirection == "forward" and nextCoordinate <= currentCoordinate)
			or (activeDirection == "backward" and nextCoordinate >= currentCoordinate)
		then
			requestTerminal(self, "failed", "numericOverflow")
			return
		end
		local runAt = self._anchorClock + (nextCoordinate - self._anchorSequence) / self._playbackSpeed
		if not isFinite(runAt) then
			requestTerminal(self, "failed", "numericOverflow")
			return
		end
		local providerDirection: TraversalDirection? = clockDirection(self._clockRate)
		if providerDirection == nil then
			cancelScheduled(self)
			return
		end
		if
			(providerDirection == "forward" and runAt <= self._anchorClock)
			or (providerDirection == "backward" and runAt >= self._anchorClock)
		then
			requestTerminal(self, "failed", "numericOverflow")
			return
		end

		local sample, clockSerial = TemporalAdapter._snapshot(self._adapter)
		if sample == nil then
			requestTerminal(self, "failed", "clockReadFailed")
			return
		end
		if clockSerial > self._appliedClockSerial then
			cancelScheduled(self)
			return
		end
		local alreadyReached = if providerDirection == "forward"
			then sample.timePosition >= runAt
			else sample.timePosition <= runAt
		if alreadyReached then
			cancelScheduled(self)
			reconcileSample(self, sample, false, false)
			if self._terminalRequest ~= nil or self._completion ~= nil then
				return
			end
			refreshUpdating(self)
			continue
		end

		local id = self._scheduledId
		if
			id ~= nil
			and preserveTask
			and self._scheduledDirection == providerDirection
			and TemporalAdapter._reschedule(self._adapter, id, runAt)
		then
			self._scheduledBoundary = nextBoundary
		else
			cancelScheduled(self)
			local scheduled = TemporalAdapter._schedule(
				self._adapter,
				runAt,
				providerDirection :: TraversalDirection,
				self._reachedCallback
			)
			if scheduled == nil then
				requestTerminal(self, "failed", "scheduleFailed")
				return
			end
			self._scheduledId = scheduled
			self._scheduledDirection = providerDirection :: TraversalDirection
			self._scheduledBoundary = nextBoundary
		end

		local validationSample, validationSerial = TemporalAdapter._snapshot(self._adapter)
		if validationSample == nil then
			requestTerminal(self, "failed", "clockReadFailed")
			return
		end
		if validationSerial > self._appliedClockSerial then
			cancelScheduled(self)
			return
		end
		local passedWhileScheduling = if providerDirection == "forward"
			then validationSample.timePosition >= runAt
			else validationSample.timePosition <= runAt
		if not passedWhileScheduling then
			return
		end
		cancelScheduled(self)
		reconcileSample(self, validationSample, false, false)
		if self._terminalRequest ~= nil or self._completion ~= nil then
			return
		end
		refreshUpdating(self)
	end
end

refreshOwnership = function(self: PlaybackImpl, preserveTask: boolean)
	if self._completion ~= nil or self._terminalRequest ~= nil then
		return
	end
	local direction: TraversalDirection? = desiredDirection(self)
	if direction ~= nil and not prepareDirection(self, direction) then
		return
	end
	refreshUpdating(self)
	if self._terminalRequest == nil then
		scheduleNext(self, preserveTask)
	end
end

reconcileSample = function(self: PlaybackImpl, sample: ClockSample, preserveTask: boolean, refreshAfter: boolean?)
	local targetCoordinate = derivePosition(self, sample.timePosition)
	if targetCoordinate == nil then
		requestTerminal(self, "failed", "numericOverflow")
		return
	end
	local currentCoordinate = self._position.unwrappedTimePosition
	if targetCoordinate ~= currentCoordinate then
		local target = positionAt(self, targetCoordinate)
		if target == nil then
			return
		end
		local direction: TraversalDirection = if targetCoordinate > currentCoordinate then "forward" else "backward"
		if not advanceTo(self, target, direction) then
			return
		end
	end
	reanchor(self, sample)
	if refreshAfter ~= false then
		refreshOwnership(self, preserveTask)
	end
end

local function reconcileReached(self: PlaybackImpl, sample: ClockSample)
	local target = derivePosition(self, sample.timePosition)
	if target == nil then
		requestTerminal(self, "failed", "numericOverflow")
		return
	end
	local scheduledBoundary = self._scheduledBoundary
	local scheduledDirection = self._scheduledDirection
	local currentClockDirection = clockDirection(sample.rate)
	local tolerance = if scheduledBoundary == nil
		then DEADLINE_ABSOLUTE_EPSILON
		else math.max(
			DEADLINE_ABSOLUTE_EPSILON,
			math.abs(scheduledBoundary.unwrappedTimePosition) * DEADLINE_RELATIVE_EPSILON
		)
	if
		scheduledBoundary ~= nil
		and scheduledDirection ~= nil
		and currentClockDirection == scheduledDirection
		and math.abs(target - scheduledBoundary.unwrappedTimePosition) <= tolerance
	then
		local scheduledCoordinate = scheduledBoundary.unwrappedTimePosition
		local currentCoordinate = self._position.unwrappedTimePosition
		if scheduledCoordinate ~= currentCoordinate then
			local movement: TraversalDirection = if scheduledCoordinate > currentCoordinate
				then "forward"
				else "backward"
			if not advanceTo(self, scheduledBoundary, movement) then
				return
			end
		end
		reanchor(self, sample)
		refreshOwnership(self, true)
		return
	end
	reconcileSample(self, sample, true)
end

local function advanceClockPosition(self: PlaybackImpl, clockPosition: number): boolean
	local targetCoordinate = derivePosition(self, clockPosition)
	if targetCoordinate == nil then
		requestTerminal(self, "failed", "numericOverflow")
		return false
	end
	local currentCoordinate = self._position.unwrappedTimePosition
	if targetCoordinate == currentCoordinate then
		return true
	end
	local target = positionAt(self, targetCoordinate)
	if target == nil then
		return false
	end
	local movement: TraversalDirection = if targetCoordinate > currentCoordinate then "forward" else "backward"
	return advanceTo(self, target, movement)
end

local function applyClockChange(self: PlaybackImpl, change: ClockChange, sample: ClockSample, clockSerial: number)
	if clockSerial <= self._appliedClockSerial then
		return
	end
	self._appliedClockSerial = clockSerial
	if self._status ~= "playing" then
		return
	end
	local previousClockPosition = change.previousTimePosition or change.currentTimePosition
	if not advanceClockPosition(self, previousClockPosition) then
		return
	end
	self._anchorClock = previousClockPosition
	self._anchorSequence = self._position.unwrappedTimePosition
	self._clockRate = sample.rate

	local changeTarget = derivePosition(self, change.currentTimePosition)
	if changeTarget == nil then
		requestTerminal(self, "failed", "numericOverflow")
		return
	end
	local changeTargetPosition = positionAt(self, changeTarget)
	if changeTargetPosition == nil then
		return
	end
	if change.discontinuous then
		if
			not applyAddressTarget(
				self,
				changeTargetPosition,
				self._sequence:getAddressPolicy(),
				"clockDiscontinuity",
				"clockDiscontinuity" :: AddressCause,
				desiredDirection(self)
			)
		then
			return
		end
	else
		local currentCoordinate = self._position.unwrappedTimePosition
		if changeTarget ~= currentCoordinate then
			local movement: TraversalDirection = if changeTarget > currentCoordinate then "forward" else "backward"
			if not advanceTo(self, changeTargetPosition, movement) then
				return
			end
		end
	end

	self._anchorClock = change.currentTimePosition
	self._anchorSequence = self._position.unwrappedTimePosition
	if sample.timePosition ~= change.currentTimePosition then
		if not advanceClockPosition(self, sample.timePosition) then
			return
		end
	end
	reanchor(self, sample)
	refreshOwnership(self, true)
end

-- Continuous updates

local function updateOverlap(
	fromPosition: number,
	toPosition: number,
	startCoordinate: number,
	endCoordinate: number
): number
	if toPosition >= fromPosition then
		return math.max(0, math.min(toPosition, endCoordinate) - math.max(fromPosition, startCoordinate))
	end
	return -math.max(0, math.min(fromPosition, endCoordinate) - math.max(toPosition, startCoordinate))
end

runPhaseUpdates = function(self: PlaybackImpl, fromPosition: number, toPosition: number)
	local direction: TraversalDirection = if toPosition >= fromPosition then "forward" else "backward"
	local duration = self._sequence:getDuration()
	local firstLoop = if self._sequence:isLooping()
		then math.floor(math.min(fromPosition, toPosition) / duration)
		else 0
	local lastLoop = if self._sequence:isLooping() then math.floor(math.max(fromPosition, toPosition) / duration) else 0
	if lastLoop - firstLoop > MAX_RECONCILIATION_WORK then
		requestTerminal(self, "failed", "catchUpLimitExceeded")
		return
	end
	local step = if direction == "forward" then 1 else -1
	local loopIndex = if direction == "forward" then firstLoop else lastLoop
	local finalLoop = if direction == "forward" then lastLoop else firstLoop
	while true do
		local base = loopIndex * duration
		for _, update in SequenceRuntime.getUpdates(self._sequence) do
			local overlap = updateOverlap(fromPosition, toPosition, base + update.startTime, base + update.endTime)
			local localNow = updateLocalPosition(self, direction)
			local activeNow = if direction == "forward"
				then localNow >= update.startTime and localNow < update.endTime
				else localNow > update.startTime and localNow <= update.endTime
			if overlap ~= 0 or (fromPosition == toPosition and activeNow) then
				self._workCount += 1
				if self._workCount > MAX_RECONCILIATION_WORK then
					requestTerminal(self, "failed", "catchUpLimitExceeded")
					return
				end
				if not pcall(update.run, asControl(self), overlap, localNow, self._context) then
					requestTerminal(self, "failed", "callbackFailed")
					return
				end
				if self._terminalRequest ~= nil then
					return
				end
			end
		end
		if loopIndex == finalLoop then
			break
		end
		loopIndex += step
	end
end

local function applyPhase(self: PlaybackImpl, sample: ClockSample)
	if self._status ~= "playing" or not self._updating then
		return
	end
	local fromPosition = self._updateCursor
	reconcileSample(self, sample, true)
	if self._terminalRequest ~= nil or self._completion ~= nil then
		return
	end
	local currentPosition = self._position.unwrappedTimePosition
	if self._updating and fromPosition == currentPosition then
		runPhaseUpdates(self, currentPosition, currentPosition)
	end
end

-- Mutation serialization and reentrancy

local function applyPause(self: PlaybackImpl, sample: ClockSample)
	if self._status ~= "playing" then
		return
	end
	reconcileSample(self, sample, true, false)
	if self._terminalRequest ~= nil then
		return
	end
	cancelScheduled(self)
	detach(self)
	self._status = "paused"
end

local function applyResume(self: PlaybackImpl, sample: ClockSample, clockSerial: number)
	if self._status ~= "paused" then
		return
	end
	self._appliedClockSerial = math.max(self._appliedClockSerial, clockSerial)
	reanchor(self, sample)
	self._status = "playing"
	if not TemporalAdapter._attach(self._adapter, asPlaybackSink(self)) then
		requestTerminal(self, "failed", "adapterAttachFailed")
		return
	end
	self._attached = true
	refreshOwnership(self, false)
end

local function applySpeed(self: PlaybackImpl, speed: number, sample: ClockSample, clockSerial: number)
	if self._status ~= "playing" and self._status ~= "paused" then
		return
	end
	if self._status == "playing" then
		reconcileSample(self, sample, true, false)
		if self._terminalRequest ~= nil then
			return
		end
	else
		self._appliedClockSerial = math.max(self._appliedClockSerial, clockSerial)
		self._clockRate = sample.rate
	end
	self._playbackSpeed = speed
	reanchor(self, sample)
	if self._status == "playing" then
		refreshOwnership(self, true)
	end
end

local function applySeek(self: PlaybackImpl, address: SequenceAddress, sample: ClockSample, clockSerial: number)
	if self._status == "idle" or self._completion ~= nil then
		return
	end
	local validated = SequenceRuntime.validateAddress(self._sequence, address)
	if self._status == "playing" then
		reconcileSample(self, sample, true, false)
		if self._terminalRequest ~= nil then
			return
		end
	else
		self._appliedClockSerial = math.max(self._appliedClockSerial, clockSerial)
		self._clockRate = sample.rate
	end
	if
		not applyAddressTarget(
			self,
			validated,
			self._sequence:getAddressPolicy(),
			"seekCancelled",
			"seek" :: AddressCause,
			desiredDirection(self)
		)
	then
		return
	end
	reanchor(self, sample)
	if self._status == "playing" then
		refreshOwnership(self, true)
	end
end

local function applyOperation(self: PlaybackImpl, operation: Operation)
	if operation.kind == "clockChange" then
		applyClockChange(self, operation.change, operation.sample, operation.clockSerial)
	elseif operation.kind == "phase" then
		applyPhase(self, operation.sample)
	elseif operation.kind == "reached" then
		if self._status ~= "playing" then
			return
		end
		reconcileReached(self, operation.sample)
	elseif operation.kind == "pause" then
		applyPause(self, operation.sample)
	elseif operation.kind == "resume" then
		applyResume(self, operation.sample, operation.clockSerial)
	elseif operation.kind == "speed" then
		applySpeed(self, operation.speed, operation.sample, operation.clockSerial)
	elseif operation.kind == "seek" then
		applySeek(self, operation.address, operation.sample, operation.clockSerial)
	end
end

local function sampledOperationSerial(operation: Operation): number?
	if operation.kind == "clockChange" then
		return nil
	elseif operation.kind == "phase" or operation.kind == "reached" then
		return operation.clockSerial
	elseif operation.kind == "pause" or operation.kind == "resume" then
		return operation.clockSerial
	elseif operation.kind == "speed" or operation.kind == "seek" then
		return operation.clockSerial
	end
	return nil
end

local function nextOperationIndex(self: PlaybackImpl): number?
	local operation = self._operations[1]
	if operation == nil then
		return nil
	end
	local requiredSerial = sampledOperationSerial(operation)
	if self._status == "paused" or requiredSerial == nil or requiredSerial <= self._appliedClockSerial then
		return 1
	end
	for index = 2, #self._operations do
		local candidate = self._operations[index]
		if
			candidate.kind == "clockChange"
			and candidate.clockSerial > self._appliedClockSerial
			and candidate.clockSerial <= requiredSerial
		then
			return index
		end
	end
	return nil
end

local function drainOperations(self: PlaybackImpl)
	if self._busy or self._completion ~= nil then
		return
	end
	self._busy = true
	while #self._operations > 0 and self._completion == nil and self._terminalRequest == nil do
		local operationIndex = nextOperationIndex(self)
		if operationIndex == nil then
			break
		end
		local operation = table.remove(self._operations, operationIndex)
		assert(operation ~= nil, "Pulse operation queue invariant failed")
		self._workCount += 1
		if self._workCount > MAX_RECONCILIATION_WORK then
			requestTerminal(self, "failed", "catchUpLimitExceeded")
			break
		end
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

local function onReached(self: PlaybackImpl)
	local sample, clockSerial = snapshotClock(self)
	if sample ~= nil then
		enqueue(self, {
			kind = "reached",
			sample = sample,
			clockSerial = clockSerial,
		})
	end
end

local module: RuntimeModule = {
	derivePosition = derivePosition,
	reanchor = reanchor,
	desiredDirection = desiredDirection,
	snapshotClock = snapshotClock,
	refreshOwnership = refreshOwnership,
	drainOperations = drainOperations,
	enqueue = enqueue,
	onReached = onReached,
}

return module
