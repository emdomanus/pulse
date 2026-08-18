--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback)
local Types = require(script.Parent.Parent.Parent.Parent.types.managers.clockDriver)
local PlaybackModule = require(script.Parent.Parent.Parent.Parent.components.playback.shared.playback)

type AddressMode = DefTypes.AddressMode
type ClockDriver = Types.ClockDriver
type ClockDriverAttachmentOptions = Types.ClockDriverAttachmentOptions
type Completion = DefTypes.Completion
type DirectionTokens<DirectionTokenT> = Types.DirectionTokens<DirectionTokenT>
type DrivenPlayback = Types.DrivenPlayback
type DriverDiscontinuityMode = Types.DriverDiscontinuityMode
type EndedCallback = PlaybackTypes.EndedCallback
type LoopedCallback = PlaybackTypes.LoopedCallback
type PhaseCallback = Types.PhaseCallback
type Playback = PlaybackTypes.Playback
type PlaybackPosition = DefTypes.PlaybackPosition
type ProviderClock<PhaseInputT, DirectionTokenT> = Types.ProviderClock<PhaseInputT, DirectionTokenT>
type RawClockChangedCallback = Types.RawClockChangedCallback
type ReachedCallback = Types.ReachedCallback
type Release = DefTypes.Release
type ScheduledTaskId = Types.ScheduledTaskId
type SequenceAddress = DefTypes.SequenceAddress
type Status = DefTypes.Status
type StoredClock = Types.StoredClock
type TimeSample = DefTypes.TimeSample
type TraversalForecast = PlaybackTypes.TraversalForecast
type TraversalDirection = DefTypes.TraversalDirection

type ProviderChange = {
	kind: string?,
	previousPosition: number?,
	currentPosition: number,
	discontinuous: boolean,
}

type ControlKind = "play" | "pause" | "resume" | "speed" | "seek" | "cleanup" | "cancel" | "destroy" | "detach"

type ClockNotification = {
	kind: "clock",
	change: ProviderChange,
	previousSample: TimeSample,
	sample: TimeSample,
}

type PhaseNotification = {
	kind: "phase",
	sample: TimeSample,
}

type ReachedNotification = {
	kind: "reached",
	attachment: DrivenPlayback,
	generation: number,
	direction: unknown,
}

type ControlNotification = {
	kind: "control",
	attachment: DrivenPlayback,
	operation: ControlKind,
	speed: number?,
	address: SequenceAddress?,
	mode: AddressMode?,
	cleanup: (() -> ())?,
	reason: string?,
	result: boolean?,
}

type Notification = ClockNotification | PhaseNotification | ReachedNotification | ControlNotification

type AttachmentImpl = DrivenPlayback & {
	_driver: ClockDriver,
	_playback: Playback,
	_discontinuityMode: DriverDiscontinuityMode,
	_attached: boolean,
	_active: boolean,
	_scheduledId: ScheduledTaskId?,
	_scheduledSourcePosition: number?,
	_scheduledDirection: TraversalDirection?,
	_taskGeneration: number,
	_reachedSample: TimeSample?,
	_endedRelease: Release?,
}

type ClockDriverImpl = ClockDriver & {
	_clock: StoredClock,
	_phase: unknown,
	_directions: DirectionTokens<unknown>,
	_destroyed: boolean,
	_attachments: { DrivenPlayback },
	_attachmentMembership: { [DrivenPlayback]: true },
	_active: { DrivenPlayback },
	_activeMembership: { [DrivenPlayback]: true },
	_phaseAttachments: { DrivenPlayback },
	_phaseMembership: { [DrivenPlayback]: true },
	_changedRelease: Release?,
	_phaseRelease: Release?,
	_changedCallback: RawClockChangedCallback,
	_phaseCallback: PhaseCallback,
	_notifications: { Notification },
	_notifying: boolean,
	_lastSample: TimeSample,
}

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

