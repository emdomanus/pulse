--!strict

local requireAny = require :: any
local Harness = requireAny("../lib/testHarness")
local Transform = requireAny("../lib/luneRequireTransform")

local transformedPackage = Transform.write({
	packageRoot = "src",
	tempDir = "tests/lune/.tmp/pulse",
})
local Sequence = transformedPackage.requireModule("pulse/components/sequence/shared/sequence.luau") :: any
local Builder = transformedPackage.requireModule("pulse/components/builder/shared/builder.luau") :: any
local Def = transformedPackage.requireModule("pulse/types/def/init.luau") :: any
transformedPackage.cleanup()

Harness.test("clock boundary guards narrow richer provider records", function()
	local sample = Def.assertClockSample({
		timePosition = 4,
		rate = -2,
		revision = 8,
	})
	Harness.assertEqual(sample.timePosition, 4)
	Harness.assertEqual(sample.rate, -2)
	Harness.assertEqual(sample.revision, nil)

	local change = Def.assertClockChange({
		previousTimePosition = 4,
		currentTimePosition = 6,
		discontinuous = true,
		kind = "seek",
	})
	Harness.assertEqual(change.previousTimePosition, 4)
	Harness.assertEqual(change.currentTimePosition, 6)
	Harness.assertTrue(change.discontinuous)
	Harness.assertEqual(change.kind, nil)
	Harness.assertThrows(function()
		Def.assertClockSample({ timePosition = 0 / 0, rate = 1 })
	end, "timePosition")
end)

Harness.test("compiler rejects invalid authored numeric values", function()
	Harness.assertThrows(function()
		Sequence.compile({ duration = math.huge })
	end, "duration")
	Harness.assertThrows(function()
		Sequence.compile({ cleanupDelay = -1 })
	end, "cleanupDelay")
	Harness.assertThrows(function()
		Sequence.compile({ duration = 1, events = { { time = 2 } } })
	end, "event #1 time")
	Harness.assertThrows(function()
		Sequence.compile({ steps = { start = { time = 0 / 0 } } })
	end, "step time")
	Harness.assertThrows(function()
		Sequence.compile({ transitions = { { after = 2, before = 1 } } })
	end, "after must not exceed before")
	Harness.assertThrows(function()
		Sequence.compile({
			events = {
				[1] = { time = 0 },
				[3] = { time = 1 },
			},
		} :: any)
	end, "dense array")
	Harness.assertThrows(function()
		Sequence.compile({ loop = true })
	end, "positive duration")
	Harness.assertThrows(function()
		Sequence.compile({ duration = 0, loop = true })
	end, "positive duration")
end)

