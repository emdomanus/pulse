--!strict

export type Release = () -> ()
export type ScheduledTaskId = number
export type DirectionName = "forward" | "backward"
export type DirectionToken = {
	name: DirectionName,
}
export type ClockSample = {
	timePosition: number,
	rate: number,
}
export type ClockChange = {
	previousTimePosition: number?,
	currentTimePosition: number,
	discontinuous: boolean,
}
export type ClockChangedCallback = (change: ClockChange) -> ()
export type PhaseCallback = (clockDt: number, now: number) -> ()
export type ReachedCallback = (now: number, direction: DirectionToken) -> ()

type ChangeBinding = {
	callback: ClockChangedCallback,
	active: boolean,
}

type PhaseState<PhaseT> = {
	phase: PhaseT,
	lastTimePosition: number,
}

type PhaseBinding<PhaseT> = {
	phase: PhaseT,
	callback: PhaseCallback,
	active: boolean,
}

type ReachedRecord<PhaseT> = {
	id: ScheduledTaskId,
	timePosition: number,
	direction: DirectionToken,
	callback: ReachedCallback,
	phase: PhaseT,
	wakeAtRoot: number?,
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
	bindToChanged: (self: FakeClock<PhaseT>, callback: ClockChangedCallback, runInitially: boolean?) -> Release,
	isDestroyed: (self: FakeClock<PhaseT>) -> boolean,
	bindToReached: (
		self: FakeClock<PhaseT>,
		timePosition: number,
		direction: DirectionToken,
		callback: ReachedCallback,
		phase: PhaseT
	) -> ScheduledTaskId,
	cancel: (self: FakeClock<PhaseT>, id: ScheduledTaskId) -> boolean,
	rescheduleAt: (self: FakeClock<PhaseT>, id: ScheduledTaskId, runAt: number, phase: PhaseT) -> boolean,
	bindPhase: (self: FakeClock<PhaseT>, phase: PhaseT, callback: PhaseCallback) -> Release,
	advanceRootTo: (self: FakeClock<PhaseT>, rootTime: number) -> (),
	stepRootTo: (self: FakeClock<PhaseT>, rootTime: number, phase: PhaseT) -> (),
	evaluatePhase: (self: FakeClock<PhaseT>, phase: PhaseT) -> (),
	setRate: (self: FakeClock<PhaseT>, rate: number) -> (),
	jumpTo: (self: FakeClock<PhaseT>, timePosition: number) -> (),
	destroy: (self: FakeClock<PhaseT>) -> (),
	getTaskCount: (self: FakeClock<PhaseT>) -> number,
	getPhaseBindingCount: (self: FakeClock<PhaseT>) -> number,
	getChangedBindingCount: (self: FakeClock<PhaseT>) -> number,
	getTaskWakeAtRoot: (self: FakeClock<PhaseT>, id: ScheduledTaskId) -> number?,
	getRetimeCount: (self: FakeClock<PhaseT>) -> number,
	_rootTime: number,
	_rootAtAnchor: number,
	_timeAtAnchor: number,
	_rate: number,
	_destroyed: boolean,
	_nextTaskId: number,
	_tasks: { [number]: ReachedRecord<PhaseT> },
	_changedBindings: { ChangeBinding },
	_phaseStates: { PhaseState<PhaseT> },
	_phaseBindings: { PhaseBinding<PhaseT> },
	_retimeCount: number,
}

local FORWARD: DirectionToken = table.freeze({ name = "forward" })
local BACKWARD: DirectionToken = table.freeze({ name = "backward" })

local FakeClock = {}
FakeClock.__index = FakeClock

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function currentTimePosition<PhaseT>(self: FakeClock<PhaseT>): number
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
		lastTimePosition = currentTimePosition(self),
	}
	table.insert(self._phaseStates, state)
	return state
end

