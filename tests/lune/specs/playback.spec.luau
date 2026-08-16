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

type DirectionToken = {
	name: "forward" | "backward",
}

type FakeClock = {
	directions: {
		forward: DirectionToken,
		backward: DirectionToken,
	},
	read: (self: FakeClock) -> {
		timePosition: number,
		rate: number,
		revision: number,
	},
	stepRootTo: (self: FakeClock, rootTime: number, phase: string) -> (),
	advanceRootTo: (self: FakeClock, rootTime: number) -> (),
	evaluatePhase: (self: FakeClock, phase: string) -> (),
	setRate: (self: FakeClock, rate: number) -> (),
	jumpTo: (self: FakeClock, timePosition: number) -> (),
	bindToChanged: (self: FakeClock, callback: (change: unknown) -> (), runInitially: boolean?) -> () -> (),
	destroy: (self: FakeClock) -> (),
	setBeforeNextReached: (self: FakeClock, callback: (() -> ())?) -> (),
	getTaskCount: (self: FakeClock) -> number,
	getChangedBindingCount: (self: FakeClock) -> number,
	getPhaseBindingCount: (self: FakeClock) -> number,
	getScheduleCount: (self: FakeClock) -> number,
	getRescheduleCount: (self: FakeClock) -> number,
	getCancelCount: (self: FakeClock) -> number,
	getLastTaskId: (self: FakeClock) -> number?,
}

type FakeClockModule = {
	new: (options: {
		rootTime: number?,
		timePosition: number?,
		rate: number?,
	}?) -> FakeClock,
}

type Completion = {
	status: "completed" | "cancelled" | "destroyed" | "failed",
	reason: string?,
}

type PlaybackPosition = {
	timePosition: number,
	loopIndex: number,
	unwrappedTimePosition: number,
}

type Playback = {
	play: (self: Playback) -> Playback,
	pause: (self: Playback) -> (),
	resume: (self: Playback) -> (),
	setPlaybackSpeed: (self: Playback, speed: number) -> (),
	getPlaybackSpeed: (self: Playback) -> number,
	seek: (self: Playback, address: { timePosition: number, loopIndex: number? }) -> boolean,
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
	run: (playback: Playback) -> (),
	reverse: ((playback: Playback) -> ())?,
}

type Update = {
	startTime: number?,
	endTime: number?,
	run: (playback: Playback, dt: number, timePosition: number) -> (),
}

type Definition = {
	duration: number,
	loop: boolean?,
	addressPolicy: ("skip" | "rebuild" | "cancel")?,
	events: { Event }?,
	updates: { Update }?,
	onPlay: ((playback: Playback) -> ())?,
	onLoop: ((playback: Playback, change: unknown) -> ())?,
}

type Sequence = {
	getDuration: (self: Sequence) -> number,
	isLooping: (self: Sequence) -> boolean,
	getAddressPolicy: (self: Sequence) -> "skip" | "rebuild" | "cancel",
}

type Builder = {
	duration: (self: Builder, seconds: number) -> Builder,
	loop: (self: Builder, enabled: boolean?) -> Builder,
	addressPolicy: (self: Builder, policy: "skip" | "rebuild" | "cancel") -> Builder,
	event: (self: Builder, event: Event) -> Builder,
	update: (self: Builder, update: Update) -> Builder,
	onPlay: (self: Builder, callback: (playback: Playback) -> ()) -> Builder,
	compile: (self: Builder) -> Sequence,
}

type TemporalAdapter = {
	destroy: (self: TemporalAdapter) -> (),
	isDestroyed: (self: TemporalAdapter) -> boolean,
}

type PulseApi = {
	sequence: (definition: Definition) -> Sequence,
	builder: () -> Builder,
	temporalAdapter: (clock: unknown, phase: unknown, directions: unknown) -> TemporalAdapter,
	playback: (
		sequence: Sequence,
		adapter: TemporalAdapter,
		options: {
			playbackSpeed: number?,
			position: { timePosition: number, loopIndex: number? }?,
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
local FakeClock = (requireUnknown("../lib/fakeClock") :: unknown) :: FakeClockModule
local Transform = (requireUnknown("../lib/luneRequireTransform") :: unknown) :: TransformModule
local transformed = Transform.write({
	packageRoot = "src",
	tempDir = ".lune-pulse-tests",
})
local Pulse = (transformed.requireModule("init.luau") :: unknown) :: PulseApi
transformed.cleanup()

local PHASE = "simulation"

local function adapterFor(clock: FakeClock): TemporalAdapter
	return Pulse.temporalAdapter(clock, PHASE, clock.directions)
end

local function createPlayback(
	clock: FakeClock,
	definition: Definition,
	options: {
		playbackSpeed: number?,
		position: { timePosition: number, loopIndex: number? }?,
	}?
): (Playback, TemporalAdapter)
	local adapter = adapterFor(clock)
	return Pulse.playback(Pulse.sequence(definition), adapter, options), adapter
end

Harness.test("compiler validates, freezes, and builder keeps fluent temporal names", function()
	Harness.assertThrows(function()
		Pulse.sequence({ duration = 0 })
	end, "greater than zero")
	Harness.assertThrows(function()
		Pulse.sequence({
			duration = 1,
			events = {
				{ time = 2, run = function() end },
			},
		})
	end, "within the sequence duration")
	local event: Event = {
		time = 0.5,
		run = function() end,
	}
	local sequence = Pulse.builder():duration(1):addressPolicy("rebuild"):event(event):compile()
	event.time = 0.75
	Harness.assertEqual(sequence:getDuration(), 1)
	Harness.assertEqual(sequence:getAddressPolicy(), "rebuild")
	Harness.assertFalse(sequence:isLooping())

	local loopClock = FakeClock.new()
	local loopAdapter = adapterFor(loopClock)
	local loopSequence = Pulse.sequence({ duration = 1, loop = true })
	Harness.assertThrows(function()
		Pulse.playback(loopSequence, loopAdapter, {
			position = {
				timePosition = 0.5,
				loopIndex = 9_007_199_254_740_991,
			},
		})
	end, "exact")
	loopAdapter:destroy()
end)

Harness.test("inert creation is observable before synchronous completion", function()
	local clock = FakeClock.new()
	local playback = createPlayback(clock, { duration = 1 }, {
		position = { timePosition = 1 },
	})
	local ended = 0
	playback:onEnded(function(completion)
		ended += 1
		Harness.assertEqual(completion.status, "completed")
	end)
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
	playback:play()
	Harness.assertEqual(ended, 1)
	Harness.assertEqual(playback:getStatus(), "completed")
	local late = 0
	playback:onEnded(function()
		late += 1
	end)
	Harness.assertEqual(late, 1)

	local reverseClock = FakeClock.new()
	local reverse = createPlayback(reverseClock, { duration = 1 }, {
		playbackSpeed = -1,
	})
	local reverseEnded = 0
	reverse:onEnded(function()
		reverseEnded += 1
	end)
	reverse:play()
	Harness.assertEqual(reverseEnded, 1)
	Harness.assertEqual(reverse:getStatus(), "completed")

	local upperClock = FakeClock.new()
	local fromUpper = createPlayback(upperClock, { duration = 1 }, {
		playbackSpeed = -1,
		position = { timePosition = 1 },
	})
	fromUpper:play()
	Harness.assertEqual(fromUpper:getStatus(), "playing")
	upperClock:stepRootTo(1, PHASE)
	Harness.assertEqual(fromUpper:getStatus(), "completed")
end)

Harness.test("event-only playback owns one deadline and no phase binding", function()
	local clock = FakeClock.new()
	local hits = 0
	local playback = createPlayback(clock, {
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function()
					hits += 1
				end,
			},
		},
	})
	playback:play()
	Harness.assertEqual(clock:getChangedBindingCount(), 1)
	Harness.assertEqual(clock:getTaskCount(), 1)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	clock:stepRootTo(0.5, PHASE)
	Harness.assertEqual(hits, 1)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)

	local liveClock = FakeClock.new()
	local liveHits = 0
	local live = createPlayback(liveClock, {
		duration = 10,
		events = {
			{
				time = 5,
				run = function()
					liveHits += 1
				end,
			},
		},
	})
	live:play()
	liveClock:advanceRootTo(2)
	Harness.assertNear(live:getPosition().timePosition, 2)
	Harness.assertEqual(liveHits, 0)
	live:cancel()
end)

