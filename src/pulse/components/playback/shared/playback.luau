--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback)
local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence)
local TemporalAdapterTypes = require(script.Parent.Parent.Parent.Parent.types.managers.temporalAdapter)
local SequenceRuntime = require(script.Parent.Parent.Parent.sequence.shared.sequence.runtime)
local TemporalAdapter = require(script.Parent.Parent.Parent.Parent.managers.temporalAdapter.shared.temporalAdapter)

type AddressPolicy = DefTypes.AddressPolicy
type AddressCause = DefTypes.AddressCause
type AddressInfo = DefTypes.AddressInfo
type AddressMode = DefTypes.AddressMode
type BoundaryState = PlaybackTypes.BoundaryState
type ClockChange = TemporalAdapterTypes.ClockChange
type ClockSample = TemporalAdapterTypes.ClockSample
type Completion = DefTypes.Completion
type EndedBinding = PlaybackTypes.EndedBinding
type EndedCallback = PlaybackTypes.EndedCallback
type LoopChange = DefTypes.LoopChange
type LoopedBinding = PlaybackTypes.LoopedBinding
type LoopedCallback = PlaybackTypes.LoopedCallback
type Operation = PlaybackTypes.Operation
type Playback = PlaybackTypes.Playback
type PlaybackControl = DefTypes.PlaybackControl
type PlaybackImpl = PlaybackTypes.PlaybackImpl
type PlaybackOptions = PlaybackTypes.PlaybackOptions
type PlaybackPosition = DefTypes.PlaybackPosition
type PlaybackSink = TemporalAdapterTypes.PlaybackSink
type SequenceAddress = DefTypes.SequenceAddress
type SequenceBoundary = SequenceTypes.SequenceBoundary
type Sequence<ContextT> = SequenceTypes.Sequence<ContextT>
type StoredSequence = SequenceTypes.StoredSequence
type Status = DefTypes.Status
type TemporalAdapterType = TemporalAdapterTypes.TemporalAdapter
type TerminalRequest = PlaybackTypes.TerminalRequest
type TerminalStatus = DefTypes.TerminalStatus
type TraversalDirection = DefTypes.TraversalDirection

type PlaybackModule = {
	new: <ContextT>(
		sequence: Sequence<ContextT>,
		adapter: TemporalAdapterType,
		context: ContextT,
		options: PlaybackOptions?
	) -> Playback,
}

local MAX_RECONCILIATION_WORK = 4_096
local DEADLINE_ABSOLUTE_EPSILON = 1e-9
local DEADLINE_RELATIVE_EPSILON = 4.440892098500626e-16

local Playback = {}
Playback.__index = Playback

-- Primitive and direction helpers

local function noopRelease() end

local refreshOwnership: (self: PlaybackImpl, preserveTask: boolean) -> ()
local runPhaseUpdates: (self: PlaybackImpl, fromPosition: number, toPosition: number) -> ()
local reconcileSample: (self: PlaybackImpl, sample: ClockSample, preserveTask: boolean, refreshAfter: boolean?) -> ()

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function validateInitialMode(mode: AddressMode?): AddressMode
	local resolved: AddressMode = if mode == nil then "reconstruct" :: AddressMode else mode
	assert(resolved == "reconstruct" or resolved == "skip", "Pulse initialMode must be 'reconstruct' or 'skip'")
	return resolved
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

local function publicPosition(position: PlaybackPosition): PlaybackPosition
	return {
		timePosition = position.timePosition,
		loopIndex = position.loopIndex,
		unwrappedTimePosition = position.unwrappedTimePosition,
	}
end

-- Lifecycle and cleanup

local function cancelScheduled(self: PlaybackImpl)
	local id = self._scheduledId
	self._scheduledId = nil
	self._scheduledDirection = nil
	self._scheduledBoundary = nil
	if id ~= nil then
		TemporalAdapter._cancel(self._adapter, id)
	end
end

local function stopUpdating(self: PlaybackImpl)
	if self._updating then
		self._updating = false
		TemporalAdapter._setUpdating(self._adapter, asPlaybackSink(self), false)
	end
end

