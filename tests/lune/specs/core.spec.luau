--!strict

type RequireUnknown = (path: string) -> unknown
local requireUnknown = (require :: unknown) :: RequireUnknown

type HarnessApi = {
	test: (name: string, callback: () -> ()) -> (),
	assertTrue: (value: boolean, message: string?) -> (),
	assertFalse: (value: boolean, message: string?) -> (),
	assertEqual: <T>(actual: T, expected: T, message: string?) -> (),
	assertNear: (actual: number, expected: number, epsilon: number?) -> (),
	assertArrayEqual: <T>(actual: { T }, expected: { T }) -> (),
	assertThrows: (callback: () -> (), pattern: string?) -> (),
}

type Completion = {
	status: "completed" | "cancelled" | "destroyed" | "failed",
	reason: string?,
}

type TimeSample = {
	position: number,
	rate: number,
}

type PlaybackPosition = {
	timePosition: number,
	loopIndex: number,
	unwrappedTimePosition: number,
}

type SampleInfo = {
	position: PlaybackPosition,
	rate: number,
}

type AddressMode = "reconstruct" | "skip"
type AddressInfo = {
	cause: "initial" | "seek",
	mode: AddressMode,
	from: PlaybackPosition?,
	target: PlaybackPosition,
}

type Playback = {
	play: (self: Playback, sample: TimeSample) -> Playback,
	evaluate: (self: Playback, sample: TimeSample) -> boolean,
	pause: (self: Playback) -> (),
	resume: (self: Playback) -> (),
	setPlaybackSpeed: (self: Playback, speed: number) -> (),
	getPlaybackSpeed: (self: Playback) -> number,
	seek: (self: Playback, address: { timePosition: number, loopIndex: number? }, mode: AddressMode) -> boolean,
	getPosition: (self: Playback) -> PlaybackPosition,
	getStatus: (self: Playback) -> string,
	addCleanup: (self: Playback, cleanup: () -> ()) -> (),
	cancel: (self: Playback, reason: string?) -> (),
	destroy: (self: Playback) -> (),
	onEnded: (self: Playback, callback: (completion: Completion) -> ()) -> () -> (),
	onLooped: (
		self: Playback,
		callback: (
			change: {
				fromLoopIndex: number,
				toLoopIndex: number,
				direction: "forward" | "backward",
			}
		) -> ()
	) -> () -> (),
	isAlive: (self: Playback) -> boolean,
	getCompletion: (self: Playback) -> Completion?,
}

type Event = {
	time: number,
	run: (playback: Playback, context: unknown) -> (),
	reverse: ((playback: Playback, context: unknown) -> ())?,
}

type Sample = {
	startTime: number?,
	endTime: number?,
	run: (playback: Playback, sample: SampleInfo, context: unknown) -> (),
}

type Definition = {
	duration: number,
	loop: boolean?,
	events: { Event }?,
	samples: { Sample }?,
	onPlay: ((playback: Playback, context: unknown) -> ())?,
	onAddress: ((playback: Playback, info: AddressInfo, context: unknown) -> ())?,
	onLoop: ((playback: Playback, change: unknown, context: unknown) -> ())?,
}

type Sequence = {
	getDuration: (self: Sequence) -> number,
	isLooping: (self: Sequence) -> boolean,
}

type Builder = {
	duration: (self: Builder, seconds: number) -> Builder,
	loop: (self: Builder, enabled: boolean?) -> Builder,
	event: (self: Builder, event: Event) -> Builder,
	sample: (self: Builder, sample: Sample) -> Builder,
	onPlay: (self: Builder, callback: (playback: Playback, context: unknown) -> ()) -> Builder,
	onAddress: (self: Builder, callback: (playback: Playback, info: AddressInfo, context: unknown) -> ()) -> Builder,
	onLoop: (self: Builder, callback: (playback: Playback, change: unknown, context: unknown) -> ()) -> Builder,
	compile: (self: Builder) -> Sequence,
}

