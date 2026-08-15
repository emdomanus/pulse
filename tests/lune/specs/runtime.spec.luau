--!strict

local requireAny = require :: any
local Harness = requireAny("../lib/testHarness")
local Transform = requireAny("../lib/luneRequireTransform")
local FakeClock = requireAny("../lib/fakeClock")

local transformedPackage = Transform.write({
	packageRoot = "src",
	tempDir = "tests/lune/.tmp/pulse-runtime",
})
local Pulse = transformedPackage.requireModule("pulse/init.luau") :: any
transformedPackage.cleanup()

local function createPlayback(runtime: any, sequence: any, clock: any, phase: any, extra: any?): any
	local options = extra or {}
	options.clock = clock
	options.directions = clock.directions
	options.phase = phase
	return runtime:createPlayback(sequence, options)
end

Harness.test("createPlayback is inert and event-only playbacks never bind continuous work", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local callbacks = 0
	local ended = 0
	local sequence = Pulse.sequence({
		duration = 0,
		events = {
			{
				time = 0,
				run = function()
					callbacks += 1
				end,
				reverse = "ignore",
			},
		},
	})
	local playback = createPlayback(runtime, sequence, clock, "simulation")
	playback:onEnded(function(completion: any)
		ended += 1
		Harness.assertEqual(completion.status, "completed")
	end)

	Harness.assertEqual(callbacks, 0)
	Harness.assertEqual(clock:getTaskCount(), 0)
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	playback:play()
	Harness.assertEqual(callbacks, 1)
	Harness.assertEqual(ended, 1)
	Harness.assertEqual(playback:getStatus(), "completed")
	Harness.assertEqual(clock:getTaskCount(), 0)
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)

	local futureRuns = 0
	local future = createPlayback(
		runtime,
		Pulse.sequence({
			duration = 2,
			events = {
				{
					time = 1,
					run = function()
						futureRuns += 1
					end,
					reverse = "ignore",
				},
				{
					time = 2,
					run = function()
						futureRuns += 1
					end,
					reverse = "ignore",
				},
			},
		}),
		clock,
		"simulation"
	)
	future:play()
	Harness.assertEqual(clock:getTaskCount(), 1)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	Harness.assertEqual(clock:getChangedBindingCount(), 1)
	clock:stepRootTo(2, "simulation")
	Harness.assertEqual(futureRuns, 2)
	Harness.assertEqual(future:getStatus(), "completed")
	Harness.assertEqual(clock:getTaskCount(), 0)
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
	runtime:destroy()
end)

Harness.test("updating playbacks lazily share exact clock and phase groups", function()
	local clockA = FakeClock.new()
	local clockB = FakeClock.new()
	local runtime = Pulse.new()
	local updateCalls = 0
	local sequence = Pulse.sequence({
		duration = 10,
		updates = {
			{
				run = function(_ctx: any, dt: number, position: number)
					updateCalls += 1
					Harness.assertNear(dt, 0.25)
					Harness.assertNear(position, 0.25)
				end,
			},
		},
	})
	local first = createPlayback(runtime, sequence, clockA, "simulation")
	local second = createPlayback(runtime, sequence, clockA, "simulation")
	local otherPhase = createPlayback(runtime, sequence, clockA, "render")
	local otherClock = createPlayback(runtime, sequence, clockB, "simulation")
	Harness.assertEqual(clockA:getPhaseBindingCount(), 0)
	first:play()
	second:play()
	otherPhase:play()
	otherClock:play()
	Harness.assertEqual(clockA:getPhaseBindingCount(), 2)
	Harness.assertEqual(clockA:getChangedBindingCount(), 1)
	Harness.assertEqual(clockB:getPhaseBindingCount(), 1)
	Harness.assertEqual(clockB:getChangedBindingCount(), 1)

	first:pause()
	Harness.assertEqual(clockA:getPhaseBindingCount(), 2)
	second:pause()
	Harness.assertEqual(clockA:getPhaseBindingCount(), 1)
	second:resume()
	Harness.assertEqual(clockA:getPhaseBindingCount(), 2)
	clockA:stepRootTo(0.25, "simulation")
	Harness.assertEqual(updateCalls, 1)
	second:pause()
	Harness.assertEqual(clockA:getPhaseBindingCount(), 1)
	otherPhase:stop()
	Harness.assertEqual(clockA:getPhaseBindingCount(), 0)
	otherClock:stop()
	Harness.assertEqual(clockB:getPhaseBindingCount(), 0)
	first:stop()
	second:stop()
	Harness.assertEqual(clockA:getChangedBindingCount(), 0)
	Harness.assertEqual(clockB:getChangedBindingCount(), 0)
	Harness.assertFalse(clockA:isDestroyed())
	runtime:destroy()
end)