local DriverMethods = {}
DriverMethods.__index = DriverMethods

local DrivenMethods = {}
DrivenMethods.__index = DrivenMethods

local attachmentByPlayback = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [Playback]: AttachmentImpl }

local dispatchNotifications: (self: ClockDriverImpl) -> ()
local refreshAttachment: (
	self: ClockDriverImpl,
	attachment: AttachmentImpl,
	currentSample: TimeSample?,
	reachedTaskFired: boolean?
) -> ()

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function sameSourceCoordinate(first: number, second: number): boolean
	local magnitude = math.max(1, math.abs(first), math.abs(second))
	return math.abs(first - second) <= DEADLINE_TOLERANCE * magnitude
end

local function asDriver(driver: ClockDriver): ClockDriverImpl
	return (driver :: unknown) :: ClockDriverImpl
end

local function asAttachment(attachment: DrivenPlayback): AttachmentImpl
	return (attachment :: unknown) :: AttachmentImpl
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

local function assertProviderChange(value: unknown): ProviderChange
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

local function validateAddressMode(mode: AddressMode): AddressMode
	assert(mode == "skip" or mode == "reconstruct", "Pulse address mode must be 'reconstruct' or 'skip'")
	return mode
end

local function releaseSafely(release: Release?)
	if release ~= nil then
		pcall(release)
	end
end

local function clockIsDestroyed(self: ClockDriverImpl): boolean
	local ok, destroyed = pcall(self._clock.isDestroyed, self._clock)
	return not ok or destroyed ~= false
end

local function readClock(self: ClockDriverImpl): TimeSample?
	if self._destroyed or clockIsDestroyed(self) then
		return nil
	end
	local readOk, rawSample = pcall(self._clock.read, self._clock)
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

local function cancelScheduled(self: ClockDriverImpl, attachment: AttachmentImpl)
	local id = attachment._scheduledId
	attachment._scheduledId = nil
	attachment._scheduledSourcePosition = nil
	attachment._scheduledDirection = nil
	attachment._taskGeneration += 1
	if id ~= nil then
		pcall(self._clock.cancel, self._clock, id)
	end
end

local function setPhaseRequired(self: ClockDriverImpl, attachment: AttachmentImpl, required: boolean): boolean
	local publicAttachment = (attachment :: unknown) :: DrivenPlayback
	if required then
		if self._destroyed or not attachment._active then
			return false
		end
		if self._phaseMembership[publicAttachment] ~= nil then
			return true
		end
		if #self._phaseAttachments == 0 then
			local ok, release = pcall(self._clock.bindPhase, self._clock, self._phase, self._phaseCallback)
			if not ok or type(release) ~= "function" then
				return false
			end
			self._phaseRelease = release
		end
		table.insert(self._phaseAttachments, publicAttachment)
		self._phaseMembership[publicAttachment] = true
		return true
	end

	if removeMember(self._phaseAttachments, self._phaseMembership, publicAttachment) then
		if #self._phaseAttachments == 0 then
			local release = self._phaseRelease
			self._phaseRelease = nil
			releaseSafely(release)
		end
	end
	return true
end

local function deactivateAttachment(self: ClockDriverImpl, attachment: AttachmentImpl)
	if not attachment._active then
		return
	end
	cancelScheduled(self, attachment)
	setPhaseRequired(self, attachment, false)
	attachment._active = false
	local publicAttachment = (attachment :: unknown) :: DrivenPlayback
	if removeMember(self._active, self._activeMembership, publicAttachment) and #self._active == 0 then
		local release = self._changedRelease
		self._changedRelease = nil
		releaseSafely(release)
	end
end

local function retireAttachment(self: ClockDriverImpl, attachment: AttachmentImpl)
	if not attachment._attached then
		return
	end
	deactivateAttachment(self, attachment)
	attachment._attached = false
	if attachmentByPlayback[attachment._playback] == attachment then
		attachmentByPlayback[attachment._playback] = nil
	end
	local publicAttachment = (attachment :: unknown) :: DrivenPlayback
	removeMember(self._attachments, self._attachmentMembership, publicAttachment)
	local endedRelease = attachment._endedRelease
	attachment._endedRelease = nil
	releaseSafely(endedRelease)