type PulseApi = {
	sequence: (definition: Definition) -> Sequence,
	builder: () -> Builder,
	playback: (
		sequence: Sequence,
		context: unknown,
		options: {
			playbackSpeed: number?,
			position: { timePosition: number, loopIndex: number? }?,
			initialMode: AddressMode?,
		}?
	) -> Playback,
}

type TransformHandle = {
	requireModule: (relativePath: string) -> unknown,
	cleanup: () -> (),
}

type TransformModule = {
	write: (options: { packageRoot: string, tempDir: string }) -> TransformHandle,
}

local Harness = (requireUnknown("../lib/testHarness") :: unknown) :: HarnessApi
local Transform = (requireUnknown("../lib/luneRequireTransform") :: unknown) :: TransformModule
local transformed = Transform.write({
	packageRoot = "src",
	tempDir = ".lune-pulse-core-tests",
})
local Pulse = (transformed.requireModule("init.luau") :: unknown) :: PulseApi
transformed.cleanup()

local function createPlayback(
	definition: Definition,
	options: {
		playbackSpeed: number?,
		position: { timePosition: number, loopIndex: number? }?,
		initialMode: AddressMode?,
	}?
): Playback
	return Pulse.playback(Pulse.sequence(definition), nil, options)
end

local function timeSample(position: number, rate: number?): TimeSample
	return {
		position = position,
		rate = rate or 1,
	}
end

Harness.test("core compiler freezes declarations and exposes no sequence address policy", function()
	local instant = Pulse.sequence({ duration = 0 })
	Harness.assertEqual(instant:getDuration(), 0)
	Harness.assertFalse(instant:isLooping())
	Harness.assertThrows(function()
		Pulse.sequence({ duration = 0, loop = true })
	end, "looping sequences require duration greater than zero")
	Harness.assertThrows(function()
		Pulse.sequence({
			duration = 1,
			samples = {
				{ startTime = 0.5, endTime = 0.5, run = function() end },
			},
		})
	end, "sample #1 interval")

	local event: Event = { time = 0.25, run = function() end }
	local sequence = Pulse.builder():duration(1):event(event):sample({ run = function() end }):compile()
	event.time = 0.75
	Harness.assertEqual(sequence:getDuration(), 1)
	local sequenceFields = (sequence :: unknown) :: { [string]: unknown }
	local builderFields = (Pulse.builder() :: unknown) :: { [string]: unknown }
	Harness.assertEqual(sequenceFields.getAddressPolicy, nil)
	Harness.assertEqual(builderFields.addressPolicy, nil)
	Harness.assertEqual(builderFields.update, nil)
end)

