--!strict

export type Release = () -> ()

type TaskRecord = {
	id: number,
	runAt: number,
	callback: () -> (),
	active: boolean,
}

export type FakeRealTimeScheduler = {
	delay: (self: FakeRealTimeScheduler, seconds: number, callback: () -> ()) -> Release,
	advanceBy: (self: FakeRealTimeScheduler, seconds: number) -> (),
	advanceTo: (self: FakeRealTimeScheduler, now: number) -> (),
	now: (self: FakeRealTimeScheduler) -> number,
	getTaskCount: (self: FakeRealTimeScheduler) -> number,
	_now: number,
	_nextId: number,
	_tasks: { [number]: TaskRecord },
}

local FakeRealTimeScheduler = {}
FakeRealTimeScheduler.__index = FakeRealTimeScheduler

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function FakeRealTimeScheduler.new(): FakeRealTimeScheduler
	return setmetatable({
		_now = 0,
		_nextId = 0,
		_tasks = {},
	}, FakeRealTimeScheduler) :: FakeRealTimeScheduler
end

function FakeRealTimeScheduler.delay(self: FakeRealTimeScheduler, seconds: number, callback: () -> ()): Release
	assert(isFinite(seconds) and seconds >= 0, "fake real-time delay must be finite and non-negative")
	self._nextId += 1
	local id = self._nextId
	self._tasks[id] = {
		id = id,
		runAt = self._now + seconds,
		callback = callback,
		active = true,
	}

	return function()
		local record = self._tasks[id]
		if record ~= nil and record.active then
			record.active = false
			self._tasks[id] = nil
		end
	end
end

local function nextDue(self: FakeRealTimeScheduler, target: number): TaskRecord?
	local selected: TaskRecord? = nil
	for _, record in self._tasks do
		if record.active and record.runAt <= target then
			if
				selected == nil
				or record.runAt < selected.runAt
				or (record.runAt == selected.runAt and record.id < selected.id)
			then
				selected = record
			end
		end
	end
	return selected
end

function FakeRealTimeScheduler.advanceTo(self: FakeRealTimeScheduler, now: number)
	assert(isFinite(now) and now >= self._now, "fake real time must advance monotonically")

	while true do
		local record = nextDue(self, now)
		if record == nil then
			break
		end
		self._now = record.runAt
		record.active = false
		self._tasks[record.id] = nil
		record.callback()
	end

	self._now = now
end

function FakeRealTimeScheduler.advanceBy(self: FakeRealTimeScheduler, seconds: number)
	assert(isFinite(seconds) and seconds >= 0, "fake real-time advance must be finite and non-negative")
	self:advanceTo(self._now + seconds)
end

function FakeRealTimeScheduler.now(self: FakeRealTimeScheduler): number
	return self._now
end

function FakeRealTimeScheduler.getTaskCount(self: FakeRealTimeScheduler): number
	local count = 0
	for _, record in self._tasks do
		if record.active then
			count += 1
		end
	end
	return count
end

return FakeRealTimeScheduler