end

local function activateAttachment(self: ClockDriverImpl, attachment: AttachmentImpl): boolean
	if attachment._active then
		return true
	end
	if self._destroyed or clockIsDestroyed(self) then
		return false
	end
	if #self._active == 0 then
		local ok, release = pcall(self._clock.bindToChanged, self._clock, self._changedCallback, false)
		if not ok or type(release) ~= "function" then
			return false
		end
		self._changedRelease = release
	end
	local publicAttachment = (attachment :: unknown) :: DrivenPlayback
	table.insert(self._active, publicAttachment)
	self._activeMembership[publicAttachment] = true
	attachment._active = true
	return true
end

local function terminateDriver(self: ClockDriverImpl, reason: string)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._notifications = {}
	local attachments = table.clone(self._attachments)
	for _, publicAttachment in attachments do
		local attachment = asAttachment(publicAttachment)
		cancelScheduled(self, attachment)
		attachment._active = false
		attachment._attached = false
		attachment._endedRelease = nil
		if attachmentByPlayback[attachment._playback] == attachment then
			attachmentByPlayback[attachment._playback] = nil
		end
	end
	table.clear(self._attachments)
	table.clear(self._attachmentMembership)
	table.clear(self._active)
	table.clear(self._activeMembership)
	table.clear(self._phaseAttachments)
	table.clear(self._phaseMembership)
	local changedRelease = self._changedRelease
	local phaseRelease = self._phaseRelease
	self._changedRelease = nil
	self._phaseRelease = nil
	releaseSafely(phaseRelease)
	releaseSafely(changedRelease)
	for _, publicAttachment in attachments do
		PlaybackModule._fail(asAttachment(publicAttachment)._playback, reason)
	end
end

local function enqueueNotification(self: ClockDriverImpl, notification: Notification)
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

local function evaluateCurrent(self: ClockDriverImpl, attachment: AttachmentImpl): TimeSample?
	local sample = readForEvaluation(self)
	if sample == nil then
		return nil
	end
	return if attachment._playback:evaluate(sample) then sample else nil
end

local function scheduleNext(
	self: ClockDriverImpl,
	attachment: AttachmentImpl,
	initialState: TraversalForecast,
	initialSample: TimeSample?,
	reachedTaskFired: boolean
)
	local attempts = 0
	local state: TraversalForecast? = initialState
	local current: TimeSample? = initialSample
	local taskFired = reachedTaskFired
	while attachment._attached and attachment._active and attachment._playback:getStatus() == "playing" do
		attempts += 1
		if attempts > MAX_DRIVER_WORK then
			PlaybackModule._fail(attachment._playback, "driverWorkLimitExceeded")
			return
		end
		local forecast = state or PlaybackModule._getTraversalForecast(attachment._playback)
		state = nil
		if not attachment._attached or attachment._playback:getStatus() ~= "playing" then
			return
		end
		local runAt = forecast.sourceBoundary
		local direction = forecast.sourceDirection
		if runAt == nil or direction == nil then
			cancelScheduled(self, attachment)
			return
		end
		local id = attachment._scheduledId
		local scheduledSourcePosition = attachment._scheduledSourcePosition
		local equivalent = false
		local effectiveRunAt = runAt
		if
			id ~= nil
			and attachment._scheduledDirection == direction
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
			cancelScheduled(self, attachment)
			attachment._playback:evaluate(current)
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
		if id ~= nil and attachment._scheduledDirection == direction then
			local ok, rescheduled = pcall(self._clock.rescheduleAt, self._clock, id, effectiveRunAt, self._phase)
			reused = ok and rescheduled == true
			if reused then
				attachment._scheduledSourcePosition = effectiveRunAt
			end
		end
		if not reused then
			cancelScheduled(self, attachment)
			attachment._taskGeneration += 1
			local generation = attachment._taskGeneration
			local publicAttachment = (attachment :: unknown) :: DrivenPlayback
			local function reachedCallback(_now: number, actualDirection: unknown)
				enqueueNotification(self, {
					kind = "reached" :: "reached",
					attachment = publicAttachment,
					generation = generation,
					direction = actualDirection,
				})
			end
			local callback: ReachedCallback = reachedCallback
			local token = if direction == "forward" then self._directions.forward else self._directions.backward
			local ok, scheduled =
				pcall(self._clock.bindToReached, self._clock, effectiveRunAt, token, callback, self._phase)
			if not ok or type(scheduled) ~= "number" then
				PlaybackModule._fail(attachment._playback, "scheduleFailed")
				return
			end
			attachment._scheduledId = scheduled
			attachment._scheduledSourcePosition = effectiveRunAt
			attachment._scheduledDirection = direction :: TraversalDirection
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
		cancelScheduled(self, attachment)
		attachment._playback:evaluate(validation)
		if hasPendingClockNotification(self) then
			return
		end
		current = validation
		taskFired = false
	end