local function retimeRecord<PhaseT>(self: FakeClock<PhaseT>, record: ReachedRecord<PhaseT>)
	local now = currentTimePosition(self)
	local movesTowardTarget = (self._rate > 0 and record.direction == FORWARD and record.timePosition > now)
		or (self._rate < 0 and record.direction == BACKWARD and record.timePosition < now)
	if movesTowardTarget then
		record.wakeAtRoot = self._rootTime + (record.timePosition - now) / self._rate
	else
		record.wakeAtRoot = nil
	end
	self._retimeCount += 1
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
	local config = options or {}
	local rootTime = config.rootTime or 0
	local timePosition = config.timePosition or 0
	local rate = config.rate or 1
	assert(isFinite(rootTime), "fake clock rootTime must be finite")
	assert(isFinite(timePosition), "fake clock timePosition must be finite")
	assert(isFinite(rate), "fake clock rate must be finite")

	return setmetatable({
		directions = table.freeze({
			forward = FORWARD,
			backward = BACKWARD,
		}),
		_rootTime = rootTime,
		_rootAtAnchor = rootTime,
		_timeAtAnchor = timePosition,
		_rate = rate,
		_destroyed = false,
		_nextTaskId = 0,
		_tasks = {},
		_changedBindings = {},
		_phaseStates = {},
		_phaseBindings = {},
		_retimeCount = 0,
	}, FakeClock) :: FakeClock<PhaseT>
end

function FakeClock.read<PhaseT>(self: FakeClock<PhaseT>): ClockSample
	return {
		timePosition = currentTimePosition(self),
		rate = self._rate,
	}
end