Harness.test("deadline ownership catches up when authored work advances the provider", function()
	local clock = FakeClock.new()
	local order: { string } = {}
	local playback = createPlayback(clock, {
		duration = 2,
		events = {
			{
				time = 0.5,
				run = function()
					table.insert(order, "first")
					clock:advanceRootTo(1.5)
				end,
			},
			{
				time = 1,
				run = function()
					table.insert(order, "second")
				end,
			},
		},
	})
	playback:play()
	clock:stepRootTo(0.5, PHASE)
	Harness.assertArrayEqual(order, { "first", "second" })
	Harness.assertEqual(clock:getTaskCount(), 1)
	clock:stepRootTo(2, PHASE)
	Harness.assertEqual(playback:getStatus(), "completed")
end)

Harness.test("update intervals bind lazily, receive timeline delta, and release", function()
	local clock = FakeClock.new()
	local deltas: { number } = {}
	local playback = createPlayback(clock, {
		duration = 1,
		updates = {
			{
				startTime = 0.2,
				endTime = 0.8,
				run = function(_playback, dt)
					table.insert(deltas, dt)
				end,
			},
		},
	})
	playback:play()
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	clock:stepRootTo(0.2, PHASE)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	clock:stepRootTo(0.5, PHASE)
	Harness.assertNear(deltas[#deltas], 0.3)
	clock:stepRootTo(0.8, PHASE)
	Harness.assertEqual(#deltas, 3)
	Harness.assertNear(deltas[1], 0)
	Harness.assertNear(deltas[2], 0.3)
	Harness.assertNear(deltas[3], 0.3)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)

	local pauseClock = FakeClock.new()
	local pauseDelta = 0
	local pausing = createPlayback(pauseClock, {
		duration = 1,
		updates = {
			{
				startTime = 0,
				endTime = 1,
				run = function(_playback, dt)
					pauseDelta += dt
				end,
			},
		},
	})
	pausing:play()
	pauseClock:stepRootTo(0.2, PHASE)
	pauseClock:advanceRootTo(0.5)
	pausing:pause()
	Harness.assertNear(pauseDelta, 0.5)
	Harness.assertEqual(pauseClock:getPhaseBindingCount(), 0)
end)

Harness.test("two updating playbacks share exactly one adapter phase binding", function()
	local clock = FakeClock.new()
	local adapter = adapterFor(clock)
	local sequence = Pulse.sequence({
		duration = 1,
		updates = {
			{ startTime = 0, endTime = 1, run = function() end },
		},
	})
	local first = Pulse.playback(sequence, adapter)
	local second = Pulse.playback(sequence, adapter)
	first:play()
	second:play()
	Harness.assertEqual(clock:getChangedBindingCount(), 1)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	first:cancel()
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	second:cancel()
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
end)

Harness.test("shared fanout keeps not-yet-notified playback inspection serialized", function()
	local clock = FakeClock.new()
	local adapter = adapterFor(clock)
	local second: Playback
	local observed = -1
	local first = Pulse.playback(
		Pulse.sequence({
			duration = 2,
			events = {
				{
					time = 0.25,
					run = function()
						observed = second:getPosition().timePosition
					end,
				},
			},
		}),
		adapter
	)
	second = Pulse.playback(Pulse.sequence({ duration = 2 }), adapter)
	first:play()
	second:play()
	clock:advanceRootTo(0.5)
	clock:setRate(2)
	Harness.assertNear(observed, 0)
	Harness.assertNear(second:getPosition().timePosition, 0.5)
	first:cancel()
	second:cancel()
end)

Harness.test("shared adapter serializes reentrant clock changes for every playback", function()
	local clock = FakeClock.new()
	local adapter = adapterFor(clock)
	local order: { string } = {}
	local reverseHits = 0
	local changedDirection = false
	local first = Pulse.playback(
		Pulse.sequence({
			duration = 2,
			events = {
				{
					time = 0.5,
					run = function()
						table.insert(order, "first")
						if not changedDirection then
							changedDirection = true
							clock:setRate(-1)
						end
					end,
					reverse = function()
						reverseHits += 1
					end,
				},
			},
		}),
		adapter
	)
	local second = Pulse.playback(
		Pulse.sequence({
			duration = 2,
			events = {
				{
					time = 0.5,
					run = function()
						table.insert(order, "second")
					end,
					reverse = function()
						reverseHits += 1
					end,
				},
			},
		}),
		adapter
	)
	first:play()
	second:play()
	clock:advanceRootTo(0.75)
	clock:setRate(2)
	Harness.assertArrayEqual(order, { "first", "second" })
	clock:stepRootTo(1, PHASE)
	Harness.assertEqual(reverseHits, 2)

	local cycleClock = FakeClock.new()
	local cycleAdapter = adapterFor(cycleClock)
	local armed = false
	local cycle = Pulse.playback(
		Pulse.sequence({
			duration = 1,
			events = {
				{
					time = 0.5,
					run = function()
						if armed then
							cycleClock:setRate(-1)
						end
					end,
					reverse = function()
						if armed then
							cycleClock:setRate(1)
						end
					end,
				},
			},
		}),
		cycleAdapter
	)
	cycle:play()
	cycleClock:stepRootTo(0.5, PHASE)
	armed = true
	cycleClock:setRate(-1)
	Harness.assertTrue(cycleAdapter:isDestroyed())
	Harness.assertEqual(cycle:getCompletion().status, "failed")
	Harness.assertEqual(cycle:getCompletion().reason, "notificationLimitExceeded")
	Harness.assertEqual(cycleClock:getTaskCount(), 0)
	Harness.assertEqual(cycleClock:getChangedBindingCount(), 0)
end)

Harness.test("shared phase fanout completes before callback clock mutation", function()
	local clock = FakeClock.new()
	local adapter = adapterFor(clock)
	local changedDirection = false
	local firstSequence = Pulse.sequence({
		duration = 2,
		updates = {
			{
				startTime = 0,
				endTime = 2,
				run = function()
					if not changedDirection then
						changedDirection = true
						clock:setRate(-1)
					end
				end,
			},
		},
	})
	local secondSequence = Pulse.sequence({
		duration = 2,
		updates = {
			{ startTime = 0, endTime = 2, run = function() end },
		},
	})
	local first = Pulse.playback(firstSequence, adapter)
	local second = Pulse.playback(secondSequence, adapter)
	first:play()
	second:play()
	clock:stepRootTo(0.25, PHASE)
	clock:stepRootTo(0.5, PHASE)
	Harness.assertEqual(first:getStatus(), "completed")
	Harness.assertEqual(second:getStatus(), "completed")
end)

Harness.test("clock changes and callback mutations preserve causal order", function()
	local jumpFirstClock = FakeClock.new()
	local jumpFirstHits = 0
	local jumpFirstMutated = false
	local jumpFirst = createPlayback(jumpFirstClock, {
		duration = 2,
		addressPolicy = "skip",
		events = {
			{
				time = 1,
				run = function()
					jumpFirstHits += 1
				end,
			},
		},
		updates = {
			{
				startTime = 0,
				endTime = 2,
				run = function(context, dt)
					if dt > 0 and not jumpFirstMutated then
						jumpFirstMutated = true
						jumpFirstClock:jumpTo(1.5)
						context:pause()
					end
				end,
			},
		},
	})
	jumpFirst:play()
	jumpFirstClock:stepRootTo(0.5, PHASE)
	Harness.assertEqual(jumpFirstHits, 0)
	Harness.assertEqual(jumpFirst:getStatus(), "paused")
	Harness.assertNear(jumpFirst:getPosition().timePosition, 1.5)

	local pauseFirstClock = FakeClock.new()
	local pauseFirstHits = 0
	local pauseFirstMutated = false
	local pauseFirst = createPlayback(pauseFirstClock, {
		duration = 2,
		addressPolicy = "skip",
		events = {
			{
				time = 1,
				run = function()
					pauseFirstHits += 1
				end,
			},
		},
		updates = {
			{
				startTime = 0,
				endTime = 2,
				run = function(context, dt)
					if dt > 0 and not pauseFirstMutated then
						pauseFirstMutated = true
						context:pause()
						pauseFirstClock:jumpTo(1.5)
					end
				end,
			},
		},
	})
	pauseFirst:play()
	pauseFirstClock:stepRootTo(0.5, PHASE)
	Harness.assertEqual(pauseFirstHits, 0)
	Harness.assertEqual(pauseFirst:getStatus(), "paused")
	Harness.assertNear(pauseFirst:getPosition().timePosition, 0.5)
end)

Harness.test("different adapter identities do not share ownership implicitly", function()
	local clock = FakeClock.new()
	local definition: Definition = {
		duration = 1,
		updates = {
			{ startTime = 0, endTime = 1, run = function() end },
		},
	}
	local first = createPlayback(clock, definition)
	local second = createPlayback(clock, definition)
	first:play()
	second:play()
	Harness.assertEqual(clock:getChangedBindingCount(), 2)
	Harness.assertEqual(clock:getPhaseBindingCount(), 2)
end)

Harness.test("forward and equal-time ordering are authored-order stable", function()
	local clock = FakeClock.new()
	local order: { string } = {}
	local function event(time: number, name: string): Event
		return {
			time = time,
			run = function()
				table.insert(order, name)
			end,
		}
	end
	local playback = createPlayback(clock, {
		duration = 1,
		events = { event(0.5, "a"), event(0.5, "b"), event(1, "c") },
	})
	playback:play()
	clock:stepRootTo(1, PHASE)
	Harness.assertArrayEqual(order, { "a", "b", "c" })
end)

Harness.test("reverse callbacks use exact inverse time and authored order", function()
	local clock = FakeClock.new()
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
	local playback = createPlayback(clock, {
		duration = 2,
		events = { event(0.5, "a"), event(0.5, "b"), event(1, "c") },
	})
	playback:play()
	clock:stepRootTo(1, PHASE)
	clock:setRate(-1)
	clock:stepRootTo(1.6, PHASE)
	Harness.assertArrayEqual(order, { "a", "b", "c", "-c", "-b", "-a" })
end)

Harness.test("a late reached callback catches up every missed event", function()
	local clock = FakeClock.new()
	local order: { number } = {}
	local positions: { number } = {}
	local events: { Event } = {}
	for index = 1, 4 do
		table.insert(events, {
			time = index * 0.25,
			run = function(context)
				table.insert(order, index)
				table.insert(positions, context:getPosition().timePosition)
			end,
		})
	end
	local playback = createPlayback(clock, { duration = 2, events = events })
	playback:play()
	clock:advanceRootTo(1)
	clock:evaluatePhase(PHASE)
	Harness.assertArrayEqual(order, { 1, 2, 3, 4 })
	Harness.assertArrayEqual(positions, { 0.25, 0.5, 0.75, 1 })
end)

Harness.test("loop boundaries order end, loop, then next start", function()
	local clock = FakeClock.new()
	local order: { string } = {}
	local playback = createPlayback(clock, {
		duration = 1,
		loop = true,
		events = {
			{
				time = 0,
				run = function()
					table.insert(order, "start")
				end,
			},
			{
				time = 1,
				run = function()
					table.insert(order, "end")
				end,
			},
		},
		onLoop = function()
			table.insert(order, "loop")
		end,
	})
	playback:play()
	clock:stepRootTo(1, PHASE)
	Harness.assertArrayEqual(order, { "start", "end", "loop", "start" })

	local observerClock = FakeClock.new()
	local observerPlayback = createPlayback(observerClock, {
		duration = 1,
		loop = true,
	})
	local observedDirection = ""
	observerPlayback:onLooped(function(change)
		change.direction = "backward"
	end)
	observerPlayback:onLooped(function(change)
		observedDirection = change.direction
	end)
	observerPlayback:play()
	observerClock:stepRootTo(1, PHASE)
	Harness.assertEqual(observedDirection, "forward")
	observerPlayback:cancel()
end)

Harness.test("missed twenty-loop catch-up preserves authored boundaries forward and backward", function()
	local forwardClock = FakeClock.new()
	local forwardOrder: { string } = {}
	local forwardCoordinates: { number } = {}
	local reverseOrder: { string } = {}
	local forwardLoops = 0
	local reverseLoops = 0
	local function event(time: number, label: string): Event
		return {
			time = time,
			run = function(context)
				local position = context:getPosition()
				Harness.assertEqual(position.timePosition, time)
				table.insert(forwardOrder, `{label}@{position.loopIndex}`)
				table.insert(forwardCoordinates, position.unwrappedTimePosition)
			end,
			reverse = function(context)
				local position = context:getPosition()
				Harness.assertEqual(position.timePosition, time)
				table.insert(reverseOrder, `{label}@{position.loopIndex}`)
			end,
		}
	end
	local definition: Definition = {
		duration = 6,
		loop = true,
		events = {
			event(0.8, "a"),
			event(2.4, "b"),
			event(4.6, "c"),
		},
		onLoop = function(_context, rawChange)
			local change = rawChange :: {
				direction: "forward" | "backward",
			}
			if change.direction == "forward" then
				forwardLoops += 1
			else
				reverseLoops += 1
			end
		end,
	}
	local forward = createPlayback(forwardClock, definition)
	forward:play()
	forwardClock:advanceRootTo(120.8)
	forwardClock:evaluatePhase(PHASE)
	local expectedForward: { string } = {}
	for loopIndex = 0, 19 do
		table.insert(expectedForward, `a@{loopIndex}`)
		table.insert(expectedForward, `b@{loopIndex}`)
		table.insert(expectedForward, `c@{loopIndex}`)
	end
	table.insert(expectedForward, "a@20")
	Harness.assertArrayEqual(forwardOrder, expectedForward)
	Harness.assertEqual(forwardCoordinates[7], 12.8)
	Harness.assertEqual(forwardCoordinates[10], 18.8)
	Harness.assertEqual(forwardCoordinates[61], 120.8)
	Harness.assertEqual(forwardLoops, 20)
	Harness.assertEqual(forward:getPosition().timePosition, 0.8)
	Harness.assertEqual(forward:getPosition().loopIndex, 20)
	Harness.assertTrue(forward:isAlive())
	Harness.assertEqual(forwardClock:getTaskCount(), 1)
	Harness.assertEqual(forwardClock:getPhaseBindingCount(), 0)

	local reverseClock = FakeClock.new()
	local reverse = createPlayback(reverseClock, definition, {
		playbackSpeed = -1,
		position = { timePosition = 0, loopIndex = 20 },
	})
	reverse:play()
	reverseClock:advanceRootTo(119.2)
	reverseClock:evaluatePhase(PHASE)
	local expectedReverse: { string } = {}
	for loopIndex = 19, 0, -1 do
		table.insert(expectedReverse, `c@{loopIndex}`)
		table.insert(expectedReverse, `b@{loopIndex}`)
		table.insert(expectedReverse, `a@{loopIndex}`)
	end
	Harness.assertArrayEqual(reverseOrder, expectedReverse)
	Harness.assertEqual(reverseLoops, 20)
	Harness.assertNear(reverse:getPosition().timePosition, 0.8)
	Harness.assertEqual(reverse:getPosition().loopIndex, 0)
	Harness.assertTrue(reverse:isAlive())
	Harness.assertEqual(reverseClock:getTaskCount(), 1)
	Harness.assertEqual(reverseClock:getPhaseBindingCount(), 0)
end)

Harness.test("direction pivots apply exact event and loop boundaries once", function()
	local eventClock = FakeClock.new()
	local eventOrder: { string } = {}
	local eventPlayback = createPlayback(eventClock, {
		duration = 6,
		loop = true,
		events = {
			{
				time = 0.8,
				run = function(context)
					Harness.assertEqual(context:getPosition().timePosition, 0.8)
					table.insert(eventOrder, "forward")
				end,
				reverse = function(context)
					Harness.assertEqual(context:getPosition().timePosition, 0.8)
					table.insert(eventOrder, "backward")
				end,
			},
		},
	})
	eventPlayback:play()
	eventClock:stepRootTo(0.8, PHASE)
	eventClock:setRate(-1)
	eventClock:setRate(1)
	Harness.assertArrayEqual(eventOrder, { "forward", "backward", "forward" })
	Harness.assertEqual(eventPlayback:getPosition().timePosition, 0.8)
	Harness.assertEqual(eventClock:getTaskCount(), 1)

	local loopClock = FakeClock.new()
	local loopOrder: { string } = {}
	local loopPlayback = createPlayback(loopClock, {
		duration = 6,
		loop = true,
		events = {
			{
				time = 0,
				run = function(context)
					Harness.assertEqual(context:getPosition().timePosition, 0)
					table.insert(loopOrder, "zeroForward")
				end,
				reverse = function(context)
					Harness.assertEqual(context:getPosition().timePosition, 0)
					table.insert(loopOrder, "zeroBackward")
				end,
			},
			{
				time = 6,
				run = function(context)
					Harness.assertEqual(context:getPosition().timePosition, 6)
					table.insert(loopOrder, "durationForward")
				end,
				reverse = function(context)
					Harness.assertEqual(context:getPosition().timePosition, 6)
					table.insert(loopOrder, "durationBackward")
				end,
			},
		},
		onLoop = function(context, rawChange)
			local change = rawChange :: {
				direction: "forward" | "backward",
			}
			if change.direction == "forward" then
				Harness.assertEqual(context:getPosition().timePosition, 6)
				Harness.assertEqual(context:getPosition().loopIndex, 0)
			else
				Harness.assertEqual(context:getPosition().timePosition, 0)
				Harness.assertEqual(context:getPosition().loopIndex, 1)
			end
			table.insert(loopOrder, `authored{change.direction}`)
		end,
	})
	loopPlayback:onLooped(function(change)
		table.insert(loopOrder, `observed{change.direction}`)
	end)
	loopPlayback:play()
	loopClock:stepRootTo(6, PHASE)
	loopClock:setRate(-1)
	loopClock:setRate(1)
	Harness.assertArrayEqual(loopOrder, {
		"zeroForward",
		"durationForward",
		"authoredforward",
		"observedforward",
		"zeroForward",
		"zeroBackward",
		"authoredbackward",
		"observedbackward",
		"durationBackward",
		"durationForward",
		"authoredforward",
		"observedforward",
		"zeroForward",
	})
	Harness.assertEqual(loopPlayback:getPosition().timePosition, 0)
	Harness.assertEqual(loopPlayback:getPosition().loopIndex, 1)
	Harness.assertEqual(loopClock:getTaskCount(), 1)
	Harness.assertEqual(loopClock:getPhaseBindingCount(), 0)
end)

Harness.test("public Loop +1 rebuild seeks retain local position and target-loop provenance", function()
	local clock = FakeClock.new()
	local setups = 0
	local cleanups = 0
	local replayOrder: { string } = {}
	local function event(time: number, label: string): Event
		return {
			time = time,
			run = function(context)
				local position = context:getPosition()
				Harness.assertEqual(position.timePosition, time)
				table.insert(replayOrder, `{label}@{position.loopIndex}`)
			end,
		}
	end
	local playback = createPlayback(clock, {
		duration = 6,
		loop = true,
		addressPolicy = "rebuild",
		events = {
			event(0.8, "a"),
			event(2.4, "b"),
			event(4.6, "c"),
		},
		onPlay = function(context)
			setups += 1
			context:addCleanup(function()
				cleanups += 1
			end)
		end,
	})
	playback:play()
	local function seek(timePosition: number, loopIndex: number)
		Harness.assertTrue(playback:seek({
			timePosition = timePosition,
			loopIndex = loopIndex,
		}))
		local position = playback:getPosition()
		Harness.assertEqual(position.timePosition, timePosition)
		Harness.assertEqual(position.loopIndex, loopIndex)
	end
	local function loopPlusOne()
		local position = playback:getPosition()
		seek(position.timePosition, position.loopIndex + 1)
	end

	seek(0.8, 0)
	for _ = 1, 5 do
		loopPlusOne()
	end
	seek(1.1, 5)
	loopPlusOne()
	seek(0, 6)
	loopPlusOne()
	seek(5.9, 7)
	loopPlusOne()
	Harness.assertArrayEqual(replayOrder, {
		"a@0",
		"a@1",
		"a@2",
		"a@3",
		"a@4",
		"a@5",
		"a@5",
		"a@6",
		"a@7",
		"b@7",
		"c@7",
		"a@8",
		"b@8",
		"c@8",
	})
	Harness.assertEqual(setups, 13)
	Harness.assertEqual(cleanups, 12)
	Harness.assertEqual(playback:getPosition().timePosition, 5.9)
	Harness.assertEqual(playback:getPosition().loopIndex, 8)
	Harness.assertEqual(clock:read().timePosition, 0)
	Harness.assertEqual(clock:getTaskCount(), 1)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	playback:cancel()
	Harness.assertEqual(cleanups, 13)
end)

Harness.test("looping updates share phase execution across three complete loops", function()
	local clock = FakeClock.new()
	local adapter = adapterFor(clock)
	local positiveDelta = 0
	local zeroSamples = 0
	local sequence = Pulse.sequence({
		duration = 6,
		loop = true,
		updates = {
			{
				startTime = 0,
				endTime = 6,
				run = function(_context, dt)
					if dt == 0 then
						zeroSamples += 1
					else
						positiveDelta += dt
					end
				end,
			},
		},
	})
	local first = Pulse.playback(sequence, adapter)
	local second = Pulse.playback(sequence, adapter)
	first:play()
	second:play()
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	clock:advanceRootTo(18.25)
	clock:evaluatePhase(PHASE)
	Harness.assertNear(positiveDelta, 36.5)
	Harness.assertEqual(zeroSamples, 2)
	Harness.assertEqual(first:getPosition().loopIndex, 3)
	Harness.assertEqual(second:getPosition().loopIndex, 3)
	Harness.assertEqual(first:getPosition().timePosition, 0.25)
	Harness.assertEqual(second:getPosition().timePosition, 0.25)
	Harness.assertEqual(clock:getTaskCount(), 2)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	first:cancel()
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	second:cancel()
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
end)

Harness.test("pause and resume discard paused clock movement", function()
	local clock = FakeClock.new()
	local hits = 0
	local playback = createPlayback(clock, {
		duration = 2,
		events = {
			{
				time = 0.8,
				run = function()
					hits += 1
				end,
			},
		},
	})
	playback:play()
	clock:stepRootTo(0.4, PHASE)
	playback:pause()
	clock:advanceRootTo(2)
	playback:resume()
	Harness.assertNear(playback:getPosition().timePosition, 0.4)
	clock:stepRootTo(2.4, PHASE)
	Harness.assertEqual(hits, 1)
end)

Harness.test("playbackSpeed reanchors without snapping", function()
	local clock = FakeClock.new()
	local hits = 0
	local playback = createPlayback(clock, {
		duration = 2,
		events = {
			{
				time = 0.75,
				run = function()
					hits += 1
				end,
			},
		},
	})
	playback:play()
	clock:stepRootTo(0.25, PHASE)
	playback:setPlaybackSpeed(2)
	Harness.assertNear(playback:getPosition().timePosition, 0.25)
	clock:stepRootTo(0.5, PHASE)
	Harness.assertEqual(hits, 1)
	Harness.assertNear(playback:getPosition().timePosition, 0.75)
end)

Harness.test("same-sign clock rate changes reschedule the same task identity", function()
	local clock = FakeClock.new()
	local playback = createPlayback(clock, {
		duration = 2,
		events = {
			{ time = 1, run = function() end },
		},
	})
	playback:play()
	local id = clock:getLastTaskId()
	clock:setRate(2)
	Harness.assertEqual(clock:getScheduleCount(), 1)
	Harness.assertTrue(clock:getRescheduleCount() >= 1)
	Harness.assertEqual(clock:getLastTaskId(), id)
end)

Harness.test("direction change catches up before reversing traversal", function()
	local clock = FakeClock.new()
	local order: { string } = {}
	local playback = createPlayback(clock, {
		duration = 2,
		events = {
			{
				time = 0.5,
				run = function()
					table.insert(order, "forward")
				end,
				reverse = function()
					table.insert(order, "reverse")
				end,
			},
		},
	})
	playback:play()
	clock:advanceRootTo(0.75)
	clock:setRate(-1)
	Harness.assertArrayEqual(order, { "forward" })
	clock:stepRootTo(1, PHASE)
	Harness.assertArrayEqual(order, { "forward", "reverse" })

	local updateClock = FakeClock.new()
	local deltas: { number } = {}
	local updating = createPlayback(updateClock, {
		duration = 2,
		updates = {
			{
				startTime = 0,
				endTime = 2,
				run = function(_playback, dt)
					table.insert(deltas, dt)
				end,
			},
		},
	})
	updating:play()
	updateClock:advanceRootTo(0.4)
	updateClock:setRate(-1)
	updateClock:advanceRootTo(0.8)
	updateClock:setRate(1)
	Harness.assertEqual(#deltas, 2)
	Harness.assertNear(deltas[1], 0.4)
	Harness.assertNear(deltas[2], -0.4)
end)

Harness.test("discontinuity skip, rebuild, and cancel are distinct", function()
	local skipClock = FakeClock.new()
	local skipped = 0
	local skip = createPlayback(skipClock, {
		duration = 1,
		addressPolicy = "skip",
		events = {
			{
				time = 0.5,
				run = function()
					skipped += 1
				end,
			},
		},
	})
	skip:play()
	skipClock:jumpTo(0.75)
	Harness.assertEqual(skipped, 0)
	Harness.assertNear(skip:getPosition().timePosition, 0.75)

	local revisionClock = FakeClock.new()
	local nested = false
	local releaseExternal = revisionClock:bindToChanged(function()
		if not nested then
			nested = true
			revisionClock:jumpTo(0.75)
		end
	end, false)
	local revisionHits = 0
	local revisionPlayback = createPlayback(revisionClock, {
		duration = 1,
		addressPolicy = "skip",
		events = {
			{
				time = 0.5,
				run = function()
					revisionHits += 1
				end,
			},
		},
	})
	revisionPlayback:play()
	revisionClock:jumpTo(0.25)
	Harness.assertEqual(revisionHits, 0)
	Harness.assertNear(revisionPlayback:getPosition().timePosition, 0.75)
	releaseExternal()

	local rebuildClock = FakeClock.new()
	local order: { string } = {}
	local rebuild = createPlayback(rebuildClock, {
		duration = 1,
		addressPolicy = "rebuild",
		events = {
			{
				time = 0,
				run = function(context)
					table.insert(order, "zero")
					context:addCleanup(function()
						table.insert(order, "cleanup")
					end)
				end,
			},
			{
				time = 0.5,
				run = function()
					table.insert(order, "half")
				end,
			},
		},
	})
	rebuild:play()
	rebuildClock:jumpTo(0.75)
	Harness.assertArrayEqual(order, { "zero", "cleanup", "zero", "half" })

	local lifecycleClock = FakeClock.new()
	local setups = 0
	local cleanups = 0
	local setupPositions: { number } = {}
	local lifecycle = createPlayback(lifecycleClock, {
		duration = 1,
		addressPolicy = "rebuild",
		onPlay = function(context)
			setups += 1
			table.insert(setupPositions, context:getPosition().timePosition)
			context:addCleanup(function()
				cleanups += 1
			end)
		end,
	})
	lifecycle:play()
	lifecycleClock:jumpTo(0.5)
	Harness.assertEqual(setups, 2)
	Harness.assertEqual(cleanups, 1)
	Harness.assertArrayEqual(setupPositions, { 0, 0.5 })
	lifecycle:cancel()
	Harness.assertEqual(cleanups, 2)

	local cancelClock = FakeClock.new()
	local cancel = createPlayback(cancelClock, {
		duration = 1,
		addressPolicy = "cancel",
	})
	cancel:play()
	cancelClock:jumpTo(0.5)
	Harness.assertEqual(cancel:getCompletion().status, "cancelled")
end)

Harness.test("manual seek uses the sequence discontinuity policy", function()
	local clock = FakeClock.new()
	local runs = 0
	local playback = createPlayback(clock, {
		duration = 1,
		addressPolicy = "rebuild",
		events = {
			{
				time = 0.5,
				run = function()
					runs += 1
				end,
			},
		},
	})
	playback:play()
	Harness.assertTrue(playback:seek({ timePosition = 0.75 }))
	Harness.assertEqual(runs, 1)
	Harness.assertTrue(playback:seek({ timePosition = 0.25 }))
	Harness.assertEqual(runs, 1)
	Harness.assertTrue(playback:seek({ timePosition = 0.5 }))
	Harness.assertEqual(runs, 2)

	local terminalClock = FakeClock.new()
	local replayed = 0
	local terminal = createPlayback(terminalClock, {
		duration = 1,
		addressPolicy = "rebuild",
		events = {
			{
				time = 0,
				run = function()
					replayed += 1
				end,
			},
		},
		onPlay = function(context)
			context:addCleanup(function()
				context:cancel("cleanupCancelled")
			end)
		end,
	})
	terminal:play()
	terminal:seek({ timePosition = 0.5 })
	Harness.assertEqual(replayed, 1)
	Harness.assertEqual(terminal:getCompletion().reason, "cleanupCancelled")

	local directionClock = FakeClock.new()
	local reverseRuns = 0
	local direction = createPlayback(directionClock, {
		duration = 1,
		addressPolicy = "skip",
		events = {
			{
				time = 0.5,
				run = function() end,
				reverse = function()
					reverseRuns += 1
				end,
			},
		},
	})
	direction:play()
	directionClock:advanceRootTo(0.25)
	direction:pause()
	directionClock:setRate(-1)
	Harness.assertTrue(direction:seek({ timePosition = 0.5 }))
	direction:resume()
	Harness.assertEqual(reverseRuns, 0)
	direction:cancel()
end)

Harness.test("structured loop seeks retain the requested boundary side", function()
	local clock = FakeClock.new()
	local playback = createPlayback(clock, {
		duration = 6,
		loop = true,
		addressPolicy = "skip",
	})
	playback:play()
	Harness.assertTrue(playback:seek({ timePosition = 6, loopIndex = 2 }))
	local durationSide = playback:getPosition()
	Harness.assertEqual(durationSide.timePosition, 6)
	Harness.assertEqual(durationSide.loopIndex, 2)
	Harness.assertEqual(durationSide.unwrappedTimePosition, 18)
	Harness.assertTrue(playback:seek({ timePosition = 0, loopIndex = 3 }))
	local zeroSide = playback:getPosition()
	Harness.assertEqual(zeroSide.timePosition, 0)
	Harness.assertEqual(zeroSide.loopIndex, 3)
	Harness.assertEqual(zeroSide.unwrappedTimePosition, 18)
	Harness.assertEqual(clock:read().timePosition, 0)
	Harness.assertEqual(clock:getTaskCount(), 1)
	playback:cancel()
end)

Harness.test("terminal callback mutation interrupts equal-time work", function()
	local clock = FakeClock.new()
	local order: { string } = {}
	local seekAccepted = true
	local playback = createPlayback(clock, {
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function(context)
					table.insert(order, "first")
					context:cancel("inside")
					context:pause()
					context:setPlaybackSpeed(2)
					seekAccepted = context:seek({ timePosition = 0.75 })
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
	playback:play()
	clock:stepRootTo(0.5, PHASE)
	Harness.assertArrayEqual(order, { "first" })
	Harness.assertFalse(seekAccepted)
	Harness.assertEqual(playback:getPlaybackSpeed(), 1)
	Harness.assertEqual(playback:getCompletion().reason, "inside")

	local adapterClock = FakeClock.new()
	local adapter: TemporalAdapter
	local adapterPlayback: Playback
	adapterPlayback, adapter = createPlayback(adapterClock, {
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function(context)
					context:pause()
					adapter:destroy()
				end,
			},
		},
	})
	adapterPlayback:play()
	adapterClock:stepRootTo(0.5, PHASE)
	Harness.assertEqual(adapterPlayback:getCompletion().status, "failed")
	Harness.assertEqual(adapterPlayback:getCompletion().reason, "adapterDestroyed")
end)

Harness.test("nonterminal callback mutation is serialized after the occurrence", function()
	local clock = FakeClock.new()
	local order: { string } = {}
	local playback = createPlayback(clock, {
		duration = 2,
		events = {
			{
				time = 0.5,
				run = function(context)
					table.insert(order, "first")
					context:setPlaybackSpeed(2)
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
	playback:play()
	clock:stepRootTo(0.5, PHASE)
	Harness.assertArrayEqual(order, { "first", "second" })
	Harness.assertEqual(playback:getPlaybackSpeed(), 2)

	local seekClock = FakeClock.new()
	local address = { timePosition = 0.75 }
	local seekPlayback = createPlayback(seekClock, {
		duration = 1,
		events = {
			{
				time = 0.25,
				run = function(context)
					context:seek(address)
					address.timePosition = 2
				end,
			},
		},
	})
	seekPlayback:play()
	seekClock:stepRootTo(0.25, PHASE)
	Harness.assertNear(seekPlayback:getPosition().timePosition, 0.75)

	local cycleClock = FakeClock.new()
	local cycleRuns = 0
	local cycle = createPlayback(cycleClock, {
		duration = 1,
		addressPolicy = "rebuild",
		events = {
			{
				time = 0,
				run = function(context)
					cycleRuns += 1
					context:seek({ timePosition = 0 })
				end,
			},
		},
	})
	local cycleEnded = 0
	cycle:onEnded(function()
		cycleEnded += 1
	end)
	cycle:play()
	Harness.assertEqual(cycleRuns, 2_048)
	Harness.assertEqual(cycle:getCompletion().status, "failed")
	Harness.assertEqual(cycle:getCompletion().reason, "catchUpLimitExceeded")
	Harness.assertEqual(cycleEnded, 1)
	Harness.assertEqual(cycleClock:getTaskCount(), 0)
	Harness.assertEqual(cycleClock:getChangedBindingCount(), 0)
end)

Harness.test("stale reached work revalidates after an immediate clock jump", function()
	local pausedClock = FakeClock.new()
	local pausedOrder: { string } = {}
	local paused = createPlayback(pausedClock, {
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function()
					table.insert(pausedOrder, "beforePause")
				end,
			},
			{
				time = 0.75,
				run = function()
					table.insert(pausedOrder, "afterPause")
				end,
			},
		},
	})
	paused:play()
	pausedClock:setBeforeNextReached(function()
		paused:pause()
		pausedClock:advanceRootTo(0.75)
	end)
	pausedClock:stepRootTo(0.5, PHASE)
	Harness.assertArrayEqual(pausedOrder, { "beforePause" })
	Harness.assertEqual(paused:getStatus(), "paused")
	Harness.assertNear(paused:getPosition().timePosition, 0.5)

	local clock = FakeClock.new()
	local hits = 0
	local playback = createPlayback(clock, {
		duration = 1,
		addressPolicy = "skip",
		events = {
			{
				time = 0.5,
				run = function()
					hits += 1
				end,
			},
		},
	})
	playback:play()
	clock:setBeforeNextReached(function()
		clock:jumpTo(0)
	end)
	clock:stepRootTo(0.5, PHASE)
	Harness.assertEqual(hits, 1)
	Harness.assertNear(playback:getPosition().timePosition, 0)

	local largeClock = FakeClock.new()
	local largeHits = 0
	local large = createPlayback(largeClock, {
		duration = 1,
		loop = true,
		addressPolicy = "skip",
		events = {
			{
				time = 0,
				run = function()
					largeHits += 1
				end,
			},
		},
	}, {
		position = { timePosition = 0, loopIndex = 1_000_000_000_000 },
	})
	large:play()
	largeClock:setBeforeNextReached(function()
		largeClock:jumpTo(-499)
	end)
	largeClock:stepRootTo(1, PHASE)
	Harness.assertEqual(largeHits, 2)
end)

Harness.test("cancel, destroy, and adapter destruction release all ownership", function()
	local clock = FakeClock.new()
	local playback, adapter = createPlayback(clock, {
		duration = 2,
		updates = {
			{ startTime = 0, endTime = 2, run = function() end },
		},
	})
	playback:play()
	playback:cancel("done")
	Harness.assertEqual(clock:getTaskCount(), 0)
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	playback:destroy()
	adapter:destroy()

	local otherClock = FakeClock.new()
	local other, otherAdapter = createPlayback(otherClock, { duration = 2 })
	other:play()
	otherAdapter:destroy()
	Harness.assertEqual(other:getCompletion().status, "failed")
	Harness.assertEqual(otherClock:getTaskCount(), 0)

	local detachedClock = FakeClock.new()
	local detachedAdapter = adapterFor(detachedClock)
	Harness.assertFalse(detachedAdapter:isDestroyed())
	detachedClock:destroy()
	Harness.assertTrue(detachedAdapter:isDestroyed())
end)

Harness.test("callback failure and numeric precision handling are deterministic", function()
	local callbackClock = FakeClock.new()
	local callbackPlayback = createPlayback(callbackClock, {
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
	local callbackEnded = 0
	callbackPlayback:onEnded(function()
		callbackEnded += 1
	end)
	callbackPlayback:play()
	callbackClock:stepRootTo(0.5, PHASE)
	Harness.assertEqual(callbackPlayback:getCompletion().status, "failed")
	Harness.assertEqual(callbackEnded, 1)
	Harness.assertEqual(callbackClock:getTaskCount(), 0)

	local overflowClock = FakeClock.new()
	local overflow = createPlayback(overflowClock, {
		duration = 1,
		addressPolicy = "skip",
	}, {
		playbackSpeed = 1e308,
	})
	local overflowEnded = 0
	overflow:onEnded(function()
		overflowEnded += 1
	end)
	overflow:play()
	overflowClock:jumpTo(2)
	Harness.assertEqual(overflow:getCompletion().status, "failed")
	Harness.assertEqual(overflow:getCompletion().reason, "numericOverflow")
	Harness.assertEqual(overflowEnded, 1)

	local precisionClock = FakeClock.new({ timePosition = 1e16 })
	local precision = createPlayback(precisionClock, {
		duration = 2,
		events = {
			{ time = 1, run = function() end },
		},
	})
	precision:play()
	Harness.assertEqual(precision:getCompletion().status, "failed")
	Harness.assertEqual(precision:getCompletion().reason, "numericOverflow")
	Harness.assertEqual(precisionClock:getTaskCount(), 0)

	local loopClock = FakeClock.new()
	local looping = createPlayback(loopClock, {
		duration = 1,
		loop = true,
		addressPolicy = "skip",
	})
	local loopEnded = 0
	looping:onEnded(function()
		loopEnded += 1
	end)
	looping:play()
	loopClock:jumpTo(1e16)
	Harness.assertEqual(looping:getCompletion().status, "failed")
	Harness.assertEqual(looping:getCompletion().reason, "numericOverflow")
	Harness.assertEqual(loopEnded, 1)
	Harness.assertEqual(loopClock:getTaskCount(), 0)
	Harness.assertEqual(loopClock:getChangedBindingCount(), 0)
	Harness.assertEqual(loopClock:getPhaseBindingCount(), 0)

	local boundaryClock = FakeClock.new()
	local boundary = createPlayback(boundaryClock, {
		duration = 1,
		loop = true,
		events = {
			{ time = 0.01, run = function() end },
		},
	}, {
		position = { timePosition = 0.5, loopIndex = 1_000_000_000_000_000 },
	})
	boundary:play()
	Harness.assertEqual(boundary:getCompletion().status, "failed")
	Harness.assertEqual(boundary:getCompletion().reason, "numericOverflow")
	Harness.assertEqual(boundaryClock:getTaskCount(), 0)

	local driftClock = FakeClock.new()
	local driftRuns = 0
	local driftPosition: PlaybackPosition? = nil
	local drift = createPlayback(driftClock, {
		duration = 1,
		loop = true,
		events = {
			{
				time = 0.01,
				run = function(context)
					driftRuns += 1
					driftPosition = context:getPosition()
				end,
			},
		},
	}, {
		position = { timePosition = 0.5, loopIndex = 1_000_000_000_000 },
	})
	drift:play()
	Harness.assertEqual(driftRuns, 1)
	Harness.assertEqual((driftPosition :: PlaybackPosition).timePosition, 0.01)
	Harness.assertEqual((driftPosition :: PlaybackPosition).loopIndex, 1_000_000_000_000)
	Harness.assertTrue(drift:isAlive())
	Harness.assertEqual(driftClock:getTaskCount(), 1)

	local identityClock = FakeClock.new()
	local identity = createPlayback(identityClock, {
		duration = 1,
		loop = true,
	}, {
		position = { timePosition = 0, loopIndex = 9_007_199_254_740_991 },
	})
	identity:play()
	Harness.assertEqual(identity:getCompletion().status, "failed")
	Harness.assertEqual(identity:getCompletion().reason, "numericOverflow")
	Harness.assertEqual(identityClock:getTaskCount(), 0)

	local collisionClock = FakeClock.new()
	local collisionRuns = 0
	local collision = createPlayback(collisionClock, {
		duration = 1,
		loop = true,
		events = {
			{
				time = 0.49,
				run = function()
					collisionRuns += 1
				end,
			},
			{
				time = 0.5,
				run = function()
					collisionRuns += 1
				end,
			},
		},
	}, {
		position = { timePosition = 0.25, loopIndex = 1_000_000_000_000_000 },
	})
	collision:play()
	Harness.assertEqual(collisionRuns, 0)
	Harness.assertEqual(collision:getCompletion().status, "failed")
	Harness.assertEqual(collision:getCompletion().reason, "numericOverflow")
	Harness.assertEqual(collisionClock:getTaskCount(), 0)
end)

Harness.test("cleanup is generation-scoped and terminal cleanup is immediate LIFO", function()
	local clock = FakeClock.new()
	local order: { string } = {}
	local playback = createPlayback(clock, {
		duration = 1,
		onPlay = function(context)
			context:addCleanup(function()
				table.insert(order, "first")
			end)
			context:addCleanup(function()
				table.insert(order, "second")
			end)
		end,
	})
	playback:play()
	playback:cancel()
	Harness.assertArrayEqual(order, { "second", "first" })

	local recursiveClock = FakeClock.new()
	local nestedCleanup = 0
	local recursive = createPlayback(recursiveClock, {
		duration = 1,
		onPlay = function(context)
			context:addCleanup(function()
				context:cancel("cleanup")
				context:addCleanup(function()
					nestedCleanup += 1
				end)
			end)
		end,
	})
	local ended = 0
	recursive:onEnded(function()
		ended += 1
	end)
	recursive:play()
	recursive:cancel("outer")
	Harness.assertEqual(recursive:getCompletion().reason, "outer")
	Harness.assertEqual(nestedCleanup, 1)
	Harness.assertEqual(ended, 1)

	local cleanupCycleClock = FakeClock.new()
	local cleanupCycleRuns = 0
	local cleanupCycle = createPlayback(cleanupCycleClock, {
		duration = 1,
		addressPolicy = "rebuild",
		onPlay = function(context)
			local cleanup: () -> ()
			cleanup = function()
				cleanupCycleRuns += 1
				context:addCleanup(cleanup)
				context:seek({ timePosition = 0 })
			end
			context:addCleanup(cleanup)
			context:seek({ timePosition = 0 })
		end,
	})
	cleanupCycle:play()
	Harness.assertEqual(cleanupCycleRuns, 4_096)
	Harness.assertEqual(cleanupCycle:getCompletion().status, "failed")
	Harness.assertEqual(cleanupCycle:getCompletion().reason, "cleanupFailed")
	Harness.assertEqual(cleanupCycleClock:getTaskCount(), 0)
	Harness.assertEqual(cleanupCycleClock:getChangedBindingCount(), 0)

	local mutationClock = FakeClock.new()
	local mutationRuns = 0
	local seekAccepted = true
	local mutation = createPlayback(mutationClock, {
		duration = 1,
		addressPolicy = "rebuild",
		events = {
			{
				time = 0.5,
				run = function()
					mutationRuns += 1
				end,
			},
		},
		onPlay = function(context)
			context:addCleanup(function()
				seekAccepted = context:seek({ timePosition = 0.75 })
				context:pause()
				context:setPlaybackSpeed(2)
			end)
		end,
	})
	mutation:play()
	mutation:cancel("terminal")
	Harness.assertFalse(seekAccepted)
	Harness.assertEqual(mutationRuns, 0)
	Harness.assertEqual(mutation:getPlaybackSpeed(), 1)
	Harness.assertEqual(mutation:getCompletion().reason, "terminal")

	local idleClock = FakeClock.new()
	local idle = createPlayback(idleClock, {
		duration = 1,
		events = {
			{ time = 0.5, run = function() end },
		},
	})
	idle:addCleanup(function()
		idle:play()
	end)
	idle:cancel("idle")
	Harness.assertEqual(idleClock:getTaskCount(), 0)
	Harness.assertEqual(idleClock:getChangedBindingCount(), 0)
	Harness.assertEqual(idleClock:getPhaseBindingCount(), 0)
	Harness.assertEqual(idle:getCompletion().reason, "idle")

	local immutableClock = FakeClock.new()
	local immutable = createPlayback(immutableClock, { duration = 2 })
	local observedReason = ""
	immutable:onEnded(function(completion)
		completion.reason = "mutated"
	end)
	immutable:onEnded(function(completion)
		observedReason = completion.reason or ""
	end)
	immutable:play()
	immutable:cancel("original")
	Harness.assertEqual(observedReason, "original")
	Harness.assertEqual(immutable:getCompletion().reason, "original")

	local endedClock = FakeClock.new()
	local endedPlayback = createPlayback(endedClock, { duration = 1 })
	local endedCalls = 0
	local endedCallback: (completion: Completion) -> ()
	endedCallback = function()
		endedCalls += 1
		endedPlayback:onEnded(endedCallback)
	end
	endedPlayback:onEnded(endedCallback)
	endedPlayback:play()
	endedPlayback:cancel()
	Harness.assertEqual(endedCalls, 1)
	endedPlayback:onEnded(endedCallback)
	Harness.assertEqual(endedCalls, 2)
end)