end

refreshAttachment = function(
	self: ClockDriverImpl,
	attachment: AttachmentImpl,
	currentSample: TimeSample?,
	reachedTaskFired: boolean?
)
	if not attachment._attached then
		return
	end
	if hasPendingClockNotification(self) then
		return
	end
	local status = attachment._playback:getStatus()
	if status ~= "playing" then
		cancelScheduled(self, attachment)
		setPhaseRequired(self, attachment, false)
		if not attachment._playback:isAlive() then
			retireAttachment(self, attachment)
		end
		return
	end
	if not attachment._active and not activateAttachment(self, attachment) then
		if clockIsDestroyed(self) then
			terminateDriver(self, "clockDestroyed")
		else
			PlaybackModule._fail(attachment._playback, "driverAttachFailed")
		end
		return
	end
	local state = PlaybackModule._getTraversalForecast(attachment._playback)
	if not setPhaseRequired(self, attachment, state.phaseRequired) then
		PlaybackModule._fail(attachment._playback, "phaseBindFailed")
		return
	end
	scheduleNext(self, attachment, state, currentSample, reachedTaskFired == true)
end

local function applyClockChangeToAttachment(
	self: ClockDriverImpl,
	attachment: AttachmentImpl,
	change: ProviderChange,
	previousSample: TimeSample,
	sample: TimeSample
)
	if not attachment._attached or not attachment._active or attachment._playback:getStatus() ~= "playing" then
		return
	end
	local previousPosition = change.previousPosition or previousSample.position
	if change.discontinuous then
		attachment._playback:evaluate({
			position = previousPosition,
			rate = previousSample.rate,
		})
		if attachment._playback:getStatus() ~= "playing" then
			refreshAttachment(self, attachment, sample)
			return
		end
		local target = PlaybackModule._projectSourcePosition(attachment._playback, change.currentPosition)
		if target == nil then
			refreshAttachment(self, attachment, sample)
			return
		end
		if attachment._discontinuityMode == "cancel" then
			attachment._playback:cancel("clockDiscontinuity")
		else
			PlaybackModule._acceptSourceSample(attachment._playback, {
				position = change.currentPosition,
				rate = sample.rate,
			})
			attachment._playback:seek({
				timePosition = target.timePosition,
				loopIndex = target.loopIndex,
			}, attachment._discontinuityMode)
			if attachment._playback:getStatus() == "playing" and sample.position ~= change.currentPosition then
				attachment._playback:evaluate(sample)
			end
		end
	else
		attachment._playback:evaluate({
			position = previousPosition,
			rate = sample.rate,
		})
		if attachment._playback:getStatus() == "playing" and change.currentPosition ~= previousPosition then
			attachment._playback:evaluate({
				position = change.currentPosition,
				rate = sample.rate,
			})
		end
		if attachment._playback:getStatus() == "playing" and sample.position ~= change.currentPosition then
			attachment._playback:evaluate(sample)
		end
	end
	refreshAttachment(self, attachment, sample)
