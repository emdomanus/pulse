--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local Types = require(script.Parent.Parent.Parent.Parent.types.managers.temporalAdapter)

type ClockChange = Types.ClockChange
type ClockSample = Types.ClockSample
type DirectionTokens<DirectionTokenT> = Types.DirectionTokens<DirectionTokenT>
type PlaybackSink = Types.PlaybackSink
type ProviderClock<PhaseInputT, DirectionTokenT> = Types.ProviderClock<PhaseInputT, DirectionTokenT>
type ReachedCallback = Types.ReachedCallback
type ScheduledTaskId = Types.ScheduledTaskId
type StoredClock = Types.StoredClock
type TemporalAdapter = Types.TemporalAdapter
type TemporalAdapterImpl = Types.TemporalAdapterImpl
type TraversalDirection = DefTypes.TraversalDirection

type TemporalAdapterModule = {
	new: <PhaseInputT, DirectionTokenT>(
		clock: ProviderClock<PhaseInputT, DirectionTokenT>,
		phase: PhaseInputT,
		directions: DirectionTokens<DirectionTokenT>
	) -> TemporalAdapter,
	_snapshot: (adapter: TemporalAdapter) -> (ClockSample?, number),
	_attach: (adapter: TemporalAdapter, playback: PlaybackSink) -> boolean,
	_detach: (adapter: TemporalAdapter, playback: PlaybackSink) -> (),
	_setUpdating: (adapter: TemporalAdapter, playback: PlaybackSink, updating: boolean) -> boolean,
	_schedule: (
		adapter: TemporalAdapter,
		timePosition: number,
		direction: TraversalDirection,
		callback: ReachedCallback
	) -> ScheduledTaskId?,
	_reschedule: (adapter: TemporalAdapter, id: ScheduledTaskId, timePosition: number) -> boolean,
	_cancel: (adapter: TemporalAdapter, id: ScheduledTaskId) -> boolean,
}

local AdapterMethods = {}
AdapterMethods.__index = AdapterMethods

local MAX_NOTIFICATION_WORK = 4_096

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function assertClockSample(value: unknown): ClockSample
	assert(type(value) == "table", "Pulse clock read must return a table")
	local fields = value :: { [string]: unknown }
	local timePosition = fields.timePosition
	local rate = fields.rate
	local revision = fields.revision
	assert(type(timePosition) == "number" and isFinite(timePosition), "Pulse clock timePosition must be finite")
	assert(type(rate) == "number" and isFinite(rate), "Pulse clock rate must be finite")
	assert(
		revision == nil or (type(revision) == "number" and isFinite(revision)),
		"Pulse clock revision must be finite"
	)
	return {
		timePosition = timePosition,
		rate = rate,
		revision = revision :: number?,
	}
end

local function assertClockChange(value: unknown): ClockChange
	assert(type(value) == "table", "Pulse clock change must be a table")
	local fields = value :: { [string]: unknown }
	local kind = fields.kind
	local previous = fields.previousTimePosition
	local current = fields.currentTimePosition
	local discontinuous = fields.discontinuous
	local currentMapping = fields.current
	local revision: number? = nil
	if currentMapping ~= nil then
		assert(type(currentMapping) == "table", "Pulse clock change current mapping must be a table")
		local rawRevision = (currentMapping :: { [string]: unknown }).revision
		assert(
			rawRevision == nil or (type(rawRevision) == "number" and isFinite(rawRevision)),
			"Pulse clock change revision must be finite"
		)
		revision = rawRevision :: number?
	end
	assert(kind == nil or type(kind) == "string", "Pulse clock change kind must be a string")
	assert(
		previous == nil or (type(previous) == "number" and isFinite(previous)),
		"Pulse clock previousTimePosition must be finite"
	)
	assert(type(current) == "number" and isFinite(current), "Pulse clock currentTimePosition must be finite")
	assert(type(discontinuous) == "boolean", "Pulse clock discontinuous must be boolean")
	return {
		kind = kind :: string?,
		previousTimePosition = previous :: number?,
		currentTimePosition = current,
		discontinuous = discontinuous,
		revision = revision,
	}
end

local function asImpl(adapter: TemporalAdapter): TemporalAdapterImpl
	return (adapter :: unknown) :: TemporalAdapterImpl
end

local function findAttachment(values: { PlaybackSink }, candidate: PlaybackSink): number?
	for index, value in values do
		if value == candidate then
			return index
		end
	end
	return nil
end

local function removeAttachment(values: { PlaybackSink }, candidate: PlaybackSink): boolean
	local index = findAttachment(values, candidate)
	if index == nil then
		return false
	end
	table.remove(values, index)
	return true