Harness.test("raw playback uses absolute source anchors without multiplying position delta by rate", function()
	local observed: { SampleInfo } = {}
	local playback = createPlayback({
		duration = 10,
		samples = {
			{
				run = function(_playback, sample)
					table.insert(observed, sample)
				end,
			},
		},
	}, {
		playbackSpeed = 2,
		position = { timePosition = 0.25 },
	})
	playback:play({ position = 100, rate = 3 })
	Harness.assertNear(playback:getPosition().timePosition, 0.25)
	Harness.assertEqual(#observed, 1)
	Harness.assertNear(observed[1].rate, 6)
	playback:evaluate({ position = 100.5, rate = 7 })
	Harness.assertNear(playback:getPosition().timePosition, 1.25)
	Harness.assertEqual(#observed, 2)
	Harness.assertNear(observed[2].position.timePosition, 1.25)
	Harness.assertNear(observed[2].rate, 14)
end)

Harness.test("a large evaluation traverses every event and samples final state once", function()
	local order: { string } = {}
	local samples: { number } = {}
	local playback = createPlayback({
		duration = 2,
		events = {
			{
				time = 0.25,
				run = function()
					table.insert(order, "a")
				end,
			},
			{
				time = 0.5,
				run = function()
					table.insert(order, "b")
				end,
			},
			{
				time = 0.75,
				run = function()
					table.insert(order, "c")
				end,
			},
		},
		samples = {
			{
				startTime = 0,
				endTime = 2,
				run = function(_playback, sample)
					table.insert(samples, sample.position.timePosition)
				end,
			},
		},
	})
	playback:play(timeSample(0))
	order = {}
	samples = {}
	playback:evaluate(timeSample(1))
	Harness.assertArrayEqual(order, { "a", "b", "c" })
	Harness.assertArrayEqual(samples, { 1 })
end)

Harness.test("samples use direction-independent start-inclusive end-exclusive intervals", function()
	local positions: { number } = {}
	local playback = createPlayback({
		duration = 1,
		samples = {
			{
				startTime = 0.2,
				endTime = 0.8,
				run = function(_playback, sample)
					table.insert(positions, sample.position.timePosition)
				end,
			},
		},
	}, {
		position = { timePosition = 0.2 },
	})
	playback:play(timeSample(10))
	playback:seek({ timePosition = 0.8 }, "skip")
	Harness.assertArrayEqual(positions, { 0.2 })
	playback:seek({ timePosition = 0.2 }, "skip")
	Harness.assertArrayEqual(positions, { 0.2, 0.2 })
end)

Harness.test("equal-coordinate evaluation samples once without duplicating discrete events", function()
	local events = 0
	local samples = 0
	local playback = createPlayback({
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function()
					events += 1
				end,
			},
		},
		samples = {
			{
				run = function()
					samples += 1
				end,
			},
		},
	})
	playback:play(timeSample(0))
	playback:evaluate(timeSample(0.5))
	playback:evaluate(timeSample(0.5))
	Harness.assertEqual(events, 1)
	Harness.assertEqual(samples, 3)
end)

Harness.test("multi-loop forward and backward evaluation preserves exact loop identity", function()
	local forwardLoops = 0
	local backwardLoops = 0
	local runs: { string } = {}
	local playback = createPlayback({
		duration = 1,
		loop = true,
		events = {
			{
				time = 0.25,
				run = function(control)
					table.insert(runs, `+{control:getPosition().loopIndex}`)
				end,
				reverse = function(control)
					table.insert(runs, `-{control:getPosition().loopIndex}`)
				end,
			},
		},
		onLoop = function(_playback, rawChange)
			local change = rawChange :: { direction: "forward" | "backward" }
			if change.direction == "forward" then
				forwardLoops += 1
			else
				backwardLoops += 1
			end
		end,
	})
	playback:play(timeSample(0))
	playback:evaluate(timeSample(3))
	local boundary = playback:getPosition()
	Harness.assertEqual(boundary.timePosition, 0)
	Harness.assertEqual(boundary.loopIndex, 3)
	Harness.assertEqual(boundary.unwrappedTimePosition, 3)
	Harness.assertEqual(forwardLoops, 3)
	playback:evaluate({ position = 0.2, rate = -1 })
	Harness.assertEqual(backwardLoops, 3)
	Harness.assertEqual(playback:getPosition().loopIndex, 0)
	Harness.assertNear(playback:getPosition().timePosition, 0.2)
	Harness.assertArrayEqual(runs, { "+0", "+1", "+2", "-2", "-1", "-0" })
end)

Harness.test("explicit loop addresses preserve both sides of one unwrapped boundary", function()
	local sequence = Pulse.sequence({ duration = 1, loop = true })
	local playback = Pulse.playback(sequence, nil, { initialMode = "skip" })
	playback:play(timeSample(0))

	playback:seek({ timePosition = 1, loopIndex = 2 }, "skip")
	local durationSide = playback:getPosition()
	Harness.assertEqual(durationSide.timePosition, 1)
	Harness.assertEqual(durationSide.loopIndex, 2)
	Harness.assertEqual(durationSide.unwrappedTimePosition, 3)

	playback:seek({ timePosition = 0, loopIndex = 3 }, "skip")
	local zeroSide = playback:getPosition()
	Harness.assertEqual(zeroSide.timePosition, 0)
	Harness.assertEqual(zeroSide.loopIndex, 3)
	Harness.assertEqual(zeroSide.unwrappedTimePosition, 3)
end)

