--!strict

export type Release = () -> ()
export type DirectionName = "forward" | "backward"
export type DirectionToken = {
	name: DirectionName,
}
export type ClockSample = {
	timePosition: number,
	rate: number,
	revision: number,
}
export type ClockChange = {
	kind: string,
	current: {
		revision: number,
	},
	previousTimePosition: number?,
	currentTimePosition: number,
	discontinuous: boolean,
}
export type RawChangedCallback = (change: unknown) -> ()
export type ReachedCallback = (now: number, direction: unknown) -> ()
export type PhaseCallback = (dt: number, now: number) -> ()

type ChangedBinding = {
	callback: RawChangedCallback,
	active: boolean,
}

type PhaseBinding<PhaseT> = {
	phase: PhaseT,
	callback: PhaseCallback,
	active: boolean,
}

type PhaseState<PhaseT> = {
	phase: PhaseT,
	lastPosition: number,
}

type ReachedRecord<PhaseT> = {
	id: number,
	timePosition: number,
	previousTimePosition: number,
	direction: DirectionToken,
	callback: ReachedCallback,
	phase: PhaseT,
	active: boolean,
	running: boolean,
	rescheduled: boolean,
}

export type FakeClockOptions = {
	rootTime: number?,
	timePosition: number?,
	rate: number?,
}

export type FakeClock<PhaseT> = {
	directions: {
		forward: DirectionToken,
		backward: DirectionToken,
	},
	read: (self: FakeClock<PhaseT>) -> ClockSample,
	bindToChanged: (self: FakeClock<PhaseT>, callback: RawChangedCallback, runInitially: boolean?) -> Release,
	isDestroyed: (self: FakeClock<PhaseT>) -> boolean,
	bindToReached: (
		self: FakeClock<PhaseT>,
		timePosition: number,
		direction: DirectionToken,
		callback: ReachedCallback,
		phase: PhaseT
	) -> number,
	cancel: (self: FakeClock<PhaseT>, id: number) -> boolean,
	rescheduleAt: (self: FakeClock<PhaseT>, id: number, runAt: number, phase: PhaseT) -> boolean,
	bindPhase: (self: FakeClock<PhaseT>, phase: PhaseT, callback: PhaseCallback) -> Release,
	advanceRootTo: (self: FakeClock<PhaseT>, rootTime: number) -> (),
	stepRootTo: (self: FakeClock<PhaseT>, rootTime: number, phase: PhaseT) -> (),
	evaluatePhase: (self: FakeClock<PhaseT>, phase: PhaseT) -> (),
	setRate: (self: FakeClock<PhaseT>, rate: number) -> (),
	jumpTo: (self: FakeClock<PhaseT>, timePosition: number) -> (),
	destroy: (self: FakeClock<PhaseT>) -> (),
	setBeforeNextReached: (self: FakeClock<PhaseT>, callback: (() -> ())?) -> (),
	getTaskCount: (self: FakeClock<PhaseT>) -> number,
	getChangedBindingCount: (self: FakeClock<PhaseT>) -> number,
	getPhaseBindingCount: (self: FakeClock<PhaseT>) -> number,
	getScheduleCount: (self: FakeClock<PhaseT>) -> number,
	getRescheduleCount: (self: FakeClock<PhaseT>) -> number,
	getCancelCount: (self: FakeClock<PhaseT>) -> number,
	getLastTaskId: (self: FakeClock<PhaseT>) -> number?,
	_rootTime: number,
	_rootAtAnchor: number,
	_timeAtAnchor: number,
	_rate: number,
	_revision: number,
	_destroyed: boolean,
	_nextId: number,
	_tasks: { [number]: ReachedRecord<PhaseT> },
	_changedBindings: { ChangedBinding },
	_phaseBindings: { PhaseBinding<PhaseT> },
	_phaseStates: { PhaseState<PhaseT> },
	_scheduleCount: number,
	_rescheduleCount: number,
	_cancelCount: number,
	_lastTaskId: number?,
	_beforeNextReached: (() -> ())?,
}

local FORWARD: DirectionToken = table.freeze({ name = "forward" })
local BACKWARD: DirectionToken = table.freeze({ name = "backward" })

local FakeClock = {}
FakeClock.__index = FakeClock

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function position<PhaseT>(self: FakeClock<PhaseT>): number
	return self._timeAtAnchor + (self._rootTime - self._rootAtAnchor) * self._rate
end

local function getPhaseState<PhaseT>(self: FakeClock<PhaseT>, phase: PhaseT): PhaseState<PhaseT>
	for _, state in self._phaseStates do
		if state.phase == phase then
			return state
		end
	end
	local state: PhaseState<PhaseT> = {
		phase = phase,
		lastPosition = position(self),
	}
	table.insert(self._phaseStates, state)
	return state
end

local function notifyChanged<PhaseT>(self: FakeClock<PhaseT>, change: ClockChange)
	local snapshot = table.clone(self._changedBindings)
	for _, binding in snapshot do
		if binding.active then
			binding.callback(change)
		end
	end
