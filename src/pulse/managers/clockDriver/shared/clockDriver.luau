--!strict
--!optimize 2
--!native

local PlaybackTraversalTypes =
	require(script.Parent.Parent.Parent.Parent.types.components.playback.shared.playbackTraversal)
local ClockDriverVocabulary =
	require(script.Parent.Parent.Parent.Parent.common.clockDriver.shared.clockDriverVocabulary)

local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.types.def.playback.shared.playbackDefinitions)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback.shared.playback)
local ClockDriverTypes = require(script.Parent.Parent.Parent.Parent.types.managers.clockDriver.shared.clockDriver)
local DrivenPlaybackTypes =
	require(script.Parent.Parent.Parent.Parent.types.managers.clockDriver.shared.clockDriver.drivenPlayback)
local ClockDriverNotifications =
	require(script.Parent.Parent.Parent.Parent.types.managers.clockDriver.shared.clockDriver.clockDriverNotifications)
local ProviderClockTypes = require(script.Parent.Parent.Parent.Parent.types.ports.components.clock.shared.providerClock)
local DrivenPlayback = require(script.Parent.drivenPlayback)
local PlaybackVocabulary = require(script.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)

type AddressMode = PlaybackVocabulary.AddressMode
type ClockDriver = ClockDriverTypes.ClockDriver
type ClockDriverAttachmentOptions = ClockDriverTypes.ClockDriverAttachmentOptions
type Completion = PlaybackDefinitions.Completion
type DirectionTokens<DirectionTokenT> = ProviderClockTypes.DirectionTokens<DirectionTokenT>
type DrivenPlayback = DrivenPlaybackTypes.DrivenPlayback
type DriverDiscontinuityMode = ClockDriverTypes.DriverDiscontinuityMode
type EndedCallback = PlaybackTypes.EndedCallback
type LoopedCallback = PlaybackTypes.LoopedCallback
type PhaseCallback = ProviderClockTypes.PhaseCallback
type Playback = PlaybackTypes.Playback
type PlaybackPosition = PlaybackDefinitions.PlaybackPosition
type ProviderClock<PhaseInputT, DirectionTokenT> = ProviderClockTypes.ProviderClock<PhaseInputT, DirectionTokenT>
type RawClockChangedCallback = ProviderClockTypes.RawClockChangedCallback
type ReachedCallback = ProviderClockTypes.ReachedCallback
type Release = PlaybackDefinitions.Release
type ScheduledTaskId = ProviderClockTypes.ScheduledTaskId
type SequenceAddress = PlaybackDefinitions.SequenceAddress
type Status = PlaybackVocabulary.Status
type StoredProviderClock = ProviderClockTypes.StoredProviderClock
type TimeSample = PlaybackDefinitions.TimeSample
type TraversalForecast = PlaybackTraversalTypes.TraversalForecast
type TraversalDirection = PlaybackVocabulary.TraversalDirection

type ClockDriverImpl = ClockDriverTypes.ClockDriverImpl
type DrivenPlaybackImpl = DrivenPlaybackTypes.DrivenPlaybackImpl
type PlaybackDriven = PlaybackTypes.PlaybackDriven
type ProviderClockChange = ClockDriverNotifications.ProviderClockChange
type ClockDriverControlKind = ClockDriverVocabulary.ClockDriverControlKind
type ClockDriverClockNotification = ClockDriverNotifications.ClockDriverClockNotification
type ClockDriverPhaseNotification = ClockDriverNotifications.ClockDriverPhaseNotification
type ClockDriverReachedNotification = ClockDriverNotifications.ClockDriverReachedNotification<DrivenPlayback>
type ClockDriverControlNotification = ClockDriverNotifications.ClockDriverControlNotification<DrivenPlayback>
type ClockDriverNotification = ClockDriverNotifications.ClockDriverNotification<DrivenPlayback>

type ClockDriverModule = {
	new: <PhaseInputT, DirectionTokenT>(
		clock: ProviderClock<PhaseInputT, DirectionTokenT>,
		phase: PhaseInputT,
		directions: DirectionTokens<DirectionTokenT>
	) -> ClockDriver,
}