end

local function releaseSafely(release: (() -> ())?)
	if release ~= nil then
		pcall(release)
	end
end

local function clockIsDestroyed(self: TemporalAdapterImpl): boolean
	local ok, destroyed = pcall(self._clock.isDestroyed, self._clock)
	return not ok or destroyed ~= false
end

local function readClock(self: TemporalAdapterImpl): ClockSample?
	if self._destroyed or clockIsDestroyed(self) then
		return nil
	end
	local readOk, rawSample = pcall(self._clock.read, self._clock)
	if not readOk then
		return nil
	end
	local parseOk, sample = pcall(assertClockSample, rawSample)
	if not parseOk then
		return nil
	end
	return sample
end

local function notifyAdapterDestroyed(self: TemporalAdapterImpl, reason: string)
	if self._destroyed then
		return
	end
	self._destroyed = true
	local attachments = table.clone(self._attachments)
	for _, playback in attachments do
		pcall(playback._onAdapterDestroyed, playback, reason)
	end
	self._attachments = {}
	self._updating = {}
	self._notifications = {}
	local changedRelease = self._changedRelease
	local phaseRelease = self._phaseRelease
	self._changedRelease = nil
	self._phaseRelease = nil
	releaseSafely(phaseRelease)
	releaseSafely(changedRelease)
end

local function dispatchNotifications(self: TemporalAdapterImpl)
	if self._notifying or self._destroyed then
		return
	end
	self._notifying = true
	local workCount = 0
	while #self._notifications > 0 and not self._destroyed do
		workCount += 1
		if workCount > MAX_NOTIFICATION_WORK then
			notifyAdapterDestroyed(self, "notificationLimitExceeded")
			break
		end
		local notification = table.remove(self._notifications, 1)
		assert(notification ~= nil, "Pulse adapter notification queue invariant failed")
		local snapshot: { PlaybackSink } =
			table.clone(if notification.kind == "clock" then self._attachments else self._updating)
		for _, playback in snapshot do
			local isAttached = if notification.kind == "clock"
				then findAttachment(self._attachments, playback) ~= nil
				else findAttachment(self._updating, playback) ~= nil
			if isAttached then
				local ok = if notification.kind == "clock"
					then pcall(
						playback._onAdapterClockChanged,
						playback,
						notification.change,
						notification.sample,
						notification.clockSerial
					)
					else pcall(playback._onAdapterPhase, playback, notification.sample, notification.clockSerial)
				if not ok then
					local reason = if notification.kind == "clock"
						then "clockNotificationFailed"
						else "phaseNotificationFailed"
					pcall(playback._onAdapterDestroyed, playback, reason)
				end
			end
		end
	end
	self._notifying = false
end

local function notifyClockChange(self: TemporalAdapterImpl, rawChange: unknown)
	if self._destroyed then
		return
	end
	local parseOk, change = pcall(assertClockChange, rawChange)
	if not parseOk then
		notifyAdapterDestroyed(self, "invalidClockChange")
		return
	end
	if clockIsDestroyed(self) or change.kind == "destroyed" then
		notifyAdapterDestroyed(self, "clockDestroyed")
		return
	end
	local revision = change.revision
	if revision ~= nil then
		local latestRevision = self._latestRevision
		if latestRevision ~= nil and revision < latestRevision then
			return
		end
		self._latestRevision = revision
	end
	local sample = readClock(self)
	if sample == nil then
		notifyAdapterDestroyed(self, "clockReadFailed")
		return
	end

	self._clockSerial += 1
	table.insert(self._notifications, {
		kind = "clock",
		change = change,
		sample = sample,
		clockSerial = self._clockSerial,
	})
	dispatchNotifications(self)
end

local function notifyPhase(self: TemporalAdapterImpl)
	if self._destroyed then
		return
	end
	local sample = readClock(self)
	if sample == nil then
		notifyAdapterDestroyed(self, "clockReadFailed")
		return
	end
	table.insert(self._notifications, {
		kind = "phase",
		sample = sample,
		clockSerial = self._clockSerial,
	})
	dispatchNotifications(self)
end

local TemporalAdapter = {}

