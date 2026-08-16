--!strict

export type Release = () -> ()
export type Phase = "heartbeat"
export type DirectionName = "forward" | "backward"
export type DirectionToken = {
	name: DirectionName,
}

export type ClockSample = {
	timePosition: number,
	rate: number,
	revision: number,
}

export type Diagnostics = {
	reachedTasks: number,
	changedBindings: number,
	phaseBindings: number,
}

type RawChangedCallback = (change: unknown) -> ()
type ReachedCallback = (now: number, direction: unknown) -> ()
type PhaseCallback = (clockDt: number, now: number) -> ()

type ChangedBinding = {
	callback: RawChangedCallback,
	active: boolean,
}

type PhaseBinding = {
	phase: Phase,
	callback: PhaseCallback,
	active: boolean,
}

type ReachedTask = {
	id: number,
	runAt: number,
	previousTimePosition: number,
	direction: DirectionToken,
	callback: ReachedCallback,
	phase: Phase,
	active: boolean,
	running: boolean,
	rescheduled: boolean,
}

export type LiveClock = {
	directions: {
		forward: DirectionToken,
		backward: DirectionToken,
	},
	read: (self: LiveClock) -> ClockSample,
	bindToChanged: (self: LiveClock, callback: RawChangedCallback, runInitially: boolean?) -> Release,
	isDestroyed: (self: LiveClock) -> boolean,
	bindToReached: (
		self: LiveClock,
		timePosition: number,
		direction: DirectionToken,
		callback: ReachedCallback,
		phase: Phase
	) -> number,
	cancel: (self: LiveClock, id: number) -> boolean,
	rescheduleAt: (self: LiveClock, id: number, runAt: number, phase: Phase) -> boolean,
	bindPhase: (self: LiveClock, phase: Phase, callback: PhaseCallback) -> Release,
	step: (self: LiveClock, deltaTime: number) -> (),
	jumpBy: (self: LiveClock, deltaTime: number) -> (),
	destroy: (self: LiveClock) -> (),
	getDiagnostics: (self: LiveClock) -> Diagnostics,
	_timePosition: number,
	_rate: number,
	_revision: number,
	_destroyed: boolean,
	_nextId: number,
	_tasks: { [number]: ReachedTask },
	_changedBindings: { ChangedBinding },
	_phaseBindings: { PhaseBinding },
}

local PHASE: Phase = "heartbeat"
local FORWARD: DirectionToken = table.freeze({ name = "forward" :: DirectionName })
local BACKWARD: DirectionToken = table.freeze({ name = "backward" :: DirectionName })
local MAX_REACHED_WORK = 1_000

local LiveClock = {}
LiveClock.__index = LiveClock
LiveClock.phase = PHASE

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function notifyChanged(self: LiveClock, kind: string, previous: number, discontinuous: boolean)
	local change = {
		kind = kind,
		current = {
			revision = self._revision,
		},
		previousTimePosition = previous,
		currentTimePosition = self._timePosition,
		discontinuous = discontinuous,
	}
	for _, binding in table.clone(self._changedBindings) do
		if binding.active then
			local succeeded, problem = pcall(function(): boolean
				binding.callback(change)
				return true
			end)
			if not succeeded then
				warn(`[Pulse Dev] clock change callback failed: {tostring(problem)}`)
			end
		end
	end
end

local function crossed(current: number, taskRecord: ReachedTask): boolean
	if taskRecord.direction == FORWARD then
		return taskRecord.previousTimePosition < taskRecord.runAt and current >= taskRecord.runAt
	end
	return taskRecord.previousTimePosition > taskRecord.runAt and current <= taskRecord.runAt
end

local function nextDue(self: LiveClock, current: number, drained: { [number]: true }): ReachedTask?
	local selected: ReachedTask? = nil
	for _, taskRecord in self._tasks do
		if taskRecord.active and drained[taskRecord.id] == nil and crossed(current, taskRecord) then
			local choose = selected == nil
			if selected ~= nil then
				choose = if taskRecord.direction == FORWARD
					then taskRecord.runAt < selected.runAt
					else taskRecord.runAt > selected.runAt
			end
			if choose then
				selected = taskRecord
			end
		end
	end
	return selected
end

function LiveClock.new(): LiveClock
	return (
		setmetatable({
			directions = table.freeze({
				forward = FORWARD,
				backward = BACKWARD,
			}),
			_timePosition = 0,
			_rate = 1,
			_revision = 0,
			_destroyed = false,
			_nextId = 0,
			_tasks = {},
			_changedBindings = {},
			_phaseBindings = {},
		}, LiveClock) :: unknown
	) :: LiveClock
end

function LiveClock.read(self: LiveClock): ClockSample
	assert(not self._destroyed, "cannot read a destroyed Pulse dev clock")
	return {
		timePosition = self._timePosition,
		rate = self._rate,
		revision = self._revision,
	}
end

function LiveClock.bindToChanged(self: LiveClock, callback: RawChangedCallback, runInitially: boolean?): Release
	assert(not self._destroyed, "cannot bind a destroyed Pulse dev clock")
	local binding: ChangedBinding = {
		callback = callback,
		active = true,
	}
	table.insert(self._changedBindings, binding)
	if runInitially then
		callback({
			kind = "initial",
			current = {
				revision = self._revision,
			},
			previousTimePosition = nil,
			currentTimePosition = self._timePosition,
			discontinuous = false,
		})
	end
	return function()
		if not binding.active then
			return
		end
		binding.active = false
		for index, candidate in self._changedBindings do
			if candidate == binding then
				table.remove(self._changedBindings, index)
				break
			end
		end
	end
end