local MAX_DRIVER_WORK = 4_096
local DOUBLE_EPSILON = 2 ^ -52
-- The exercised 128-tick forward and backward profiles stay below ten scaled epsilon units.
local DEADLINE_TOLERANCE = 16 * DOUBLE_EPSILON

local drivenPlaybackByPlayback = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Playback]: DrivenPlaybackImpl }

local dispatchNotifications: (self: ClockDriverImpl) -> ()
local refreshDrivenPlayback: (
	self: ClockDriverImpl,
	drivenPlayback: DrivenPlaybackImpl,
	currentSample: TimeSample?,
	reachedTaskFired: boolean?
) -> ()

local function isFinite(value: number): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sameSourceCoordinate(first: number, second: number): boolean
	local magnitude = math.max(1, math.abs(first), math.abs(second))
	return math.abs(first - second) <= DEADLINE_TOLERANCE * magnitude
end

local function asDrivenPlayback(drivenPlayback: DrivenPlayback): DrivenPlaybackImpl
	return (drivenPlayback :: unknown) :: DrivenPlaybackImpl
end

local function assertProviderSample(value: unknown): TimeSample
	assert(type(value) == "table", "Pulse provider read must return a table")
	local fields = value :: { [string]: unknown }
	local position = fields.timePosition
	local rate = fields.rate
	assert(type(position) == "number" and isFinite(position), "Pulse provider timePosition must be finite")
	assert(type(rate) == "number" and isFinite(rate), "Pulse provider rate must be finite")
	return {
		position = position,
		rate = rate,
	}
end

local function assertProviderChange(value: unknown): ProviderClockChange
	assert(type(value) == "table", "Pulse provider change must be a table")
	local fields = value :: { [string]: unknown }
	local kind = fields.kind
	local previous = fields.previousTimePosition
	local current = fields.currentTimePosition
	local discontinuous = fields.discontinuous
	assert(kind == nil or type(kind) == "string", "Pulse provider change kind must be a string")
	assert(
		previous == nil or (type(previous) == "number" and isFinite(previous)),
		"Pulse provider previousTimePosition must be finite"
	)
	assert(type(current) == "number" and isFinite(current), "Pulse provider currentTimePosition must be finite")
	assert(type(discontinuous) == "boolean", "Pulse provider discontinuous must be boolean")
	return {
		kind = kind :: string?,
		previousPosition = previous :: number?,
		currentPosition = current,
		discontinuous = discontinuous,
	}
end

local function validateDiscontinuityMode(mode: DriverDiscontinuityMode): DriverDiscontinuityMode
	assert(
		mode == "skip" or mode == "reconstruct" or mode == "cancel",
		"Pulse discontinuityMode must be 'skip', 'reconstruct', or 'cancel'"
	)
	return mode
end

local function releaseSafely(release: Release?)
	if release ~= nil then
		pcall(release)
	end
end

local function clockIsDestroyed(self: ClockDriverImpl): boolean
	local ok, destroyed = pcall(self._providerClock.isDestroyed, self._providerClock)
	return not ok or destroyed ~= false
end

local function readClock(self: ClockDriverImpl): TimeSample?
	if self._destroyed or clockIsDestroyed(self) then
		return nil
	end
	local readOk, rawSample = pcall(self._providerClock.read, self._providerClock)
	if not readOk then
		return nil
	end
	local parseOk, sample = pcall(assertProviderSample, rawSample)
	return if parseOk then sample else nil
end

local function findMember(values: { DrivenPlayback }, candidate: DrivenPlayback): number?
	for index, value in values do
		if value == candidate then
			return index
		end
	end
	return nil
end

local function removeMember(
	values: { DrivenPlayback },
	membership: { [DrivenPlayback]: true },
	candidate: DrivenPlayback
): boolean
	if membership[candidate] == nil then
		return false
	end
	local index = findMember(values, candidate)
	assert(index ~= nil, "Pulse driver membership invariant failed")
	table.remove(values, index)
	membership[candidate] = nil
	return true
end