Harness.test("exact duration addresses preserve identity until future loop traversal", function()
	local order: { string } = {}
	local sequence = Pulse.sequence({
		duration = 1,
		loop = true,
		events = {
			{
				time = 0,
				run = function(control)
					table.insert(order, `zero@{control:getPosition().loopIndex}`)
				end,
			},
			{
				time = 1,
				run = function(control)
					table.insert(order, `duration@{control:getPosition().loopIndex}`)
				end,
			},
		},
		onLoop = function(control)
			table.insert(order, `loop@{control:getPosition().loopIndex}`)
		end,
	})
	local playback = Pulse.playback(sequence, nil, { initialMode = "skip" })
	playback:play(timeSample(0))

	playback:seek({ timePosition = 1, loopIndex = 2 }, "reconstruct")
	Harness.assertArrayEqual(order, { "zero@2", "duration@2" })
	Harness.assertEqual(playback:getPosition().timePosition, 1)
	Harness.assertEqual(playback:getPosition().loopIndex, 2)

	playback:evaluate(timeSample(0.1))
	Harness.assertArrayEqual(order, { "zero@2", "duration@2", "loop@2", "zero@3" })
	Harness.assertNear(playback:getPosition().timePosition, 0.1)
	Harness.assertEqual(playback:getPosition().loopIndex, 3)

	order = {}
	playback:seek({ timePosition = 1, loopIndex = 4 }, "skip")
	Harness.assertEqual(playback:getPosition().timePosition, 1)
	Harness.assertEqual(playback:getPosition().loopIndex, 4)
	playback:evaluate(timeSample(0.2))
	Harness.assertArrayEqual(order, { "loop@4", "zero@5" })
	Harness.assertNear(playback:getPosition().timePosition, 0.1)
	Harness.assertEqual(playback:getPosition().loopIndex, 5)
end)

Harness.test("reverse traversal uses inverse time and authored ordering", function()
	local order: { string } = {}
	local function event(time: number, name: string): Event
		return {
			time = time,
			run = function()
				table.insert(order, name)
			end,
			reverse = function()
				table.insert(order, "-" .. name)
			end,
		}
	end
	local playback = createPlayback({
		duration = 2,
		events = { event(0.5, "a"), event(0.5, "b"), event(1, "c") },
	})
	playback:play(timeSample(0))
	playback:evaluate(timeSample(1))
	playback:evaluate({ position = 0, rate = -1 })
	Harness.assertArrayEqual(order, { "a", "b", "c", "-c", "-b", "-a" })
end)

Harness.test("initial reconstruct and skip are invocation-specific and order address before sample", function()
	local function definition(order: { string }): Definition
		return {
			duration = 1,
			events = {
				{
					time = 0.25,
					run = function()
						table.insert(order, "event")
					end,
				},
			},
			samples = {
				{
					run = function()
						table.insert(order, "sample")
					end,
				},
			},
			onPlay = function()
				table.insert(order, "play")
			end,
			onAddress = function(_playback, info)
				table.insert(order, `{info.cause}:{info.mode}`)
			end,
		}
	end
	local reconstructOrder: { string } = {}
	local reconstruct = createPlayback(definition(reconstructOrder), {
		position = { timePosition = 0.5 },
		initialMode = "reconstruct",
	})
	reconstruct:play(timeSample(0))
	Harness.assertArrayEqual(reconstructOrder, { "play", "event", "initial:reconstruct", "sample" })

	local skipOrder: { string } = {}
	local skip = createPlayback(definition(skipOrder), {
		position = { timePosition = 0.5 },
		initialMode = "skip",
	})
	skip:play(timeSample(0))
	Harness.assertArrayEqual(skipOrder, { "play", "initial:skip", "sample" })
end)