end

local function applyClockNotification(self: ClockDriverImpl, notification: ClockNotification)
	local snapshot = table.clone(self._active)
	for _, publicAttachment in snapshot do
		if self._activeMembership[publicAttachment] ~= nil then
			applyClockChangeToAttachment(
				self,
				asAttachment(publicAttachment),
				notification.change,
				notification.previousSample,
				notification.sample
			)
		end
	end
end

local function applyPhaseNotification(self: ClockDriverImpl, notification: PhaseNotification)
	local snapshot = table.clone(self._phaseAttachments)
	for _, publicAttachment in snapshot do
		if self._phaseMembership[publicAttachment] ~= nil then
			local attachment = asAttachment(publicAttachment)
			local reachedSample = attachment._reachedSample
			attachment._reachedSample = nil
			if
				reachedSample == nil
				or reachedSample.position ~= notification.sample.position
				or reachedSample.rate ~= notification.sample.rate
			then
				attachment._playback:evaluate(notification.sample)
			end
			refreshAttachment(self, attachment, notification.sample)
		end
	end
end

local function applyReachedNotification(self: ClockDriverImpl, notification: ReachedNotification)
	local attachment = asAttachment(notification.attachment)
	if
		not attachment._attached
		or not attachment._active
		or attachment._taskGeneration ~= notification.generation
		or attachment._scheduledId == nil
	then
		return
	end
	local scheduledDirection = attachment._scheduledDirection
	local expectedToken = if scheduledDirection == "forward"
		then self._directions.forward
		elseif scheduledDirection == "backward" then self._directions.backward
		else nil
	if expectedToken == nil or notification.direction ~= expectedToken then
		PlaybackModule._fail(attachment._playback, "invalidReachedDirection")
		return
	end
	local sample = readForEvaluation(self)
	if sample == nil then
		return
	end
	attachment._playback:evaluate(sample)
	attachment._reachedSample = sample
	refreshAttachment(self, attachment, sample, true)
end

local function applyControlNotification(self: ClockDriverImpl, notification: ControlNotification)
	local attachment = asAttachment(notification.attachment)
	if not attachment._attached then
		notification.result = false
		return
	end
	local playback = attachment._playback
	if notification.operation == "play" then
		if playback:getStatus() ~= "idle" then
			return
		end
		if not activateAttachment(self, attachment) then
			if clockIsDestroyed(self) then
				terminateDriver(self, "clockDestroyed")
			else
				PlaybackModule._fail(playback, "driverAttachFailed")
			end
			return
		end
		local sample = readForEvaluation(self)
		if sample ~= nil then
			playback:play(sample)
			refreshAttachment(self, attachment, sample)
		end
	elseif notification.operation == "pause" then
		if playback:getStatus() == "playing" then
			evaluateCurrent(self, attachment)
			playback:pause()
			refreshAttachment(self, attachment)
		end
	elseif notification.operation == "resume" then
		if playback:getStatus() == "paused" then
			local sample = readForEvaluation(self)
			if sample ~= nil then
				playback:resume()
				playback:evaluate(sample)
				refreshAttachment(self, attachment, sample)
			end
		end
	elseif notification.operation == "speed" then
		local currentSample: TimeSample? = nil
		if playback:getStatus() == "playing" then
			currentSample = evaluateCurrent(self, attachment)
		end
		local speed = notification.speed
		if speed ~= nil then
			playback:setPlaybackSpeed(speed)
			refreshAttachment(self, attachment, currentSample)
		end
	elseif notification.operation == "seek" then
		local currentSample: TimeSample? = nil
		if playback:getStatus() == "playing" then
			currentSample = evaluateCurrent(self, attachment)
		end
		local address = notification.address
		local mode = notification.mode
		if address ~= nil and mode ~= nil then
			notification.result = playback:seek(address, mode :: AddressMode)
			refreshAttachment(self, attachment, currentSample)
		end
	elseif notification.operation == "cleanup" then
		if playback:getStatus() == "playing" then
			evaluateCurrent(self, attachment)
		end
		local cleanup = notification.cleanup
		if cleanup ~= nil then
			playback:addCleanup(cleanup)
		end
	elseif notification.operation == "cancel" then
		if playback:getStatus() == "playing" then
			evaluateCurrent(self, attachment)
		end
		if playback:isAlive() then
			playback:cancel(notification.reason)
		end
	elseif notification.operation == "destroy" then
		if playback:getStatus() == "playing" then
			evaluateCurrent(self, attachment)
		end
		if playback:isAlive() then
			playback:destroy()
		end
	elseif notification.operation == "detach" then
		if playback:getStatus() == "playing" then
			evaluateCurrent(self, attachment)
		end
		retireAttachment(self, attachment)
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