local function cancelScheduled(self: ClockDriverImpl, drivenPlayback: DrivenPlaybackImpl)
	local id = drivenPlayback._scheduledId
	drivenPlayback._scheduledId = nil
	drivenPlayback._scheduledSourcePosition = nil
	drivenPlayback._scheduledDirection = nil
	drivenPlayback._taskGeneration += 1
	if id ~= nil then
		pcall(self._providerClock.cancel, self._providerClock, id)
	end
end

local function setPhaseRequired(self: ClockDriverImpl, drivenPlayback: DrivenPlaybackImpl, required: boolean): boolean
	local publicDrivenPlayback = (drivenPlayback :: unknown) :: DrivenPlayback
	if required then
		if self._destroyed or not drivenPlayback._active then
			return false
		end
		if self._phaseMembership[publicDrivenPlayback] ~= nil then
			return true
		end
		if #self._phaseDrivenPlaybacks == 0 then
			local ok, release =
				pcall(self._providerClock.bindPhase, self._providerClock, self._phase, self._phaseCallback)
			if not ok or type(release) ~= "function" then
				return false
			end
			self._phaseRelease = release
		end
		table.insert(self._phaseDrivenPlaybacks, publicDrivenPlayback)
		self._phaseMembership[publicDrivenPlayback] = true
		return true
	end

	if removeMember(self._phaseDrivenPlaybacks, self._phaseMembership, publicDrivenPlayback) then
		if #self._phaseDrivenPlaybacks == 0 then
			local release = self._phaseRelease
			self._phaseRelease = nil
			releaseSafely(release)
		end
	end
	return true
end

local function deactivateDrivenPlayback(self: ClockDriverImpl, drivenPlayback: DrivenPlaybackImpl)
	if not drivenPlayback._active then
		return
	end
	cancelScheduled(self, drivenPlayback)
	setPhaseRequired(self, drivenPlayback, false)
	drivenPlayback._active = false
	local publicDrivenPlayback = (drivenPlayback :: unknown) :: DrivenPlayback
	if removeMember(self._active, self._activeMembership, publicDrivenPlayback) and #self._active == 0 then
		local release = self._changedRelease
		self._changedRelease = nil
		releaseSafely(release)
	end
end

local function retireDrivenPlayback(self: ClockDriverImpl, drivenPlayback: DrivenPlaybackImpl)
	if not drivenPlayback._attached then
		return
	end
	deactivateDrivenPlayback(self, drivenPlayback)
	drivenPlayback._attached = false
	if drivenPlaybackByPlayback[drivenPlayback._playback] == drivenPlayback then
		drivenPlaybackByPlayback[drivenPlayback._playback] = nil
	end
	local publicDrivenPlayback = (drivenPlayback :: unknown) :: DrivenPlayback
	removeMember(self._drivenPlaybacks, self._drivenPlaybackMembership, publicDrivenPlayback)
	local endedRelease = drivenPlayback._endedRelease
	drivenPlayback._endedRelease = nil
	releaseSafely(endedRelease)
end

local function activateDrivenPlayback(self: ClockDriverImpl, drivenPlayback: DrivenPlaybackImpl): boolean
	if drivenPlayback._active then
		return true
	end
	if self._destroyed or clockIsDestroyed(self) then
		return false
	end
	if #self._active == 0 then
		local ok, release = pcall(self._providerClock.bindToChanged, self._providerClock, self._changedCallback, false)
		if not ok or type(release) ~= "function" then
			return false
		end
		self._changedRelease = release
	end
	local publicDrivenPlayback = (drivenPlayback :: unknown) :: DrivenPlayback
	table.insert(self._active, publicDrivenPlayback)
	self._activeMembership[publicDrivenPlayback] = true
	drivenPlayback._active = true
	return true
end