function TemporalAdapter.new<PhaseInputT, DirectionTokenT>(
	clock: ProviderClock<PhaseInputT, DirectionTokenT>,
	phase: PhaseInputT,
	directions: DirectionTokens<DirectionTokenT>
): TemporalAdapter
	assert(directions.forward ~= directions.backward, "Pulse direction tokens must be distinct")
	local storedClock = (clock :: unknown) :: StoredClock
	local storedDirections: DirectionTokens<unknown> = {
		forward = directions.forward,
		backward = directions.backward,
	}
	local self: TemporalAdapterImpl
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
			_updating = {},
			_changedRelease = nil,
			_phaseRelease = nil,
			_changedCallback = changedCallback,
			_phaseCallback = phaseCallback,
			_notifications = {},
			_notifying = false,
			_clockSerial = 0,
			_latestRevision = nil,
		}, AdapterMethods) :: unknown
	) :: TemporalAdapterImpl
	local initialSample = readClock(self)
	assert(initialSample ~= nil, "Pulse TemporalAdapter requires a live scheduling-capable clock")
	self._latestRevision = initialSample.revision
	return self
end

function AdapterMethods.destroy(self: TemporalAdapterImpl)
	notifyAdapterDestroyed(self, "adapterDestroyed")
end

function AdapterMethods.isDestroyed(self: TemporalAdapterImpl): boolean
	if not self._destroyed and clockIsDestroyed(self) then
		notifyAdapterDestroyed(self, "clockDestroyed")
	end
	return self._destroyed
end

function TemporalAdapter._snapshot(adapter: TemporalAdapter): (ClockSample?, number)
	local self = asImpl(adapter)
	return readClock(self), self._clockSerial
end

function TemporalAdapter._attach(adapter: TemporalAdapter, playback: PlaybackSink): boolean
	local self = asImpl(adapter)
	if self._destroyed or clockIsDestroyed(self) then
		return false
	end
	if findAttachment(self._attachments, playback) ~= nil then
		return true
	end
	if #self._attachments == 0 then
		local ok, release = pcall(self._clock.bindToChanged, self._clock, self._changedCallback, false)
		if not ok then
			return false
		end
		self._changedRelease = release
	end
	table.insert(self._attachments, playback)
	return true
end

function TemporalAdapter._detach(adapter: TemporalAdapter, playback: PlaybackSink)
	local self = asImpl(adapter)
	if removeAttachment(self._updating, playback) and #self._updating == 0 then
		local release = self._phaseRelease
		self._phaseRelease = nil
		releaseSafely(release)
	end
	if removeAttachment(self._attachments, playback) and #self._attachments == 0 then
		local release = self._changedRelease
		self._changedRelease = nil
		releaseSafely(release)
	end
end

function TemporalAdapter._setUpdating(adapter: TemporalAdapter, playback: PlaybackSink, updating: boolean): boolean
	local self = asImpl(adapter)
	if updating then
		if self._destroyed or findAttachment(self._attachments, playback) == nil then
			return false
		end
		if findAttachment(self._updating, playback) ~= nil then
			return true
		end
		if #self._updating == 0 then
			local ok, release = pcall(self._clock.bindPhase, self._clock, self._phase, self._phaseCallback)
			if not ok then
				return false
			end
			self._phaseRelease = release
		end
		table.insert(self._updating, playback)
		return true
	end

	if removeAttachment(self._updating, playback) and #self._updating == 0 then
		local release = self._phaseRelease
		self._phaseRelease = nil
		releaseSafely(release)
	end
	return true
end

function TemporalAdapter._schedule(
	adapter: TemporalAdapter,
	timePosition: number,
	direction: TraversalDirection,
	callback: ReachedCallback
): ScheduledTaskId?
	local self = asImpl(adapter)
	if self._destroyed then
		return nil
	end
	local token = if direction == "forward" then self._directions.forward else self._directions.backward
	local ok, id = pcall(self._clock.bindToReached, self._clock, timePosition, token, callback, self._phase)
	if not ok or type(id) ~= "number" then
		return nil
	end
	return id
end

function TemporalAdapter._reschedule(adapter: TemporalAdapter, id: ScheduledTaskId, timePosition: number): boolean
	local self = asImpl(adapter)
	if self._destroyed then
		return false
	end
	local ok, rescheduled = pcall(self._clock.rescheduleAt, self._clock, id, timePosition, self._phase)
	return ok and rescheduled == true
end

function TemporalAdapter._cancel(adapter: TemporalAdapter, id: ScheduledTaskId): boolean
	local self = asImpl(adapter)
	local ok, cancelled = pcall(self._clock.cancel, self._clock, id)
	return ok and cancelled == true
end

local module: TemporalAdapterModule = {
	new = TemporalAdapter.new,
	_snapshot = TemporalAdapter._snapshot,
	_attach = TemporalAdapter._attach,
	_detach = TemporalAdapter._detach,
	_setUpdating = TemporalAdapter._setUpdating,
	_schedule = TemporalAdapter._schedule,
	_reschedule = TemporalAdapter._reschedule,
	_cancel = TemporalAdapter._cancel,
}

return module