function ClockDriver.new<PhaseInputT, DirectionTokenT>(
	clock: ProviderClock<PhaseInputT, DirectionTokenT>,
	phase: PhaseInputT,
	directions: DirectionTokens<DirectionTokenT>
): ClockDriver
	assert(directions.forward ~= directions.backward, "Pulse direction tokens must be distinct")
	local storedClock = (clock :: unknown) :: StoredClock
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
			_clock = storedClock,
			_phase = phase,
			_directions = storedDirections,
			_destroyed = false,
			_attachments = {},
			_attachmentMembership = {},
			_active = {},
			_activeMembership = {},
			_phaseAttachments = {},
			_phaseMembership = {},
			_changedRelease = nil,
			_phaseRelease = nil,
			_changedCallback = changedCallback,
			_phaseCallback = phaseCallback,
			_notifications = {},
			_notifying = false,
			_lastSample = { position = 0, rate = 0 },
		}, DriverMethods) :: unknown
	) :: ClockDriverImpl
	local initialSample = readClock(self)
	assert(initialSample ~= nil, "Pulse ClockDriver requires a live scheduling-capable clock")
	self._lastSample = initialSample
	return self
end

function DriverMethods.attach(
	self: ClockDriverImpl,
	playback: Playback,
	options: ClockDriverAttachmentOptions
): DrivenPlayback
	assert(not self._destroyed, "Pulse cannot attach to a destroyed ClockDriver")
	assert(playback:getStatus() == "idle", "Pulse ClockDriver requires an idle Playback")
	assert(attachmentByPlayback[playback] == nil, "Pulse Playback is already attached to a ClockDriver")
	local mode = validateDiscontinuityMode(options.discontinuityMode)
	local attachment: AttachmentImpl
	attachment = (
		setmetatable({
			_driver = self,
			_playback = playback,
			_discontinuityMode = mode,
			_attached = true,
			_active = false,
			_scheduledId = nil,
			_scheduledSourcePosition = nil,
			_scheduledDirection = nil,
			_taskGeneration = 0,
			_reachedSample = nil,
			_endedRelease = nil,
		}, DrivenMethods) :: unknown
	) :: AttachmentImpl
	local publicAttachment = (attachment :: unknown) :: DrivenPlayback
	attachment._endedRelease = playback:onEnded(function()
		retireAttachment(self, attachment)
	end)
	table.insert(self._attachments, publicAttachment)
	self._attachmentMembership[publicAttachment] = true
	attachmentByPlayback[playback] = attachment
	return publicAttachment
end

function DriverMethods.destroy(self: ClockDriverImpl)
	terminateDriver(self, "driverDestroyed")
end

function DriverMethods.isDestroyed(self: ClockDriverImpl): boolean
	if not self._destroyed and clockIsDestroyed(self) then
		terminateDriver(self, "clockDestroyed")
	end
	return self._destroyed