local function detach(self: PlaybackImpl)
	stopUpdating(self)
	if self._attached then
		self._attached = false
		TemporalAdapter._detach(self._adapter, asPlaybackSink(self))
	end
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
	cancelScheduled(self)
	detach(self)
	if not disposeGeneration(self) and status ~= "failed" then
		status = "failed"
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

-- Event and boundary traversal

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
	local authored = SequenceRuntime.getOnAddress(self._sequence)
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
	local authored = SequenceRuntime.getOnLoop(self._sequence)
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
			requestTerminal(self, "failed", "numericOverflow")
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
			requestTerminal(self, "failed", "numericOverflow")
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

-- Discontinuities and reconstruction

local function beginGeneration(self: PlaybackImpl, target: PlaybackPosition, disposeCurrent: boolean): boolean
	if disposeCurrent and not disposeGeneration(self) then
		requestTerminal(self, "failed", "cleanupFailed")
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
	self._updateCursor = self._position.unwrappedTimePosition
	return true
end

local function placeWithoutTraversal(self: PlaybackImpl, target: PlaybackPosition)
	local boundary = SequenceRuntime.boundaryAt(self._sequence, target)
	self._position = boundary or target
	local direction = desiredDirection(self)
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
	cause: AddressCause
): boolean
	if policy == "cancel" then
		requestTerminal(self, "cancelled", reason)
		return false
	end

	local from = publicPosition(self._position)
	if policy == "rebuild" then
		if not reconstructTo(self, target, true) then
			return false
		end
		return emitAddress(self, cause, "reconstruct" :: AddressMode, from)
	else
		placeWithoutTraversal(self, target)
		return emitAddress(self, cause, "skip" :: AddressMode, from)
	end
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
				"clockDiscontinuity" :: AddressCause
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
			"seek" :: AddressCause
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

-- Construction and public methods

local function ConstructPlayback<ContextT>(
	sequence: Sequence<ContextT>,
	adapter: TemporalAdapterType,
	context: ContextT,
	options: PlaybackOptions?
): Playback
	local config: PlaybackOptions = options or {}
	local speed = config.playbackSpeed or 1
	local initialMode = validateInitialMode(config.initialMode)
	assert(isFinite(speed), "Pulse playbackSpeed must be finite")
	local storedSequence = (sequence :: unknown) :: StoredSequence
	local initial = SequenceRuntime.validateAddress(storedSequence, config.position or { timePosition = 0 })
	local self: PlaybackImpl
	local function reachedCallback(_now: number, _direction: unknown)
		local sample, clockSerial = snapshotClock(self)
		if sample ~= nil then
			enqueue(self, {
				kind = "reached",
				sample = sample,
				clockSerial = clockSerial,
			})
		end
	end
	self = (
		setmetatable({
			_sequence = storedSequence,
			_context = context,
			_adapter = adapter,
			_status = "idle" :: Status,
			_completion = nil,
			_playbackSpeed = speed,
			_anchorClock = 0,
			_anchorSequence = initial.unwrappedTimePosition,
			_clockRate = 0,
			_position = initial,
			_initialPosition = initial,
			_initialMode = initialMode,
			_boundaryState = nil,
			_direction = nil,
			_scheduledId = nil,
			_scheduledDirection = nil,
			_scheduledBoundary = nil,
			_attached = false,
			_updating = false,
			_updateCursor = initial.unwrappedTimePosition,
			_cleanup = {},
			_endedBindings = {},
			_loopedBindings = {},
			_operations = {},
			_busy = false,
			_finishing = false,
			_deliveringEnded = false,
			_terminalRequest = nil,
			_reachedCallback = reachedCallback,
			_workCount = 0,
			_appliedClockSerial = 0,
		}, Playback) :: unknown
	) :: PlaybackImpl
	return self
end