Harness.test("one sequence supports skip and reconstruct on different calls and playbacks", function()
	local runs = 0
	local addresses: { string } = {}
	local sequence = Pulse.sequence({
		duration = 1,
		events = {
			{
				time = 0.25,
				run = function()
					runs += 1
				end,
			},
			{
				time = 0.5,
				run = function()
					runs += 1
				end,
			},
		},
		onAddress = function(_playback, info)
			table.insert(addresses, info.mode)
		end,
	})
	local first = Pulse.playback(sequence, nil)
	local second = Pulse.playback(sequence, nil)
	first:play(timeSample(0))
	second:play(timeSample(0))
	Harness.assertTrue(first:seek({ timePosition = 0.75 }, "skip"))
	Harness.assertEqual(runs, 0)
	Harness.assertTrue(second:seek({ timePosition = 0.75 }, "reconstruct"))
	Harness.assertEqual(runs, 2)
	Harness.assertTrue(first:seek({ timePosition = 0.5 }, "reconstruct"))
	Harness.assertEqual(runs, 4)
	Harness.assertArrayEqual(addresses, {
		"reconstruct",
		"reconstruct",
		"skip",
		"reconstruct",
		"reconstruct",
	})
end)

Harness.test("pause resume and local speed mutate at the accepted coordinate", function()
	local playback = createPlayback({ duration = 5 })
	playback:play(timeSample(10))
	playback:evaluate(timeSample(11))
	Harness.assertNear(playback:getPosition().timePosition, 1)
	playback:pause()
	Harness.assertFalse(playback:evaluate(timeSample(20)))
	Harness.assertNear(playback:getPosition().timePosition, 1)
	playback:resume()
	playback:evaluate(timeSample(20))
	Harness.assertNear(playback:getPosition().timePosition, 1)
	playback:setPlaybackSpeed(2)
	playback:evaluate(timeSample(20.5))
	Harness.assertNear(playback:getPosition().timePosition, 2)
	playback:setPlaybackSpeed(-1)
	playback:evaluate({ position = 21, rate = -1 })
	Harness.assertNear(playback:getPosition().timePosition, 1.5)
end)

Harness.test("nonterminal reentrant mutation waits for the current occurrence", function()
	local order: { string } = {}
	local playback = createPlayback({
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function(control)
					table.insert(order, "first")
					control:seek({ timePosition = 0.8 }, "skip")
					control:pause()
				end,
			},
			{
				time = 0.5,
				run = function()
					table.insert(order, "second")
				end,
			},
		},
		onAddress = function(_playback, info)
			if info.cause == "seek" then
				table.insert(order, "address")
			end
		end,
	})
	playback:play(timeSample(0))
	playback:evaluate(timeSample(0.5))
	Harness.assertArrayEqual(order, { "first", "second", "address" })
	Harness.assertNear(playback:getPosition().timePosition, 0.8)
	Harness.assertEqual(playback:getStatus(), "paused")
end)

Harness.test("terminal callback mutation interrupts equal-time work", function()
	local order: { string } = {}
	local playback = createPlayback({
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function(control)
					table.insert(order, "first")
					control:cancel("inside")
				end,
			},
			{
				time = 0.5,
				run = function()
					table.insert(order, "second")
				end,
			},
		},
	})
	playback:play(timeSample(0))
	playback:evaluate(timeSample(0.5))
	Harness.assertArrayEqual(order, { "first" })
	Harness.assertEqual((playback:getCompletion() :: Completion).reason, "inside")
end)

Harness.test("callback failure completes once and completion is immutable", function()
	local playback = createPlayback({
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function()
					error("boom")
				end,
			},
		},
	})
	local ended = 0
	local observedReason = ""
	playback:onEnded(function(completion)
		ended += 1
		Harness.assertThrows(function()
			completion.reason = "changed"
		end)
	end)
	playback:onEnded(function(completion)
		observedReason = completion.reason or ""
	end)
	playback:play(timeSample(0))
	playback:evaluate(timeSample(0.5))
	Harness.assertEqual(ended, 1)
	Harness.assertEqual(observedReason, "callbackFailed")
	Harness.assertEqual((playback:getCompletion() :: Completion).status, "failed")
end)