end

local function control(self: AttachmentImpl, operation: ControlKind): ControlNotification
	local notification: ControlNotification = {
		kind = "control" :: "control",
		attachment = (self :: unknown) :: DrivenPlayback,
		operation = operation,
		result = nil,
	}
	enqueueNotification(asDriver(self._driver), notification)
	return notification
end

function DrivenMethods.play(self: AttachmentImpl): DrivenPlayback
	control(self, "play" :: ControlKind)
	return self
end

function DrivenMethods.pause(self: AttachmentImpl)
	control(self, "pause" :: ControlKind)
end

function DrivenMethods.resume(self: AttachmentImpl)
	control(self, "resume" :: ControlKind)
end

function DrivenMethods.setPlaybackSpeed(self: AttachmentImpl, speed: number)
	assert(isFinite(speed), "Pulse playbackSpeed must be finite")
	local notification: ControlNotification = {
		kind = "control" :: "control",
		attachment = (self :: unknown) :: DrivenPlayback,
		operation = "speed" :: ControlKind,
		speed = speed,
	}
	enqueueNotification(asDriver(self._driver), notification)
end

function DrivenMethods.getPlaybackSpeed(self: AttachmentImpl): number
	return self._playback:getPlaybackSpeed()
end

function DrivenMethods.seek(self: AttachmentImpl, address: SequenceAddress, mode: AddressMode): boolean
	local validatedAddress = PlaybackModule._validateAddress(self._playback, address)
	local validatedMode: AddressMode = validateAddressMode(mode)
	local notification: ControlNotification = {
		kind = "control" :: "control",
		attachment = (self :: unknown) :: DrivenPlayback,
		operation = "seek" :: ControlKind,
		address = {
			timePosition = validatedAddress.timePosition,
			loopIndex = validatedAddress.loopIndex,
		},
		mode = validatedMode,
		result = self._attached and self._playback:isAlive(),
	}
	enqueueNotification(asDriver(self._driver), notification)
	return notification.result == true
end

function DrivenMethods.getPosition(self: AttachmentImpl): PlaybackPosition
	return self._playback:getPosition()
end

function DrivenMethods.getStatus(self: AttachmentImpl): Status
	return self._playback:getStatus()
end

function DrivenMethods.addCleanup(self: AttachmentImpl, cleanup: () -> ())
	assert(type(cleanup) == "function", "Pulse cleanup must be a callback")
	enqueueNotification(asDriver(self._driver), {
		kind = "control" :: "control",
		attachment = (self :: unknown) :: DrivenPlayback,
		operation = "cleanup" :: ControlKind,
		cleanup = cleanup,
	})
end

function DrivenMethods.cancel(self: AttachmentImpl, reason: string?)
	local notification: ControlNotification = {
		kind = "control" :: "control",
		attachment = (self :: unknown) :: DrivenPlayback,
		operation = "cancel" :: ControlKind,
		reason = reason,
	}
	enqueueNotification(asDriver(self._driver), notification)
end

function DrivenMethods.destroy(self: AttachmentImpl)
	control(self, "destroy" :: ControlKind)
end

function DrivenMethods.onEnded(self: AttachmentImpl, callback: EndedCallback): Release
	return self._playback:onEnded(callback)
end

function DrivenMethods.onLooped(self: AttachmentImpl, callback: LoopedCallback): Release
	return self._playback:onLooped(callback)
end

function DrivenMethods.isAlive(self: AttachmentImpl): boolean
	return self._playback:isAlive()
end

function DrivenMethods.getCompletion(self: AttachmentImpl): Completion?
	return self._playback:getCompletion()
end

function DrivenMethods.detach(self: AttachmentImpl): Playback
	control(self, "detach" :: ControlKind)
	return self._playback
end

local module: ClockDriverModule = {
	new = ClockDriver.new,
}

return module