function LiveClock.isDestroyed(self: LiveClock): boolean
	return self._destroyed
end

function LiveClock.bindToReached(
	self: LiveClock,
	timePosition: number,
	direction: DirectionToken,
	callback: ReachedCallback,
	phase: Phase
): number
	assert(not self._destroyed and isFinite(timePosition), "invalid Pulse dev reached task")
	assert(direction == FORWARD or direction == BACKWARD, "unknown Pulse dev direction token")
	assert(phase == PHASE, "unknown Pulse dev phase")
	self._nextId += 1
	local id = self._nextId
	self._tasks[id] = {
		id = id,
		runAt = timePosition,
		previousTimePosition = self._timePosition,
		direction = direction,
		callback = callback,
		phase = phase,
		active = true,
		running = false,
		rescheduled = false,
	}
	return id
end

function LiveClock.cancel(self: LiveClock, id: number): boolean
	local taskRecord = self._tasks[id]
	if taskRecord == nil or not taskRecord.active then
		return false
	end
	taskRecord.active = false
	if not taskRecord.running then
		self._tasks[id] = nil
	end
	return true
end

function LiveClock.rescheduleAt(self: LiveClock, id: number, runAt: number, phase: Phase): boolean
	local taskRecord = self._tasks[id]
	if taskRecord == nil or not taskRecord.active or self._destroyed then
		return false
	end
	assert(isFinite(runAt), "Pulse dev reached position must be finite")
	assert(phase == PHASE, "unknown Pulse dev phase")
	taskRecord.runAt = runAt
	taskRecord.previousTimePosition = self._timePosition
	taskRecord.phase = phase
	taskRecord.rescheduled = taskRecord.running
	return true
end

function LiveClock.bindPhase(self: LiveClock, phase: Phase, callback: PhaseCallback): Release
	assert(not self._destroyed, "cannot bind phase on a destroyed Pulse dev clock")
	assert(phase == PHASE, "unknown Pulse dev phase")
	local binding: PhaseBinding = {
		phase = phase,
		callback = callback,
		active = true,
	}
	table.insert(self._phaseBindings, binding)
	return function()
		if not binding.active then
			return
		end
		binding.active = false
		for index, candidate in self._phaseBindings do
			if candidate == binding then
				table.remove(self._phaseBindings, index)
				break
			end
		end
	end
end

function LiveClock.step(self: LiveClock, deltaTime: number)
	if self._destroyed then
		return
	end
	assert(isFinite(deltaTime) and deltaTime >= 0, "Pulse dev deltaTime must be finite and non-negative")
	local previous = self._timePosition
	self._timePosition += deltaTime * self._rate
	local current = self._timePosition
	local drained: { [number]: true } = {}
	local workCount = 0
	while true do
		local taskRecord = nextDue(self, current, drained)
		if taskRecord == nil then
			break
		end
		workCount += 1
		if workCount > MAX_REACHED_WORK then
			warn("[Pulse Dev] reached task drain exceeded its safety limit")
			break
		end
		drained[taskRecord.id] = true
		taskRecord.running = true
		taskRecord.rescheduled = false
		local succeeded, problem = pcall(function(): boolean
			taskRecord.callback(current, taskRecord.direction)
			return true
		end)
		taskRecord.running = false
		if not succeeded then
			warn(`[Pulse Dev] reached callback failed: {tostring(problem)}`)
			taskRecord.active = false
		end
		if not taskRecord.active or not taskRecord.rescheduled then
			taskRecord.active = false
			self._tasks[taskRecord.id] = nil
		end
	end
	for _, taskRecord in self._tasks do
		if taskRecord.active then
			if taskRecord.rescheduled then
				taskRecord.rescheduled = false
			else
				taskRecord.previousTimePosition = current
			end
		end
	end
	for _, binding in table.clone(self._phaseBindings) do
		if binding.active and binding.phase == PHASE then
			local succeeded, problem = pcall(function(): boolean
				binding.callback(current - previous, current)
				return true
			end)
			if not succeeded then
				warn(`[Pulse Dev] phase callback failed: {tostring(problem)}`)
			end
		end
	end
end

function LiveClock.jumpBy(self: LiveClock, deltaTime: number)
	assert(not self._destroyed and isFinite(deltaTime), "Pulse dev jump must be finite")
	local previous = self._timePosition
	self._timePosition += deltaTime
	self._revision += 1
	notifyChanged(self, "mapping", previous, true)
	for _, taskRecord in self._tasks do
		if taskRecord.active then
			taskRecord.previousTimePosition = self._timePosition
		end
	end
end

function LiveClock.destroy(self: LiveClock)
	if self._destroyed then
		return
	end
	local previous = self._timePosition
	self._destroyed = true
	notifyChanged(self, "destroyed", previous, true)
	self._tasks = {}
	for _, binding in self._phaseBindings do
		binding.active = false
	end
	for _, binding in self._changedBindings do
		binding.active = false
	end
	self._phaseBindings = {}
	self._changedBindings = {}
end

function LiveClock.getDiagnostics(self: LiveClock): Diagnostics
	local reachedTasks = 0
	local changedBindings = 0
	local phaseBindings = 0
	for _, taskRecord in self._tasks do
		if taskRecord.active then
			reachedTasks += 1
		end
	end
	for _, binding in self._changedBindings do
		if binding.active then
			changedBindings += 1
		end
	end
	for _, binding in self._phaseBindings do
		if binding.active then
			phaseBindings += 1
		end
	end
	return {
		reachedTasks = reachedTasks,
		changedBindings = changedBindings,
		phaseBindings = phaseBindings,
	}
end

return LiveClock