local function terminateDriver(self: ClockDriverImpl, reason: string)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._notifications = {}
	local drivenPlaybacks = table.clone(self._drivenPlaybacks)
	for _, publicDrivenPlayback in drivenPlaybacks do
		local drivenPlayback = asDrivenPlayback(publicDrivenPlayback)
		cancelScheduled(self, drivenPlayback)
		drivenPlayback._active = false
		drivenPlayback._attached = false
		drivenPlayback._endedRelease = nil
		if drivenPlaybackByPlayback[drivenPlayback._playback] == drivenPlayback then
			drivenPlaybackByPlayback[drivenPlayback._playback] = nil
		end
	end
	table.clear(self._drivenPlaybacks)
	table.clear(self._drivenPlaybackMembership)
	table.clear(self._active)
	table.clear(self._activeMembership)
	table.clear(self._phaseDrivenPlaybacks)
	table.clear(self._phaseMembership)
	local changedRelease = self._changedRelease
	local phaseRelease = self._phaseRelease
	self._changedRelease = nil
	self._phaseRelease = nil
	releaseSafely(phaseRelease)
	releaseSafely(changedRelease)
	for _, publicDrivenPlayback in drivenPlaybacks do
		asDrivenPlayback(publicDrivenPlayback)._playback:fail(reason)
	end
end

local function enqueueNotification(self: ClockDriverImpl, notification: ClockDriverNotification)
	if self._destroyed then
		return
	end
	table.insert(self._notifications, notification)
	dispatchNotifications(self)
end

local function hasPendingClockNotification(self: ClockDriverImpl): boolean
	for _, notification in self._notifications do
		if notification.kind == "clock" then
			return true
		end
	end
	return false
end

local function readForEvaluation(self: ClockDriverImpl): TimeSample?
	local sample = readClock(self)
	if sample == nil then
		terminateDriver(self, if clockIsDestroyed(self) then "clockDestroyed" else "clockReadFailed")
		return nil
	end
	self._lastSample = sample
	return sample
end

local function evaluateCurrent(self: ClockDriverImpl, drivenPlayback: DrivenPlaybackImpl): TimeSample?
	local sample = readForEvaluation(self)
	if sample == nil then
		return nil
	end
	return if drivenPlayback._playback:evaluate(sample) then sample else nil
end

local function scheduleNext(
	self: ClockDriverImpl,
	drivenPlayback: DrivenPlaybackImpl,
	initialState: TraversalForecast,
	initialSample: TimeSample?,
	reachedTaskFired: boolean
)
	local attempts = 0
	local state: TraversalForecast? = initialState
	local current: TimeSample? = initialSample
	local taskFired = reachedTaskFired
	while drivenPlayback._attached and drivenPlayback._active and drivenPlayback._playback:getStatus() == "playing" do
		attempts += 1
		if attempts > MAX_DRIVER_WORK then
			drivenPlayback._playback:fail("driverWorkLimitExceeded")
			return
		end
		local forecast: TraversalForecast = state or drivenPlayback._forecast
		if state == nil then
			drivenPlayback._playback:writeTraversalForecastInto(forecast)
		end
		state = nil
		if not drivenPlayback._attached or drivenPlayback._playback:getStatus() ~= "playing" then
			return
		end
		local runAt = forecast.sourceBoundary
		local direction = forecast.sourceDirection
		if runAt == nil or direction == nil then
			cancelScheduled(self, drivenPlayback)
			return
		end
		local id = drivenPlayback._scheduledId
		local scheduledSourcePosition = drivenPlayback._scheduledSourcePosition
		local equivalent = false
		local effectiveRunAt = runAt
		if
			id ~= nil
			and drivenPlayback._scheduledDirection == direction
			and scheduledSourcePosition ~= nil
			and sameSourceCoordinate(scheduledSourcePosition, runAt)
		then
			equivalent = true
			effectiveRunAt = scheduledSourcePosition
		end

		if current == nil then
			current = readForEvaluation(self)
		end
		if current == nil then
			return
		end
		local alreadyReached = if direction == "forward"
			then current.position >= effectiveRunAt
			else current.position <= effectiveRunAt
		if alreadyReached then
			cancelScheduled(self, drivenPlayback)
			drivenPlayback._playback:evaluate(current)
			if hasPendingClockNotification(self) then
				return
			end
			taskFired = false
			continue
		end

		if equivalent and not taskFired then
			return
		end

		local reused = false
		if id ~= nil and drivenPlayback._scheduledDirection == direction then
			local ok, rescheduled =
				pcall(self._providerClock.rescheduleAt, self._providerClock, id, effectiveRunAt, self._phase)
			reused = ok and rescheduled == true
			if reused then
				drivenPlayback._scheduledSourcePosition = effectiveRunAt
			end
		end
		if not reused then
			cancelScheduled(self, drivenPlayback)
			drivenPlayback._taskGeneration += 1
			local generation = drivenPlayback._taskGeneration
			local publicDrivenPlayback = (drivenPlayback :: unknown) :: DrivenPlayback
			local function reachedCallback(_now: number, actualDirection: unknown)
				enqueueNotification(self, {
					kind = "reached" :: "reached",
					drivenPlayback = publicDrivenPlayback,
					generation = generation,
					direction = actualDirection,
				})
			end
			local callback: ReachedCallback = reachedCallback
			local token = if direction == "forward" then self._directions.forward else self._directions.backward
			local ok, scheduled = pcall(
				self._providerClock.bindToReached,
				self._providerClock,
				effectiveRunAt,
				token,
				callback,
				self._phase
			)
			if not ok or type(scheduled) ~= "number" then
				drivenPlayback._playback:fail("scheduleFailed")
				return
			end
			drivenPlayback._scheduledId = scheduled
			drivenPlayback._scheduledSourcePosition = effectiveRunAt
			drivenPlayback._scheduledDirection = direction :: TraversalDirection
		end

		if hasPendingClockNotification(self) then
			return
		end
		local validation = readForEvaluation(self)
		if validation == nil then
			return
		end
		local passedWhileScheduling = if direction == "forward"
			then validation.position >= effectiveRunAt
			else validation.position <= effectiveRunAt
		if not passedWhileScheduling then
			return
		end
		cancelScheduled(self, drivenPlayback)
		drivenPlayback._playback:evaluate(validation)
		if hasPendingClockNotification(self) then
			return
		end
		current = validation
		taskFired = false
	end