function FakeClock.bindToChanged<PhaseT>(
	self: FakeClock<PhaseT>,
	callback: ClockChangedCallback,
	runInitially: boolean?
): Release
	assert(not self._destroyed, "cannot bind a destroyed fake clock")
	local binding: ChangeBinding = {
		callback = callback,
		active = true,
	}
	table.insert(self._changedBindings, binding)
	if runInitially == true then
		callback({
			previousTimePosition = nil,
			currentTimePosition = currentTimePosition(self),
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
): ScheduledTaskId
	assert(not self._destroyed, "cannot schedule a destroyed fake clock")
	assert(isFinite(timePosition), "fake reached timePosition must be finite")
	assert(direction == FORWARD or direction == BACKWARD, "fake reached direction token is invalid")
	getPhaseState(self, phase)

	self._nextTaskId += 1
	local id = self._nextTaskId
	local record: ReachedRecord<PhaseT> = {
		id = id,
		timePosition = timePosition,
		direction = direction,
		callback = callback,
		phase = phase,
		wakeAtRoot = nil,
		active = true,
		running = false,
		rescheduled = false,
	}
	self._tasks[id] = record
	retimeRecord(self, record)
	return id
end

function FakeClock.cancel<PhaseT>(self: FakeClock<PhaseT>, id: ScheduledTaskId): boolean
	local record = self._tasks[id]
	if record == nil or not record.active then
		return false
	end
	record.active = false
	if not record.running then
		self._tasks[id] = nil
	end
	return true
end

function FakeClock.rescheduleAt<PhaseT>(self: FakeClock<PhaseT>, id: ScheduledTaskId, runAt: number, phase: PhaseT): boolean
	local record = self._tasks[id]
	if record == nil or not record.active or self._destroyed then
		return false
	end
	assert(isFinite(runAt), "fake reschedule runAt must be finite")
	getPhaseState(self, phase)
	record.timePosition = runAt
	record.phase = phase
	record.rescheduled = true
	retimeRecord(self, record)
	return true
end

function FakeClock.bindPhase<PhaseT>(self: FakeClock<PhaseT>, phase: PhaseT, callback: PhaseCallback): Release
	assert(not self._destroyed, "cannot bind a phase on a destroyed fake clock")
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

local function crossed(previous: number, current: number, target: number, direction: DirectionToken): boolean
	if direction == FORWARD then
		return previous < target and target <= current
	end
	return previous > target and target >= current
end

local function nextDue<PhaseT>(
	self: FakeClock<PhaseT>,
	phase: PhaseT,
	previous: number,
	current: number,
	direction: DirectionToken
): ReachedRecord<PhaseT>?
	local selected: ReachedRecord<PhaseT>? = nil
	for _, record in self._tasks do
		if
			record.active
			and record.phase == phase
			and record.direction == direction
			and crossed(previous, current, record.timePosition, direction)
		then
			local shouldSelect = selected == nil
			if selected ~= nil then
				if direction == FORWARD then
					shouldSelect = record.timePosition < selected.timePosition
						or (record.timePosition == selected.timePosition and record.id < selected.id)
				else
					shouldSelect = record.timePosition > selected.timePosition
						or (record.timePosition == selected.timePosition and record.id < selected.id)
				end
			end
			if shouldSelect then
				selected = record
			end
		end
	end
	return selected
end

function FakeClock.evaluatePhase<PhaseT>(self: FakeClock<PhaseT>, phase: PhaseT)
	assert(not self._destroyed, "cannot evaluate a destroyed fake clock")
	local state = getPhaseState(self, phase)
	local previous = state.lastTimePosition
	local current = currentTimePosition(self)
	state.lastTimePosition = current

	local actualDirection: DirectionToken? = nil
	if current > previous then
		actualDirection = FORWARD
	elseif current < previous then
		actualDirection = BACKWARD
	end

	if actualDirection ~= nil then
		while true do
			local record = nextDue(self, phase, previous, current, actualDirection)
			if record == nil then
				break
			end

			record.running = true
			record.rescheduled = false
			record.callback(current, actualDirection)
			record.running = false
			if not record.active or not record.rescheduled then
				record.active = false
				self._tasks[record.id] = nil
			else
				retimeRecord(self, record)
			end
		end
	end

	local bindings = table.clone(self._phaseBindings)
	local now = currentTimePosition(self)
	for _, binding in bindings do
		if binding.active and binding.phase == phase then
			binding.callback(now - previous, now)
		end
	end
end

function FakeClock.advanceRootTo<PhaseT>(self: FakeClock<PhaseT>, rootTime: number)
	assert(isFinite(rootTime) and rootTime >= self._rootTime, "fake root time must advance monotonically")
	self._rootTime = rootTime
end

function FakeClock.stepRootTo<PhaseT>(self: FakeClock<PhaseT>, rootTime: number, phase: PhaseT)
	self:advanceRootTo(rootTime)
	self:evaluatePhase(phase)
end

function FakeClock.setRate<PhaseT>(self: FakeClock<PhaseT>, rate: number)
	assert(not self._destroyed, "cannot change a destroyed fake clock")
	assert(isFinite(rate), "fake clock rate must be finite")
	local current = currentTimePosition(self)
	self._rootAtAnchor = self._rootTime
	self._timeAtAnchor = current
	self._rate = rate
	for _, record in self._tasks do
		if record.active then
			retimeRecord(self, record)
		end
	end
	notifyChanged(self, {
		previousTimePosition = current,
		currentTimePosition = current,
		discontinuous = false,
	})
end

function FakeClock.jumpTo<PhaseT>(self: FakeClock<PhaseT>, timePosition: number)
	assert(not self._destroyed, "cannot jump a destroyed fake clock")
	assert(isFinite(timePosition), "fake clock jump must be finite")
	local previous = currentTimePosition(self)
	self._rootAtAnchor = self._rootTime
	self._timeAtAnchor = timePosition
	for _, state in self._phaseStates do
		state.lastTimePosition = timePosition
	end
	for _, record in self._tasks do
		if record.active then
			retimeRecord(self, record)
		end
	end
	notifyChanged(self, {
		previousTimePosition = previous,
		currentTimePosition = timePosition,
		discontinuous = true,
	})
end

function FakeClock.destroy<PhaseT>(self: FakeClock<PhaseT>)
	if self._destroyed then
		return
	end
	local current = currentTimePosition(self)
	self._rootAtAnchor = self._rootTime
	self._timeAtAnchor = current
	self._rate = 0
	self._destroyed = true

	for id, record in self._tasks do
		record.active = false
		self._tasks[id] = nil
	end
	for _, binding in self._phaseBindings do
		binding.active = false
	end
	notifyChanged(self, {
		previousTimePosition = current,
		currentTimePosition = current,
		discontinuous = true,
	})
	for _, binding in self._changedBindings do
		binding.active = false
	end
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

function FakeClock.getPhaseBindingCount<PhaseT>(self: FakeClock<PhaseT>): number
	local count = 0
	for _, binding in self._phaseBindings do
		if binding.active then
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

function FakeClock.getTaskWakeAtRoot<PhaseT>(self: FakeClock<PhaseT>, id: ScheduledTaskId): number?
	local record = self._tasks[id]
	return if record == nil then nil else record.wakeAtRoot
end

function FakeClock.getRetimeCount<PhaseT>(self: FakeClock<PhaseT>): number
	return self._retimeCount
end

return FakeClock