end

function FakeClock.new<PhaseT>(options: FakeClockOptions?): FakeClock<PhaseT>
	local config: FakeClockOptions = options or {}
	local rootTime = config.rootTime or 0
	local timePosition = config.timePosition or 0
	local rate = config.rate or 1
	assert(isFinite(rootTime) and isFinite(timePosition) and isFinite(rate), "fake clock values must be finite")
	return (
		setmetatable({
			directions = table.freeze({
				forward = FORWARD,
				backward = BACKWARD,
			}),
			_rootTime = rootTime,
			_rootAtAnchor = rootTime,
			_timeAtAnchor = timePosition,
			_rate = rate,
			_revision = 0,
			_destroyed = false,
			_nextId = 0,
			_tasks = {},
			_changedBindings = {},
			_phaseBindings = {},
			_phaseStates = {},
			_scheduleCount = 0,
			_rescheduleCount = 0,
			_cancelCount = 0,
			_lastTaskId = nil,
			_beforeNextReached = nil,
		}, FakeClock) :: unknown
	) :: FakeClock<PhaseT>
end

function FakeClock.read<PhaseT>(self: FakeClock<PhaseT>): ClockSample
	assert(not self._destroyed, "cannot read a destroyed fake clock")
	return {
		timePosition = position(self),
		rate = self._rate,
		revision = self._revision,
	}
end

function FakeClock.bindToChanged<PhaseT>(self: FakeClock<PhaseT>, callback: RawChangedCallback, runInitially: boolean?): Release
	assert(not self._destroyed, "cannot bind a destroyed fake clock")
	local binding: ChangedBinding = {
		callback = callback,
		active = true,
	}
	table.insert(self._changedBindings, binding)
	if runInitially then
		callback({
			kind = "initial",
			current = { revision = self._revision },
			previousTimePosition = nil,
			currentTimePosition = position(self),
			discontinuous = false,
		})
	end
	return function()
		binding.active = false
	end
end

function FakeClock.isDestroyed<PhaseT>(self: FakeClock<PhaseT>): boolean
	return self._destroyed
end

function FakeClock.bindToReached<PhaseT>(
	self: FakeClock<PhaseT>,
	timePosition: number,
	direction: DirectionToken,
	callback: ReachedCallback,
	phase: PhaseT
): number
	assert(not self._destroyed and isFinite(timePosition), "invalid fake reached task")
	assert(direction == FORWARD or direction == BACKWARD, "fake direction token identity is invalid")
	getPhaseState(self, phase)
	self._nextId += 1
	local id = self._nextId
	self._tasks[id] = {
		id = id,
		timePosition = timePosition,
		previousTimePosition = position(self),
		direction = direction,
		callback = callback,
		phase = phase,
		active = true,
		running = false,
		rescheduled = false,
	}
	self._scheduleCount += 1
	self._lastTaskId = id
	return id
end

function FakeClock.cancel<PhaseT>(self: FakeClock<PhaseT>, id: number): boolean
	local record = self._tasks[id]
	if record == nil or not record.active then
		return false
	end
	record.active = false
	self._cancelCount += 1
	if not record.running then
		self._tasks[id] = nil
	end
	return true
end

function FakeClock.rescheduleAt<PhaseT>(self: FakeClock<PhaseT>, id: number, runAt: number, phase: PhaseT): boolean
	local record = self._tasks[id]
	if record == nil or not record.active or self._destroyed then
		return false
	end
	assert(isFinite(runAt), "fake reschedule position must be finite")
	getPhaseState(self, phase)
	record.timePosition = runAt
	record.phase = phase
	record.previousTimePosition = position(self)
	record.rescheduled = record.running
	self._rescheduleCount += 1
	return true
end

function FakeClock.bindPhase<PhaseT>(self: FakeClock<PhaseT>, phase: PhaseT, callback: PhaseCallback): Release
	assert(not self._destroyed, "cannot bind phase on destroyed fake clock")
	getPhaseState(self, phase)
	local binding: PhaseBinding<PhaseT> = {
		phase = phase,
		callback = callback,
		active = true,
	}
	table.insert(self._phaseBindings, binding)
	return function()
		binding.active = false
	end
end

local function crossed(current: number, record: ReachedRecord<unknown>): boolean
	local previous = record.previousTimePosition
	if record.direction == FORWARD then
		return previous < record.timePosition and current >= record.timePosition
	end
	return previous > record.timePosition and current <= record.timePosition
end

local function nextDue<PhaseT>(
	self: FakeClock<PhaseT>,
	phase: PhaseT,
	current: number,
	drained: { [number]: true }
): ReachedRecord<PhaseT>?
	local selected: ReachedRecord<PhaseT>? = nil
	for _, record in self._tasks do
		if record.active and drained[record.id] == nil and record.phase == phase and crossed(current, record) then
			local choose = selected == nil
			if selected ~= nil then
				choose = if record.direction == FORWARD
					then record.timePosition < selected.timePosition
					else record.timePosition > selected.timePosition
			end
			if choose then
				selected = record
			end
		end
	end
	return selected