Harness.test("one reached task reschedules in callback and cancels exactly once", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local runs: { string } = {}
	local playback = createPlayback(
		runtime,
		Pulse.sequence({
			duration = 3,
			events = {
				{
					time = 1,
					run = function()
						table.insert(runs, "one")
					end,
					reverse = "ignore",
				},
				{
					time = 2,
					run = function()
						table.insert(runs, "two")
					end,
					reverse = "ignore",
				},
			},
		}),
		clock,
		"simulation"
	)
	playback:play()
	Harness.assertEqual(clock:getTaskCount(), 1)
	clock:stepRootTo(1, "simulation")
	Harness.assertArrayEqual(runs, { "one" })
	Harness.assertEqual(clock:getTaskCount(), 1)
	clock:stepRootTo(2, "simulation")
	Harness.assertArrayEqual(runs, { "one", "two" })
	Harness.assertEqual(clock:getTaskCount(), 1)
	playback:stop()
	Harness.assertEqual(clock:getTaskCount(), 0)
	playback:stop()
	Harness.assertEqual(clock:getTaskCount(), 0)
	runtime:destroy()
end)

Harness.test("clock-rate and playback-speed changes preserve anchors and direction", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local events: { string } = {}
	local playback = createPlayback(
		runtime,
		Pulse.sequence({
			duration = 3,
			events = {
				{
					time = 2,
					run = function()
						table.insert(events, "forward")
					end,
					reverse = function()
						table.insert(events, "reverse")
					end,
				},
			},
		}),
		clock,
		"simulation"
	)
	playback:play()
	clock:stepRootTo(1, "simulation")
	Harness.assertNear(playback:getPosition().unwrappedTimePosition, 1)
	clock:setRate(2)
	Harness.assertNear(playback:getPosition().unwrappedTimePosition, 1)
	clock:stepRootTo(1.5, "simulation")
	Harness.assertArrayEqual(events, { "forward" })
	Harness.assertNear(playback:getPosition().unwrappedTimePosition, 2)
	playback:setPlaybackSpeed(-1)
	Harness.assertNear(playback:getPosition().unwrappedTimePosition, 2)
	Harness.assertArrayEqual(events, { "forward", "reverse" })
	clock:stepRootTo(2, "simulation")
	Harness.assertNear(playback:getPosition().unwrappedTimePosition, 1)
	playback:setPlaybackSpeed(0)
	clock:stepRootTo(3, "simulation")
	Harness.assertNear(playback:getPosition().unwrappedTimePosition, 1)
	playback:setPlaybackSpeed(1)
	Harness.assertNear(playback:getPosition().unwrappedTimePosition, 1)
	playback:stop()
	runtime:destroy()
end)

