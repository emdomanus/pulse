--!strict

local requireAny = require :: any
local Harness = requireAny("../lib/testHarness")
local FakeClock = requireAny("../lib/fakeClock")

Harness.test("fake clock reads mappings and publishes continuous changes", function()
	local clock = FakeClock.new({
		timePosition = 4,
		rate = 2,
	})
	local changes = {}
	local release = clock:bindToChanged(function(change)
		table.insert(changes, change)
	end, true)

	Harness.assertEqual(clock:read().timePosition, 4)
	Harness.assertEqual(clock:read().rate, 2)
	Harness.assertEqual(clock:getChangedBindingCount(), 1)
	Harness.assertEqual(changes[1].previousTimePosition, nil)
	clock:advanceRootTo(3)
	Harness.assertEqual(clock:read().timePosition, 10)
	clock:setRate(-1)
	Harness.assertEqual(changes[2].previousTimePosition, 10)
	Harness.assertEqual(changes[2].currentTimePosition, 10)
	Harness.assertFalse(changes[2].discontinuous)
	release()
	release()
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
end)

Harness.test("fake clock schedules by explicit phase and reports actual direction", function()
	local clock = FakeClock.new()
	local directions = {}
	clock:bindToReached(5, clock.directions.forward, function(_now, direction)
		table.insert(directions, direction)
	end, "presentation")

	clock:stepRootTo(5, "simulation")
	Harness.assertEqual(#directions, 0)
	Harness.assertEqual(clock:getTaskCount(), 1)
	clock:evaluatePhase("presentation")
	Harness.assertArrayEqual(directions, { clock.directions.forward })
	Harness.assertEqual(clock:getTaskCount(), 0)

	local backward = FakeClock.new({ timePosition = 10, rate = -1 })
	local actual = nil
	backward:bindToReached(7, backward.directions.backward, function(_now, direction)
		actual = direction
	end, "presentation")
	backward:stepRootTo(3, "presentation")
	Harness.assertEqual(actual, backward.directions.backward)
end)

Harness.test("fake clock supports cancellation and in-callback rescheduleAt", function()
	local clock = FakeClock.new()
	local runs = 0
	local id = 0
	id = clock:bindToReached(1, clock.directions.forward, function()
		runs += 1
		if runs == 1 then
			Harness.assertTrue(clock:rescheduleAt(id, 4, "render"))
		end
	end, "render")

	clock:stepRootTo(2, "render")
	Harness.assertEqual(runs, 1)
	Harness.assertEqual(clock:getTaskCount(), 1)
	clock:stepRootTo(4, "render")
	Harness.assertEqual(runs, 2)
	Harness.assertEqual(clock:getTaskCount(), 0)

	local cancelId = clock:bindToReached(5, clock.directions.forward, function()
		error("cancelled task ran")
	end, "render")
	Harness.assertTrue(clock:cancel(cancelId))
	Harness.assertFalse(clock:cancel(cancelId))
	clock:stepRootTo(5, "render")
	Harness.assertEqual(clock:getTaskCount(), 0)

	local cancelClock = FakeClock.new()
	local cancelInsideId = 0
	cancelInsideId = cancelClock:bindToReached(1, cancelClock.directions.forward, function()
		Harness.assertTrue(cancelClock:cancel(cancelInsideId))
		Harness.assertFalse(cancelClock:cancel(cancelInsideId))
	end, "render")
	cancelClock:stepRootTo(1, "render")
	Harness.assertEqual(cancelClock:getTaskCount(), 0)
end)

Harness.test("fake clock retimes local deadlines across continuous rate changes", function()
	local clock = FakeClock.new()
	local reached = 0
	local id = clock:bindToReached(10, clock.directions.forward, function()
		reached += 1
	end, "render")
	Harness.assertNear(clock:getTaskWakeAtRoot(id), 10)
	clock:advanceRootTo(2)
	local retimesBefore = clock:getRetimeCount()
	clock:setRate(2)
	Harness.assertEqual(clock:getRetimeCount(), retimesBefore + 1)
	Harness.assertNear(clock:getTaskWakeAtRoot(id), 6)
	clock:stepRootTo(6, "render")
	Harness.assertEqual(reached, 1)
end)

Harness.test("fake clock owns explicit phase bindings and binding counts", function()
	local clock = FakeClock.new()
	local samples = {}
	local release = clock:bindPhase("render", function(clockDt, now)
		table.insert(samples, { clockDt, now })
	end)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	clock:stepRootTo(2, "render")
	Harness.assertEqual(samples[1][1], 2)
	Harness.assertEqual(samples[1][2], 2)
	release()
	release()
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	clock:stepRootTo(3, "render")
	Harness.assertEqual(#samples, 1)
end)

Harness.test("fake clock jumps and destruction are observable without crossed work", function()
	local clock = FakeClock.new()
	local changes = {}
	local reached = 0
	clock:bindToChanged(function(change)
		table.insert(changes, {
			change = change,
			destroyed = clock:isDestroyed(),
		})
	end)
	clock:bindToReached(5, clock.directions.forward, function()
		reached += 1
	end, "render")
	clock:jumpTo(10)
	clock:evaluatePhase("render")
	Harness.assertEqual(reached, 0)
	Harness.assertTrue(changes[1].change.discontinuous)
	Harness.assertFalse(changes[1].destroyed)
	clock:bindPhase("render", function() end)
	clock:destroy()
	Harness.assertTrue(changes[2].destroyed)
	Harness.assertTrue(clock:isDestroyed())
	Harness.assertEqual(clock:getTaskCount(), 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
end)

return nil