Harness.test("compiler copies and freezes authored records", function()
	local event = {
		time = 0.5,
		name = "original",
		run = function() end,
	}
	local step = {
		time = 0.25,
	}
	local params = {
		power = 4,
	}
	local definition = {
		duration = 1,
		events = { event },
		steps = { active = step },
		params = params,
	}
	local sequence = Sequence.compile(definition)

	event.time = 0.75
	event.name = "mutated"
	step.time = 0.9
	params.power = 9
	table.insert(definition.events, { time = 0.8 })

	Harness.assertEqual(sequence.events[1].time, 0.5)
	Harness.assertEqual(sequence.events[1].name, "original")
	Harness.assertEqual(sequence.steps.active.time, 0.25)
	Harness.assertEqual(sequence.defaultParams.power, 4)
	Harness.assertEqual(#sequence.events, 1)
	Harness.assertTrue(table.isfrozen(sequence))
	Harness.assertTrue(table.isfrozen(sequence.definition))
	Harness.assertTrue(table.isfrozen(sequence.events))
	Harness.assertTrue(table.isfrozen(sequence.events[1]))
	Harness.assertThrows(function()
		sequence.events[1].time = 10
	end)
end)

Harness.test("compiler preserves equal-time author order and private inverse order", function()
	local sequence = Sequence.compile({
		events = {
			{ time = 1, name = "first" },
			{ time = 1, name = "second" },
			{ time = 0, name = "early" },
		},
	})
	local impl = sequence :: any

	Harness.assertArrayEqual({ sequence.events[1].name, sequence.events[2].name, sequence.events[3].name }, {
		"early",
		"first",
		"second",
	})
	Harness.assertArrayEqual({
		impl._reverseEvents[1].definition.name,
		impl._reverseEvents[2].definition.name,
		impl._reverseEvents[3].definition.name,
	}, { "second", "first", "early" })
	Harness.assertArrayEqual({
		impl._forwardEvents[1]._identity,
		impl._forwardEvents[2]._identity,
		impl._forwardEvents[3]._identity,
	}, { 3, 1, 2 })
	Harness.assertEqual(sequence.events[1]._identity, nil)
end)

Harness.test("compiler resolves reverse defaults and validates explicit actions", function()
	local explicitReverse = function() end
	local sequence = Sequence.compile({
		steps = {
			withRun = { time = 0, run = function() end },
			withoutRun = { time = 0 },
			explicit = { time = 0, reverse = explicitReverse },
		},
		events = {
			{ time = 0, run = function() end },
			{ time = 0 },
			{ time = 0, reverse = "ignore" },
		},
	})

	Harness.assertEqual(sequence.steps.withRun.reverse, "cancel")
	Harness.assertEqual(sequence.steps.withoutRun.reverse, "ignore")
	Harness.assertEqual(sequence.steps.explicit.reverse, explicitReverse)
	Harness.assertEqual(sequence.events[1].reverse, "cancel")
	Harness.assertEqual(sequence.events[2].reverse, "ignore")
	Harness.assertEqual(sequence.events[3].reverse, "ignore")
	Harness.assertThrows(function()
		Sequence.compile({ events = { { time = 0, reverse = "invalid" } } } :: any)
	end, "event reverse")
	Harness.assertThrows(function()
		Sequence.compile({ steps = { bad = { time = 0, reverse = "invalid" } } } :: any)
	end, "step reverse")
end)

Harness.test("compiler requires rebuild callbacks and guards loop address identity", function()
	Harness.assertThrows(function()
		Sequence.compile({ addressPolicy = "rebuild" })
	end, "requires onRebuild")

	local sequence = Sequence.compile({
		duration = 1,
		loop = true,
		addressPolicy = "rebuild",
		onRebuild = function()
			return {}
		end,
	})
	local position = Sequence.validateAddress(sequence, {
		timePosition = 1,
		loopIndex = -2,
	})
	Harness.assertEqual(position.timePosition, 1)
	Harness.assertEqual(position.loopIndex, -2)
	Harness.assertEqual(position.unwrappedTimePosition, -1)
	Harness.assertThrows(function()
		Sequence.validateAddress(sequence, {
			timePosition = 0,
			loopIndex = 9_007_199_254_740_992,
		})
	end, "exactly representable")

	local nonLoop = Sequence.compile({ duration = 1 })
	Harness.assertThrows(function()
		Sequence.validateAddress(nonLoop, { timePosition = 0, loopIndex = 1 })
	end, "loopIndex zero")
end)

Harness.test("builder uses canonical records and isolates caller mutation", function()
	local event = {
		time = 0.25,
		name = "builderEvent",
	}
	local builder = Builder.new()
	local sequence = builder
		:duration(1)
		:addressPolicy("skip")
		:step("ready", { time = 0 })
		:event(event)
		:update({
			name = "continuous",
			run = function() end,
		})
		:hold(0.5, "ready", "continue")
		:compile()

	event.time = 0.9
	Harness.assertEqual(sequence.events[1].time, 0.25)
	Harness.assertEqual(sequence.addressPolicy, "skip")
	Harness.assertEqual(sequence.events[2].reverse, "ignore")
	Harness.assertEqual(#sequence.updates, 1)
end)

return nil
