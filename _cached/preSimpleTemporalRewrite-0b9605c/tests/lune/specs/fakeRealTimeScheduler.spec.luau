--!strict

local requireAny = require :: any
local Harness = requireAny("../lib/testHarness")
local FakeRealTimeScheduler = requireAny("../lib/fakeRealTimeScheduler")

Harness.test("fake real-time scheduler is stable and cancellable", function()
	local scheduler = FakeRealTimeScheduler.new()
	local order = {}
	local cancel = scheduler:delay(2, function()
		table.insert(order, "cancelled")
	end)
	scheduler:delay(1, function()
		table.insert(order, "first")
	end)
	scheduler:delay(1, function()
		table.insert(order, "second")
	end)
	cancel()
	cancel()
	Harness.assertEqual(scheduler:getTaskCount(), 2)
	scheduler:advanceTo(1)
	Harness.assertArrayEqual(order, { "first", "second" })
	Harness.assertEqual(scheduler:now(), 1)
	Harness.assertEqual(scheduler:getTaskCount(), 0)
end)

Harness.test("fake real-time scheduler drains work created inside a due callback", function()
	local scheduler = FakeRealTimeScheduler.new()
	local order = {}
	scheduler:delay(1, function()
		table.insert(order, "outer")
		scheduler:delay(0, function()
			table.insert(order, "inner")
		end)
	end)
	scheduler:advanceBy(1)
	Harness.assertArrayEqual(order, { "outer", "inner" })
	Harness.assertEqual(scheduler:getTaskCount(), 0)
end)

return nil