Harness.test("pause and resume discard paused clock movement", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local hits = 0
	local playback = createPlayback(
		runtime,
		Pulse.sequence({
			duration = 2,
			events = {
				{
					time = 1,
					run = function()
						hits += 1
					end,
					reverse = "ignore",
				},
			},
		}),
		clock,
		"simulation"
	)
	playback:play()
	clock:stepRootTo(0.5, "simulation")
	playback:pause()
	Harness.assertEqual(clock:getTaskCount(), 0)
	clock:stepRootTo(10, "simulation")
	Harness.assertNear(playback:getPosition().unwrappedTimePosition, 0.5)
	Harness.assertEqual(hits, 0)
	playback:resume()
	Harness.assertNear(playback:getPosition().unwrappedTimePosition, 0.5)
	clock:stepRootTo(10.5, "simulation")
	Harness.assertEqual(hits, 1)
	playback:stop()
	runtime:destroy()
end)

Harness.test("continuous updates receive signed sequence delta only while active", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local deltas: { number } = {}
	local positions: { number } = {}
	local playback = createPlayback(
		runtime,
		Pulse.sequence({
			duration = 3,
			updates = {
				{
					run = function(_ctx: any, dt: number, position: number)
						table.insert(deltas, dt)
						table.insert(positions, position)
					end,
				},
			},
		}),
		clock,
		"simulation",
		{
			position = { timePosition = 2 },
			playbackSpeed = -1,
		}
	)
	playback:play()
	clock:stepRootTo(0.25, "simulation")
	Harness.assertNear(deltas[1], -0.25)
	Harness.assertNear(positions[1], 1.75)
	playback:setPlaybackSpeed(0)
	clock:stepRootTo(0.5, "simulation")
	Harness.assertNear(deltas[2], 0)
	Harness.assertNear(positions[2], 1.75)
	playback:pause()
	clock:stepRootTo(1, "simulation")
	Harness.assertEqual(#deltas, 2)
	playback:stop()
	runtime:destroy()
end)

Harness.test("missed events catch up in exact forward and inverse equal-time order", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local order: { string } = {}
	local function event(time: number, name: string): any
		return {
			time = time,
			run = function()
				table.insert(order, "f" .. name)
			end,
			reverse = function()
				table.insert(order, "r" .. name)
			end,
		}
	end
	local playback = createPlayback(
		runtime,
		Pulse.sequence({
			duration = 2,
			events = {
				event(0.5, "a"),
				event(0.5, "b"),
				event(1, "c"),
			},
		}),
		clock,
		"simulation"
	)
	playback:play()
	clock:stepRootTo(1.5, "simulation")
	Harness.assertArrayEqual(order, { "fa", "fb", "fc" })
	playback:setPlaybackSpeed(-1)
	clock:stepRootTo(2.5, "simulation")
	Harness.assertArrayEqual(order, { "fa", "fb", "fc", "rc", "rb", "ra" })
	playback:stop()
	runtime:destroy()
end)

Harness.test("loop traversal drains multiple boundaries in exact bidirectional order", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local order: { string } = {}
	local playback = createPlayback(
		runtime,
		Pulse.sequence({
			duration = 1,
			loop = true,
			events = {
				{
					time = 0,
					run = function()
						table.insert(order, "f0")
					end,
					reverse = function()
						table.insert(order, "r0")
					end,
				},
				{
					time = 1,
					run = function()
						table.insert(order, "f1")
					end,
					reverse = function()
						table.insert(order, "r1")
					end,
				},
			},
			onLoop = function(_ctx: any, change: any)
				table.insert(order, `l{change.fromLoopIndex}>{change.toLoopIndex}`)
			end,
		}),
		clock,
		"simulation"
	)
	playback:play()
	clock:stepRootTo(2.2, "simulation")
	Harness.assertArrayEqual(order, {
		"f0",
		"f1",
		"l0>1",
		"f0",
		"f1",
		"l1>2",
		"f0",
	})
	Harness.assertEqual(playback:getPosition().loopIndex, 2)
	Harness.assertNear(playback:getPosition().timePosition, 0.2)
	playback:setPlaybackSpeed(-1)
	clock:stepRootTo(2.4001, "simulation")
	Harness.assertArrayEqual(order, {
		"f0",
		"f1",
		"l0>1",
		"f0",
		"f1",
		"l1>2",
		"f0",
		"r0",
		"l2>1",
		"r1",
	})
	Harness.assertEqual(playback:getPosition().loopIndex, 1)
	Harness.assertNear(playback:getPosition().timePosition, 0.9999, 1e-6)
	playback:stop()
	runtime:destroy()
end)

Harness.test("timed-step occurrences reverse recorded state without rerunning gates", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local order: { string } = {}
	local gateCalls = 0
	local playback = createPlayback(
		runtime,
		Pulse.sequence({
			duration = 2,
			steps = {
				active = {
					time = 0,
					canEnter = function()
						gateCalls += 1
						return true
					end,
					run = function()
						table.insert(order, "stepRun")
					end,
					reverse = function()
						table.insert(order, "stepReverse")
					end,
				},
			},
			events = {
				{
					time = 0.5,
					step = "active",
					run = function()
						table.insert(order, "eventRun")
					end,
					reverse = function()
						table.insert(order, "eventReverse")
					end,
				},
			},
			onStep = function(_ctx: any, change: any)
				table.insert(order, `step:{tostring(change.direction)}`)
			end,
		}),
		clock,
		"simulation"
	)
	playback:play()
	clock:stepRootTo(0.5, "simulation")
	Harness.assertArrayEqual(order, { "stepRun", "step:forward", "eventRun" })
	Harness.assertEqual(playback:getStep(), "active")
	playback:setPlaybackSpeed(-1)
	Harness.assertArrayEqual(order, {
		"stepRun",
		"step:forward",
		"eventRun",
		"eventReverse",
		"stepReverse",
		"step:backward",
	})
	Harness.assertEqual(playback:getStep(), nil)
	Harness.assertEqual(gateCalls, 1)
	playback:stop()
	runtime:destroy()
end)

Harness.test("reentrant direction change commits one occurrence before inverse traversal", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local order: { string } = {}
	local playback: any = nil
	local sequence = Pulse.sequence({
		duration = 2,
		events = {
			{
				time = 0.5,
				run = function(ctx: any)
					table.insert(order, "firstForward")
					ctx:setPlaybackSpeed(-1)
				end,
				reverse = function()
					table.insert(order, "firstReverse")
				end,
			},
			{
				time = 0.5,
				run = function()
					table.insert(order, "staleSecond")
				end,
				reverse = "ignore",
			},
		},
	})
	playback = createPlayback(runtime, sequence, clock, "simulation")
	playback:play()
	clock:stepRootTo(0.5, "simulation")
	Harness.assertArrayEqual(order, { "firstForward", "firstReverse" })
	Harness.assertEqual(playback:getPlaybackSpeed(), -1)
	playback:stop()
	runtime:destroy()
end)

Harness.test("terminal mutation interrupts equal-time callbacks and releases ownership once", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local order: { string } = {}
	local ended = 0
	local playback = createPlayback(
		runtime,
		Pulse.sequence({
			duration = 2,
			updates = {
				{
					run = function()
						table.insert(order, "update")
					end,
				},
			},
			events = {
				{
					time = 0.5,
					run = function(ctx: any)
						table.insert(order, "stop")
						ctx:stop("callbackStop")
					end,
					reverse = "ignore",
				},
				{
					time = 0.5,
					run = function()
						table.insert(order, "stale")
					end,
					reverse = "ignore",
				},
			},
		}),
		clock,
		"simulation"
	)
	playback:onEnded(function()
		ended += 1
	end)
	playback:play()
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	clock:stepRootTo(0.5, "simulation")
	Harness.assertArrayEqual(order, { "stop" })
	Harness.assertEqual(ended, 1)
	Harness.assertEqual(playback:getStatus(), "stopped")
	Harness.assertEqual(clock:getTaskCount(), 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
	playback:destroy()
	Harness.assertEqual(ended, 1)
	runtime:destroy()
end)

Harness.test("nested signals queue and observer snapshots isolate listener mutation", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local order: { string } = {}
	local playback = createPlayback(
		runtime,
		Pulse.sequence({
			signals = {
				ping = function(ctx: any)
					table.insert(order, "ping:start")
					ctx:signal("pong")
					table.insert(order, "ping:end")
				end,
				pong = function(ctx: any)
					table.insert(order, "pong")
					ctx:setParam("nested", true)
				end,
			},
		}),
		clock,
		"simulation"
	)
	playback:play()
	playback:signal("ping")
	Harness.assertArrayEqual(order, { "ping:start", "ping:end", "pong" })
	Harness.assertEqual(playback:getParam("nested"), true)

	table.clear(order)
	local releaseSecond: () -> () = function() end
	local added = false
	playback:onSignaled(function()
		table.insert(order, "first")
		releaseSecond()
		if not added then
			added = true
			playback:onSignaled(function()
				table.insert(order, "added")
			end)
		end
	end)
	releaseSecond = playback:onSignaled(function()
		table.insert(order, "second")
	end)
	playback:signal("plain")
	Harness.assertArrayEqual(order, { "first", "second" })
	table.clear(order)
	playback:signal("plain")
	Harness.assertArrayEqual(order, { "first", "added" })
	playback:stop()
	runtime:destroy()
end)

Harness.test("clock sign change before deadline invalidates stale reached direction", function()
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local hits = 0
	local playback = createPlayback(
		runtime,
		Pulse.sequence({
			duration = 2,
			events = {
				{
					time = 1,
					run = function()
						hits += 1
					end,
					reverse = "ignore",
				},
			},
		}),
		clock,
		"simulation"
	)
	playback:play()
	clock:advanceRootTo(0.9)
	clock:setRate(-1)
	Harness.assertNear(playback:getPosition().unwrappedTimePosition, 0.9)
	clock:stepRootTo(1.1, "simulation")
	Harness.assertEqual(hits, 0)
	clock:setRate(1)
	Harness.assertNear(playback:getPosition().unwrappedTimePosition, 0.7)
	clock:stepRootTo(1.4001, "simulation")
	Harness.assertEqual(hits, 1)
	playback:stop()
	runtime:destroy()
end)

local function runCatchUpCase(workCount: number): (number, string, string?)
	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local callbacks = 0
	local events = table.create(workCount)
	for index = 1, workCount do
		events[index] = {
			time = index,
			run = function()
				callbacks += 1
			end,
			reverse = "ignore",
		}
	end
	local playback = createPlayback(
		runtime,
		Pulse.sequence({
			duration = workCount + 1,
			events = events,
		}),
		clock,
		"benchmark"
	)
	playback:play()
	clock:stepRootTo(workCount + 1, "benchmark")
	local status = playback:getStatus()
	local completion = playback:getCompletion()
	runtime:destroy()
	return callbacks, status, if completion == nil then nil else completion.reason
end

Harness.test("reconciliation work limit succeeds below and at the boundary, then fails explicitly", function()
	local belowCallbacks, belowStatus = runCatchUpCase(4_095)
	Harness.assertEqual(belowCallbacks, 4_095)
	Harness.assertEqual(belowStatus, "completed")

	local exactCallbacks, exactStatus = runCatchUpCase(4_096)
	Harness.assertEqual(exactCallbacks, 4_096)
	Harness.assertEqual(exactStatus, "completed")

	local aboveCallbacks, aboveStatus, aboveReason = runCatchUpCase(4_097)
	Harness.assertEqual(aboveCallbacks, 4_096)
	Harness.assertEqual(aboveStatus, "failed")
	Harness.assertEqual(aboveReason, "catchUpLimitExceeded")
end)

return nil