function Playback.play(self: PlaybackImpl): Playback
	if self._status ~= "idle" or self._finishing then
		return self
	end
	local sample, clockSerial = TemporalAdapter._snapshot(self._adapter)
	if sample == nil then
		finish(self, "failed", "clockReadFailed")
		return self
	end
	self._status = "playing"
	self._anchorClock = sample.timePosition
	self._anchorSequence = self._initialPosition.unwrappedTimePosition
	self._clockRate = sample.rate
	self._appliedClockSerial = clockSerial
	self._position = self._initialPosition
	if not TemporalAdapter._attach(self._adapter, asPlaybackSink(self)) then
		finish(self, "failed", "adapterAttachFailed")
		return self
	end
	self._attached = true

	self._busy = true
	self._workCount = 0
	local initialized: boolean
	if self._initialMode == "reconstruct" then
		initialized = reconstructTo(self, self._initialPosition, false)
	else
		initialized = beginGeneration(self, self._initialPosition, false)
		if initialized then
			placeWithoutTraversal(self, self._initialPosition)
		end
	end
	if initialized then
		emitAddress(self, "initial" :: AddressCause, self._initialMode, nil)
	end
	if self._terminalRequest == nil and self._sequence:getDuration() == 0 then
		requestTerminal(self, "completed", nil)
	end
	if self._terminalRequest == nil then
		reanchor(self, sample)
		refreshOwnership(self, false)
	end
	local terminal = self._terminalRequest
	self._terminalRequest = nil
	self._busy = false
	if terminal ~= nil then
		finish(self, terminal.status, terminal.reason)
	else
		drainOperations(self)
	end
	return self
end

function Playback.pause(self: PlaybackImpl)
	if self._status ~= "playing" or self._finishing or self._terminalRequest ~= nil then
		return
	end
	local sample, clockSerial = snapshotClock(self)
	if sample ~= nil then
		enqueue(self, {
			kind = "pause",
			sample = sample,
			clockSerial = clockSerial,
		})
	end
end

function Playback.resume(self: PlaybackImpl)
	if self._status ~= "paused" or self._finishing or self._terminalRequest ~= nil then
		return
	end
	local sample, clockSerial = snapshotClock(self)
	if sample ~= nil then
		enqueue(self, {
			kind = "resume",
			sample = sample,
			clockSerial = clockSerial,
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
		local sample, clockSerial = snapshotClock(self)
		if sample ~= nil then
			enqueue(self, {
				kind = "speed",
				speed = speed,
				sample = sample,
				clockSerial = clockSerial,
			})
		end
	end
end

function Playback.getPlaybackSpeed(self: PlaybackImpl): number
	return self._playbackSpeed
end

function Playback.seek(self: PlaybackImpl, address: SequenceAddress): boolean
	local validated = SequenceRuntime.validateAddress(self._sequence, address)
	if self._status == "idle" or self._completion ~= nil or self._finishing or self._terminalRequest ~= nil then
		return false
	end
	local sample, clockSerial = snapshotClock(self)
	if sample == nil then
		return false
	end
	enqueue(self, {
		kind = "seek",
		address = {
			timePosition = validated.timePosition,
			loopIndex = validated.loopIndex,
		},
		sample = sample,
		clockSerial = clockSerial,
	})
	return true
end

function Playback.getPosition(self: PlaybackImpl): PlaybackPosition
	if self._status == "playing" and not self._busy and not self._finishing then
		local sample, clockSerial = TemporalAdapter._snapshot(self._adapter)
		if sample == nil then
			requestTerminal(self, "failed", "clockReadFailed")
		elseif clockSerial > self._appliedClockSerial then
			return publicPosition(self._position)
		else
			local target = derivePosition(self, sample.timePosition)
			if target ~= nil then
				if target == self._position.unwrappedTimePosition then
					return publicPosition(self._position)
				end
				local ok, position = pcall(SequenceRuntime.positionAt, self._sequence, target)
				if ok then
					return position
				end
			end
			requestTerminal(self, "failed", "numericOverflow")
		end
	end
	return publicPosition(self._position)
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

function Playback.destroy(self: PlaybackImpl)
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

function Playback._onAdapterClockChanged(
	self: PlaybackImpl,
	change: ClockChange,
	sample: ClockSample,
	clockSerial: number
)
	enqueue(self, {
		kind = "clockChange",
		change = change,
		sample = sample,
		clockSerial = clockSerial,
	})
end

function Playback._onAdapterPhase(self: PlaybackImpl, sample: ClockSample, clockSerial: number)
	enqueue(self, {
		kind = "phase",
		sample = sample,
		clockSerial = clockSerial,
	})
end

function Playback._onAdapterDestroyed(self: PlaybackImpl, reason: string)
	requestTerminal(self, "failed", reason)
end

local module: PlaybackModule = {
	new = ConstructPlayback,
}

return module