end

refreshDrivenPlayback = function(
	self: ClockDriverImpl,
	drivenPlayback: DrivenPlaybackImpl,
	currentSample: TimeSample?,
	reachedTaskFired: boolean?
)
	if not drivenPlayback._attached then
		return
	end
	if hasPendingClockNotification(self) then
		return
	end
	local status = drivenPlayback._playback:getStatus()
	if status ~= "playing" then
		cancelScheduled(self, drivenPlayback)
		setPhaseRequired(self, drivenPlayback, false)
		if not drivenPlayback._playback:isAlive() then
			retireDrivenPlayback(self, drivenPlayback)
		end
		return
	end
	if not drivenPlayback._active and not activateDrivenPlayback(self, drivenPlayback) then
		if clockIsDestroyed(self) then
			terminateDriver(self, "clockDestroyed")
		else
			drivenPlayback._playback:fail("driverAttachFailed")
		end
		return
	end
	local state = drivenPlayback._forecast
	drivenPlayback._playback:writeTraversalForecastInto(state)
	if not setPhaseRequired(self, drivenPlayback, state.phaseRequired) then
		drivenPlayback._playback:fail("phaseBindFailed")
		return
	end
	scheduleNext(self, drivenPlayback, state, currentSample, reachedTaskFired == true)
end

local function applyClockChangeToDrivenPlayback(
	self: ClockDriverImpl,
	drivenPlayback: DrivenPlaybackImpl,
	change: ProviderClockChange,
	previousSample: TimeSample,
	sample: TimeSample
)
	if
		not drivenPlayback._attached
		or not drivenPlayback._active
		or drivenPlayback._playback:getStatus() ~= "playing"
	then
		return
	end
	local previousPosition = change.previousPosition or previousSample.position
	local scratch = self._sampleScratch
	if change.discontinuous then
		scratch.position, scratch.rate = previousPosition, previousSample.rate
		drivenPlayback._playback:evaluate(scratch)
		if drivenPlayback._playback:getStatus() ~= "playing" then
			refreshDrivenPlayback(self, drivenPlayback, sample)
			return
		end
		local target = drivenPlayback._playback:projectSourcePosition(change.currentPosition)
		if target == nil then
			refreshDrivenPlayback(self, drivenPlayback, sample)
			return
		end
		if drivenPlayback._discontinuityMode == "cancel" then
			drivenPlayback._playback:cancel("clockDiscontinuity")
		else
			scratch.position, scratch.rate = change.currentPosition, sample.rate
			drivenPlayback._playback:acceptSourceSample(scratch)
			drivenPlayback._playback:seek({
				timePosition = target.timePosition,
				loopIndex = target.loopIndex,
			}, drivenPlayback._discontinuityMode)
			if drivenPlayback._playback:getStatus() == "playing" and sample.position ~= change.currentPosition then
				drivenPlayback._playback:evaluate(sample)
			end
		end
	else
		scratch.position, scratch.rate = previousPosition, sample.rate
		drivenPlayback._playback:evaluate(scratch)
		if drivenPlayback._playback:getStatus() == "playing" and change.currentPosition ~= previousPosition then
			scratch.position, scratch.rate = change.currentPosition, sample.rate
			drivenPlayback._playback:evaluate(scratch)
		end
		if drivenPlayback._playback:getStatus() == "playing" and sample.position ~= change.currentPosition then
			drivenPlayback._playback:evaluate(sample)
		end
	end
	refreshDrivenPlayback(self, drivenPlayback, sample)