Harness.test("reconstruct replaces cleanup generations and terminal cleanup is LIFO", function()
	local order: { string } = {}
	local playback = createPlayback({
		duration = 1,
		onPlay = function(control)
			control:addCleanup(function()
				table.insert(order, "first")
			end)
			control:addCleanup(function()
				table.insert(order, "second")
			end)
		end,
	})
	playback:play(timeSample(0))
	playback:seek({ timePosition = 0.5 }, "reconstruct")
	Harness.assertArrayEqual(order, { "second", "first" })
	playback:cancel()
	Harness.assertArrayEqual(order, { "second", "first", "second", "first" })
end)

Harness.test("zero-duration behavior distinguishes initial reconstruction from skip", function()
	local reconstructedEvents = 0
	local reconstruct = createPlayback({
		duration = 0,
		events = {
			{
				time = 0,
				run = function()
					reconstructedEvents += 1
				end,
			},
		},
	})
	reconstruct:play(timeSample(0, 0))
	Harness.assertEqual(reconstructedEvents, 1)
	Harness.assertEqual(reconstruct:getStatus(), "completed")

	local skippedEvents = 0
	local skip = createPlayback({
		duration = 0,
		events = {
			{
				time = 0,
				run = function()
					skippedEvents += 1
				end,
			},
		},
	}, {
		initialMode = "skip",
	})
	skip:play(timeSample(0, 0))
	Harness.assertEqual(skippedEvents, 0)
	Harness.assertEqual(skip:getStatus(), "completed")
end)

Harness.test("numeric and catch-up limits fail explicitly", function()
	local events: { Event } = {}
	for _ = 1, 4_100 do
		table.insert(events, {
			time = 0.5,
			run = function() end,
		})
	end
	local playback = createPlayback({ duration = 1, events = events })
	playback:play(timeSample(0))
	playback:evaluate(timeSample(0.5))
	Harness.assertEqual((playback:getCompletion() :: Completion).status, "failed")
	Harness.assertEqual((playback:getCompletion() :: Completion).reason, "catchUpLimitExceeded")

	local finite = createPlayback({ duration = 1 })
	Harness.assertThrows(function()
		finite:play({ position = math.huge, rate = 1 })
	end, "position must be finite")
	local looping = Pulse.sequence({ duration = 1, loop = true })
	Harness.assertThrows(function()
		Pulse.playback(looping, nil, {
			position = { timePosition = 0.5, loopIndex = 9_007_199_254_740_991 },
		})
	end, "exact")
end)

Harness.test("typed per-play context reaches every authored callback family", function()
	local context = { actorId = 17 }
	local seen = { play = 0, address = 0, event = 0, reverse = 0, sample = 0, loop = 0 }
	local playback = Pulse.playback(
		Pulse.sequence({
			duration = 1,
			loop = true,
			events = {
				{
					time = 0.25,
					run = function(_playback, received)
						Harness.assertEqual(received, context)
						seen.event += 1
					end,
					reverse = function(_playback, received)
						Harness.assertEqual(received, context)
						seen.reverse += 1
					end,
				},
			},
			samples = {
				{
					run = function(_playback, _sample, received)
						Harness.assertEqual(received, context)
						seen.sample += 1
					end,
				},
			},
			onPlay = function(_playback, received)
				Harness.assertEqual(received, context)
				seen.play += 1
			end,
			onAddress = function(_playback, _info, received)
				Harness.assertEqual(received, context)
				seen.address += 1
			end,
			onLoop = function(_playback, _change, received)
				Harness.assertEqual(received, context)
				seen.loop += 1
			end,
		}),
		context
	)
	playback:play(timeSample(0))
	playback:evaluate(timeSample(1.25))
	playback:evaluate({ position = 0, rate = -1 })
	Harness.assertEqual(seen.play, 1)
	Harness.assertEqual(seen.address, 1)
	Harness.assertTrue(seen.event > 0)
	Harness.assertTrue(seen.reverse > 0)
	Harness.assertTrue(seen.sample > 0)
	Harness.assertTrue(seen.loop > 0)
end)