end

function FakeClock.evaluatePhase<PhaseT>(self: FakeClock<PhaseT>, phase: PhaseT)
	assert(not self._destroyed, "cannot step destroyed fake clock")
	local state = getPhaseState(self, phase)
	local previous = state.lastPosition
	local sampledNow = position(self)
	state.lastPosition = sampledNow
	local drainCount = 0
	local drained: { [number]: true } = {}
	while true do
		local record = nextDue(self, phase, sampledNow, drained)
		if record == nil then
			break
		end
		drainCount += 1
		assert(drainCount <= 1_000, `fake clock reached drain did not converge at {record.timePosition}`)
		drained[record.id] = true
		local before = self._beforeNextReached
		self._beforeNextReached = nil
		if before ~= nil then
			before()
		end
		record.running = true
		record.rescheduled = false
		record.callback(sampledNow, record.direction)
		record.running = false
		if not record.active or not record.rescheduled then
			record.active = false
			self._tasks[record.id] = nil
		end
	end
	for _, record in self._tasks do
		if record.active and record.phase == phase then
			if record.rescheduled then
				record.rescheduled = false
			else
				record.previousTimePosition = sampledNow
			end
		end
	end
	local phaseBindings = table.clone(self._phaseBindings)
	local actualNow = position(self)
	for _, binding in phaseBindings do
		if binding.active and binding.phase == phase then
			binding.callback(actualNow - previous, actualNow)
		end
	end
end

function FakeClock.advanceRootTo<PhaseT>(self: FakeClock<PhaseT>, rootTime: number)
	assert(isFinite(rootTime) and rootTime >= self._rootTime, "fake root time must advance")
	self._rootTime = rootTime
end

function FakeClock.stepRootTo<PhaseT>(self: FakeClock<PhaseT>, rootTime: number, phase: PhaseT)
	self:advanceRootTo(rootTime)
	self:evaluatePhase(phase)
end

function FakeClock.setRate<PhaseT>(self: FakeClock<PhaseT>, rate: number)
	assert(not self._destroyed and isFinite(rate), "fake rate must be finite")
	local current = position(self)
	self._rootAtAnchor = self._rootTime
	self._timeAtAnchor = current
	self._rate = rate
	self._revision += 1
	notifyChanged(self, {
		kind = "rate",
		current = { revision = self._revision },
		previousTimePosition = current,
		currentTimePosition = current,
		discontinuous = false,
	})
end

function FakeClock.jumpTo<PhaseT>(self: FakeClock<PhaseT>, timePosition: number)
	assert(not self._destroyed and isFinite(timePosition), "fake jump position must be finite")
	local previous = position(self)
	self._rootAtAnchor = self._rootTime
	self._timeAtAnchor = timePosition
	self._revision += 1
	for _, state in self._phaseStates do
		state.lastPosition = timePosition
	end
	notifyChanged(self, {
		kind = "mapping",
		current = { revision = self._revision },
		previousTimePosition = previous,
		currentTimePosition = timePosition,
		discontinuous = true,
	})
end

function FakeClock.destroy<PhaseT>(self: FakeClock<PhaseT>)
	if self._destroyed then
		return
	end
	local current = position(self)
	self._destroyed = true
	for _, record in self._tasks do
		record.active = false
	end
	notifyChanged(self, {
		kind = "destroyed",
		current = { revision = self._revision },
		previousTimePosition = current,
		currentTimePosition = current,
		discontinuous = true,
	})
	self._tasks = {}
	for _, binding in self._phaseBindings do
		binding.active = false
	end
	for _, binding in self._changedBindings do
		binding.active = false
	end
end

function FakeClock.setBeforeNextReached<PhaseT>(self: FakeClock<PhaseT>, callback: (() -> ())?)
	self._beforeNextReached = callback
end

function FakeClock.getTaskCount<PhaseT>(self: FakeClock<PhaseT>): number
	local count = 0
	for _, record in self._tasks do
		if record.active then
			count += 1
		end
	end
	return count
end

function FakeClock.getChangedBindingCount<PhaseT>(self: FakeClock<PhaseT>): number
	local count = 0
	for _, binding in self._changedBindings do
		if binding.active then
			count += 1
		end
	end
	return count
end

function FakeClock.getPhaseBindingCount<PhaseT>(self: FakeClock<PhaseT>): number
	local count = 0
	for _, binding in self._phaseBindings do
		if binding.active then
			count += 1
		end
	end
	return count
end

function FakeClock.getScheduleCount<PhaseT>(self: FakeClock<PhaseT>): number
	return self._scheduleCount
end

function FakeClock.getRescheduleCount<PhaseT>(self: FakeClock<PhaseT>): number
	return self._rescheduleCount
end

function FakeClock.getCancelCount<PhaseT>(self: FakeClock<PhaseT>): number
	return self._cancelCount
end

function FakeClock.getLastTaskId<PhaseT>(self: FakeClock<PhaseT>): number?
	return self._lastTaskId
end

return FakeClock