end

local function snapshotDrivenPlaybacks(self: ClockDriverImpl, drivenPlaybacks: { DrivenPlayback }): { DrivenPlayback }
	-- Notifications serialize dispatch, so callbacks cannot overwrite the active snapshot.
	local snapshot = self._dispatchDrivenPlaybacks
	table.clear(snapshot)
	table.move(drivenPlaybacks, 1, #drivenPlaybacks, 1, snapshot)
	return snapshot
end

local function applyClockNotification(self: ClockDriverImpl, notification: ClockDriverClockNotification)
	local snapshot = snapshotDrivenPlaybacks(self, self._active)
	for _, publicDrivenPlayback in snapshot do
		if self._activeMembership[publicDrivenPlayback] ~= nil then
			applyClockChangeToDrivenPlayback(
				self,
				asDrivenPlayback(publicDrivenPlayback),
				notification.change,
				notification.previousSample,
				notification.sample
			)
		end
	end
	table.clear(snapshot)
end

local function applyPhaseNotification(self: ClockDriverImpl, notification: ClockDriverPhaseNotification)
	local snapshot = snapshotDrivenPlaybacks(self, self._phaseDrivenPlaybacks)
	for _, publicDrivenPlayback in snapshot do
		if self._phaseMembership[publicDrivenPlayback] ~= nil then
			local drivenPlayback = asDrivenPlayback(publicDrivenPlayback)
			local reachedSample = drivenPlayback._reachedSample
			drivenPlayback._reachedSample = nil
			if
				reachedSample == nil
				or reachedSample.position ~= notification.sample.position
				or reachedSample.rate ~= notification.sample.rate
			then
				drivenPlayback._playback:evaluate(notification.sample)
			end
			refreshDrivenPlayback(self, drivenPlayback, notification.sample)
		end
	end
	table.clear(snapshot)
end

local function applyReachedNotification(self: ClockDriverImpl, notification: ClockDriverReachedNotification)
	local drivenPlayback = asDrivenPlayback(notification.drivenPlayback)
	if
		not drivenPlayback._attached
		or not drivenPlayback._active
		or drivenPlayback._taskGeneration ~= notification.generation
		or drivenPlayback._scheduledId == nil
	then
		return
	end
	local scheduledDirection = drivenPlayback._scheduledDirection
	local expectedToken = if scheduledDirection == "forward"
		then self._directions.forward
		elseif scheduledDirection == "backward" then self._directions.backward
		else nil
	if expectedToken == nil or notification.direction ~= expectedToken then
		drivenPlayback._playback:fail("invalidReachedDirection")
		return
	end
	local sample = readForEvaluation(self)
	if sample == nil then
		return
	end
	drivenPlayback._playback:evaluate(sample)
	drivenPlayback._reachedSample = sample
	refreshDrivenPlayback(self, drivenPlayback, sample, true)
end

local function applyControlNotification(self: ClockDriverImpl, notification: ClockDriverControlNotification)
	local drivenPlayback = asDrivenPlayback(notification.drivenPlayback)
	if not drivenPlayback._attached then
		notification.result = false
		return
	end
	local playback = drivenPlayback._playback
	if notification.operation == "play" then
		if playback:getStatus() ~= "idle" then
			return
		end
		if not activateDrivenPlayback(self, drivenPlayback) then
			if clockIsDestroyed(self) then
				terminateDriver(self, "clockDestroyed")
			else
				drivenPlayback._playback:fail("driverAttachFailed")
			end
			return
		end
		local sample = readForEvaluation(self)
		if sample ~= nil then
			playback:play(sample)
			refreshDrivenPlayback(self, drivenPlayback, sample)
		end
	elseif notification.operation == "pause" then
		if playback:getStatus() == "playing" then
			evaluateCurrent(self, drivenPlayback)
			playback:pause()
			refreshDrivenPlayback(self, drivenPlayback)
		end
	elseif notification.operation == "resume" then
		if playback:getStatus() == "paused" then
			local sample = readForEvaluation(self)
			if sample ~= nil then
				playback:resume()
				playback:evaluate(sample)
				refreshDrivenPlayback(self, drivenPlayback, sample)
			end
		end
	elseif notification.operation == "speed" then
		local currentSample: TimeSample? = nil
		if playback:getStatus() == "playing" then
			currentSample = evaluateCurrent(self, drivenPlayback)
		end
		local speed = notification.speed
		if speed ~= nil then
			playback:setPlaybackSpeed(speed)
			refreshDrivenPlayback(self, drivenPlayback, currentSample)
		end
	elseif notification.operation == "seek" then
		local currentSample: TimeSample? = nil
		if playback:getStatus() == "playing" then
			currentSample = evaluateCurrent(self, drivenPlayback)
		end
		local address = notification.address
		local mode = notification.mode
		if address ~= nil and mode ~= nil then
			notification.result = playback:seek(address, mode :: AddressMode)
			refreshDrivenPlayback(self, drivenPlayback, currentSample)
		end
	elseif notification.operation == "cleanup" then
		if playback:getStatus() == "playing" then
			evaluateCurrent(self, drivenPlayback)
		end
		local cleanup = notification.cleanup
		if cleanup ~= nil then
			playback:addCleanup(cleanup)
		end
	elseif notification.operation == "cancel" then
		if playback:getStatus() == "playing" then
			evaluateCurrent(self, drivenPlayback)
		end
		if playback:isAlive() then
			playback:cancel(notification.reason)
		end
	elseif notification.operation == "deconstruct" then
		if playback:getStatus() == "playing" then
			evaluateCurrent(self, drivenPlayback)
		end
		if playback:isAlive() then
			playback:deconstruct()
		end
	elseif notification.operation == "detach" then
		if playback:getStatus() == "playing" then
			evaluateCurrent(self, drivenPlayback)
		end
		retireDrivenPlayback(self, drivenPlayback)
	end
end

dispatchNotifications = function(self: ClockDriverImpl)
	if self._notifying or self._destroyed then
		return
	end
	self._notifying = true
	local workCount = 0
	while #self._notifications > 0 and not self._destroyed do
		workCount += 1
		if workCount > MAX_DRIVER_WORK then
			terminateDriver(self, "driverWorkLimitExceeded")
			break
		end
		local notification = table.remove(self._notifications, 1)
		assert(notification ~= nil, "Pulse driver notification queue invariant failed")
		if notification.kind == "clock" then
			applyClockNotification(self, notification)
		elseif notification.kind == "phase" then
			applyPhaseNotification(self, notification)
		elseif notification.kind == "reached" then
			applyReachedNotification(self, notification)
		else
			applyControlNotification(self, notification)
		end
	end
	self._notifying = false
end

local function notifyClockChange(self: ClockDriverImpl, rawChange: unknown)
	if self._destroyed then
		return
	end
	local parseOk, change = pcall(assertProviderChange, rawChange)
	if not parseOk then
		terminateDriver(self, "invalidClockChange")
		return
	end
	if clockIsDestroyed(self) or change.kind == "destroyed" then
		terminateDriver(self, "clockDestroyed")
		return
	end
	local sample = readClock(self)
	if sample == nil then
		terminateDriver(self, if clockIsDestroyed(self) then "clockDestroyed" else "clockReadFailed")
		return
	end
	local previousSample = self._lastSample
	self._lastSample = sample
	enqueueNotification(self, {
		kind = "clock" :: "clock",
		change = change,
		previousSample = previousSample,
		sample = sample,
	})
end

local function notifyPhase(self: ClockDriverImpl)
	if self._destroyed then
		return
	end
	local sample = readClock(self)
	if sample == nil then
		terminateDriver(self, if clockIsDestroyed(self) then "clockDestroyed" else "clockReadFailed")
		return
	end
	self._lastSample = sample
	enqueueNotification(self, {
		kind = "phase" :: "phase",
		sample = sample,
	})
end

local ClockDriver = {}
ClockDriver.__index = ClockDriver

function ClockDriver.new<PhaseInputT, DirectionTokenT>(
	clock: ProviderClock<PhaseInputT, DirectionTokenT>,
	phase: PhaseInputT,
	directions: DirectionTokens<DirectionTokenT>
): ClockDriver
	assert(directions.forward ~= directions.backward, "Pulse direction tokens must be distinct")
	local storedClock = (clock :: unknown) :: StoredProviderClock
	local storedDirections: DirectionTokens<unknown> = {
		forward = directions.forward,
		backward = directions.backward,
	}
	local self: ClockDriverImpl
	local function changedCallback(rawChange: unknown)
		notifyClockChange(self, rawChange)
	end
	local function phaseCallback(_clockDt: number, _now: number)
		notifyPhase(self)
	end
	self = (
		setmetatable({
			_providerClock = storedClock,
			_phase = phase,
			_directions = storedDirections,
			_destroyed = false,
			_drivenPlaybacks = {},
			_drivenPlaybackMembership = {},
			_active = {},
			_activeMembership = {},
			_phaseDrivenPlaybacks = {},
			_phaseMembership = {},
			_changedRelease = nil,
			_phaseRelease = nil,
			_changedCallback = changedCallback,
			_phaseCallback = phaseCallback,
			_dispatchDrivenPlaybacks = {},
			_notifications = {},
			_notifying = false,
			_lastSample = { position = 0, rate = 0 },
			_sampleScratch = { position = 0, rate = 0 },
		}, ClockDriver) :: unknown
	) :: ClockDriverImpl
	local initialSample = readClock(self)
	assert(initialSample ~= nil, "Pulse ClockDriver requires a live scheduling-capable clock")
	self._lastSample = initialSample
	return self
end

function ClockDriver.attach(
	self: ClockDriverImpl,
	playback: Playback,
	options: ClockDriverAttachmentOptions
): DrivenPlayback
	assert(not self._destroyed, "Pulse cannot attach to a destroyed ClockDriver")
	assert(playback:getStatus() == "idle", "Pulse ClockDriver requires an idle Playback")
	assert(drivenPlaybackByPlayback[playback] == nil, "Pulse Playback is already attached to a ClockDriver")
	local mode: DriverDiscontinuityMode = validateDiscontinuityMode(options.discontinuityMode)
	local drivenPlayback = DrivenPlayback.new(self, (playback :: unknown) :: PlaybackDriven, mode)
	local publicDrivenPlayback = (drivenPlayback :: unknown) :: DrivenPlayback
	drivenPlayback._endedRelease = playback:onEnded(function()
		retireDrivenPlayback(self, drivenPlayback)
	end)
	table.insert(self._drivenPlaybacks, publicDrivenPlayback)
	self._drivenPlaybackMembership[publicDrivenPlayback] = true
	drivenPlaybackByPlayback[playback] = drivenPlayback
	return publicDrivenPlayback
end

function ClockDriver.submitControl(self: ClockDriverImpl, notification: ClockDriverControlNotification)
	enqueueNotification(self, notification)
end

function ClockDriver.deconstruct(self: ClockDriverImpl)
	terminateDriver(self, "driverDestroyed")
end

function ClockDriver.isDestroyed(self: ClockDriverImpl): boolean
	if not self._destroyed and clockIsDestroyed(self) then
		terminateDriver(self, "clockDestroyed")
	end
	return self._destroyed
end

local module: ClockDriverModule = {
	new = ClockDriver.new,
}

return module
