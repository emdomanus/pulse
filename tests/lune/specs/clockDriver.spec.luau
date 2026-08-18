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
	setRevisionForTest: (self: FakeClock, revision: number) -> (),
	jumpTo: (self: FakeClock, timePosition: number) -> (),
	bindToChanged: (self: FakeClock, callback: (change: unknown) -> (), runInitially: boolean?) -> () -> (),
	isDestroyed: (self: FakeClock) -> boolean,
	destroy: (self: FakeClock) -> (),
	setBeforeNextReached: (self: FakeClock, callback: (() -> ())?) -> (),
	setDuringNextSchedule: (self: FakeClock, callback: (() -> ())?) -> (),
	getTaskCount: (self: FakeClock) -> number,
	getChangedBindingCount: (self: FakeClock) -> number,
	getPhaseBindingCount: (self: FakeClock) -> number,
	getChangedReleaseCount: (self: FakeClock) -> number,
	getPhaseReleaseCount: (self: FakeClock) -> number,
	getScheduleCount: (self: FakeClock) -> number,
	getRescheduleCount: (self: FakeClock) -> number,
	getCancelCount: (self: FakeClock) -> number,
	getReadCount: (self: FakeClock) -> number,
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
	play: (self: Playback, sample: { position: number, rate: number }) -> Playback,
	evaluate: (self: Playback, sample: { position: number, rate: number }) -> boolean,
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
	onLooped: (self: Playback, callback: (change: unknown) -> ()) -> () -> (),
	isAlive: (self: Playback) -> boolean,
	getCompletion: (self: Playback) -> Completion?,
}

type DrivenPlayback = {
	play: (self: DrivenPlayback) -> DrivenPlayback,
	pause: (self: DrivenPlayback) -> (),
	resume: (self: DrivenPlayback) -> (),
	setPlaybackSpeed: (self: DrivenPlayback, speed: number) -> (),
	getPlaybackSpeed: (self: DrivenPlayback) -> number,
	seek: (self: DrivenPlayback, address: { timePosition: number, loopIndex: number? }, mode: AddressMode) -> boolean,
	getPosition: (self: DrivenPlayback) -> PlaybackPosition,
	getStatus: (self: DrivenPlayback) -> string,
	addCleanup: (self: DrivenPlayback, cleanup: () -> ()) -> (),
	cancel: (self: DrivenPlayback, reason: string?) -> (),
	destroy: (self: DrivenPlayback) -> (),
	onEnded: (self: DrivenPlayback, callback: (completion: Completion) -> ()) -> () -> (),
	onLooped: (self: DrivenPlayback, callback: (change: unknown) -> ()) -> () -> (),
	isAlive: (self: DrivenPlayback) -> boolean,
	getCompletion: (self: DrivenPlayback) -> Completion?,
	detach: (self: DrivenPlayback) -> Playback,
}

type ClockDriver = {
	attach: (
		self: ClockDriver,
		playback: Playback,
		options: { discontinuityMode: "skip" | "reconstruct" | "cancel" }
	) -> DrivenPlayback,
	destroy: (self: ClockDriver) -> (),
	isDestroyed: (self: ClockDriver) -> boolean,
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

type PulseApi = {
	sequence: (definition: Definition) -> Sequence,
	playback: (
		sequence: Sequence,
		context: unknown,
		options: {
			playbackSpeed: number?,
			position: { timePosition: number, loopIndex: number? }?,
			initialMode: AddressMode?,
		}?
	) -> Playback,
	clockDriver: (clock: FakeClock, phase: string, directions: unknown) -> ClockDriver,
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
	tempDir = ".lune-pulse-driver-tests",
})
local Pulse = (transformed.requireModule("init.luau") :: unknown) :: PulseApi
transformed.cleanup()

local PHASE = "simulation"

local function driverFor(clock: FakeClock): ClockDriver
	return Pulse.clockDriver(clock, PHASE, clock.directions)
end

local function createDriven(
	clock: FakeClock,
	definition: Definition,
	mode: "skip" | "reconstruct" | "cancel",
	options: {
		playbackSpeed: number?,
		position: { timePosition: number, loopIndex: number? }?,
		initialMode: AddressMode?,
	}?
): (DrivenPlayback, Playback, ClockDriver)
	local driver = driverFor(clock)
	local playback = Pulse.playback(Pulse.sequence(definition), nil, options)
	return driver:attach(playback, { discontinuityMode = mode }), playback, driver
end

local function stepPhaseTicks(clock: FakeClock, count: number)
	for tick = 1, count do
		clock:stepRootTo(tick / (count + 1), PHASE)
	end
end

Harness.test("event-only driven playback owns one deadline and no phase binding", function()
	local clock = FakeClock.new()
	local hits = 0
	local driven = createDriven(clock, {
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function()
					hits += 1
				end,
			},
		},
	}, "skip")
	driven:play()
	Harness.assertEqual(clock:getChangedBindingCount(), 1)
	Harness.assertEqual(clock:getTaskCount(), 1)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	clock:stepRootTo(0.5, PHASE)
	Harness.assertEqual(hits, 1)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	clock:stepRootTo(1, PHASE)
	Harness.assertEqual(driven:getStatus(), "completed")
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
end)

Harness.test("sampled playbacks share one phase binding and release it with the last member", function()
	local clock = FakeClock.new()
	local driver = driverFor(clock)
	local firstSamples = 0
	local secondSamples = 0
	local first = driver:attach(
		Pulse.playback(
			Pulse.sequence({
				duration = 1,
				samples = {
					{
						run = function()
							firstSamples += 1
						end,
					},
				},
			}),
			nil
		),
		{ discontinuityMode = "skip" }
	)
	local second = driver:attach(
		Pulse.playback(
			Pulse.sequence({
				duration = 1,
				samples = {
					{
						run = function()
							secondSamples += 1
						end,
					},
				},
			}),
			nil
		),
		{ discontinuityMode = "skip" }
	)
	first:play()
	second:play()
	Harness.assertEqual(clock:getChangedBindingCount(), 1)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	clock:stepRootTo(0.25, PHASE)
	Harness.assertEqual(firstSamples, 2)
	Harness.assertEqual(secondSamples, 2)
	first:cancel()
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	second:cancel()
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	Harness.assertEqual(clock:getPhaseReleaseCount(), 1)
end)

Harness.test("ordinary Sample phase ticks keep an unchanged deadline without rescheduling", function()
	local clock = FakeClock.new()
	local samples = 0
	local driven = createDriven(clock, {
		duration = 2,
		samples = {
			{
				startTime = 0,
				endTime = 1,
				run = function()
					samples += 1
				end,
			},
		},
	}, "skip" :: "skip")
	driven:play()

	local readsBefore = clock:getReadCount()
	local schedulesBefore = clock:getScheduleCount()
	local reschedulesBefore = clock:getRescheduleCount()
	clock:stepRootTo(0.1, PHASE)
	clock:stepRootTo(0.2, PHASE)
	clock:stepRootTo(0.3, PHASE)

	Harness.assertEqual(samples, 4)
	Harness.assertEqual(clock:getReadCount(), readsBefore + 3)
	Harness.assertEqual(clock:getScheduleCount(), schedulesBefore)
	Harness.assertEqual(clock:getRescheduleCount(), reschedulesBefore)
	Harness.assertEqual(clock:getTaskCount(), 1)
	driven:cancel()
end)

Harness.test("one shared phase read fans out across multiple unchanged attachments", function()
	local clock = FakeClock.new()
	local driver = driverFor(clock)
	local sequence = Pulse.sequence({
		duration = 2,
		samples = {
			{
				startTime = 0,
				endTime = 1,
				run = function() end,
			},
		},
	})
	local drivenPlaybacks: { DrivenPlayback } = {}
	for _ = 1, 4 do
		local driven = driver:attach(Pulse.playback(sequence, nil), {
			discontinuityMode = "skip" :: "skip",
		})
		table.insert(drivenPlaybacks, driven)
		driven:play()
	end

	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	local readsBefore = clock:getReadCount()
	local reschedulesBefore = clock:getRescheduleCount()
	clock:stepRootTo(0.1, PHASE)
	Harness.assertEqual(clock:getReadCount(), readsBefore + 1)
	Harness.assertEqual(clock:getRescheduleCount(), reschedulesBefore)

	for _, driven in drivenPlaybacks do
		driven:cancel()
	end
end)

Harness.test("non-unit phase ticks retain one numerically equivalent deadline", function()
	local clock = FakeClock.new()
	local driven = createDriven(clock, {
		duration = 10,
		samples = {
			{
				startTime = 0,
				endTime = 10,
				run = function() end,
			},
		},
	}, "skip" :: "skip", { playbackSpeed = 1.3 })
	driven:play()

	local readsBefore = clock:getReadCount()
	local schedulesBefore = clock:getScheduleCount()
	local reschedulesBefore = clock:getRescheduleCount()
	stepPhaseTicks(clock, 128)
	Harness.assertEqual(clock:getReadCount(), readsBefore + 128)
	Harness.assertEqual(clock:getScheduleCount(), schedulesBefore)
	Harness.assertEqual(clock:getRescheduleCount(), reschedulesBefore)
	Harness.assertEqual(clock:getTaskCount(), 1)

	local beforeMaterialSpeed = clock:getRescheduleCount()
	driven:setPlaybackSpeed(1.5)
	Harness.assertEqual(clock:getRescheduleCount(), beforeMaterialSpeed + 1)
	Harness.assertEqual(clock:getTaskCount(), 1)
	driven:cancel()
end)

Harness.test("multiple non-unit attachments retain one shared read and stable deadlines", function()
	local clock = FakeClock.new()
	local driver = driverFor(clock)
	local sequence = Pulse.sequence({
		duration = 10,
		samples = {
			{
				startTime = 0,
				endTime = 10,
				run = function() end,
			},
		},
	})
	local drivenPlaybacks: { DrivenPlayback } = {}
	for _ = 1, 4 do
		local driven = driver:attach(Pulse.playback(sequence, nil, { playbackSpeed = 1.3 }), {
			discontinuityMode = "skip" :: "skip",
		})
		table.insert(drivenPlaybacks, driven)
		driven:play()
	end

	local readsBefore = clock:getReadCount()
	local reschedulesBefore = clock:getRescheduleCount()
	stepPhaseTicks(clock, 128)
	Harness.assertEqual(clock:getReadCount(), readsBefore + 128)
	Harness.assertEqual(clock:getRescheduleCount(), reschedulesBefore)
	Harness.assertEqual(clock:getTaskCount(), 4)
	for _, driven in drivenPlaybacks do
		driven:cancel()
	end
end)

Harness.test("backward non-unit phase ticks retain one numerically equivalent deadline", function()
	local clock = FakeClock.new({ rate = -1 })
	local driven = createDriven(
		clock,
		{
			duration = 10,
			samples = {
				{
					startTime = 0,
					endTime = 10,
					run = function() end,
				},
			},
		},
		"skip" :: "skip",
		{
			playbackSpeed = 1.3,
			position = { timePosition = 10 },
			initialMode = "skip" :: AddressMode,
		}
	)
	driven:play()

	local readsBefore = clock:getReadCount()
	local reschedulesBefore = clock:getRescheduleCount()
	stepPhaseTicks(clock, 128)
	Harness.assertEqual(clock:getReadCount(), readsBefore + 128)
	Harness.assertEqual(clock:getRescheduleCount(), reschedulesBefore)
	Harness.assertEqual(clock:getTaskCount(), 1)
	driven:cancel()
end)

Harness.test("large absolute source coordinates retain numerically equivalent deadlines", function()
	local largeCoordinate = 1_000_000_000_000
	local clock = FakeClock.new({ timePosition = largeCoordinate })
	local driven = createDriven(clock, {
		duration = largeCoordinate,
		samples = {
			{
				startTime = 0,
				endTime = largeCoordinate,
				run = function() end,
			},
		},
	}, "skip" :: "skip", { playbackSpeed = 1.3 })
	driven:play()

	local readsBefore = clock:getReadCount()
	local reschedulesBefore = clock:getRescheduleCount()
	stepPhaseTicks(clock, 128)
	Harness.assertEqual(clock:getReadCount(), readsBefore + 128)
	Harness.assertEqual(clock:getRescheduleCount(), reschedulesBefore)
	Harness.assertEqual(clock:getTaskCount(), 1)

	local beforeMaterialSpeed = clock:getRescheduleCount()
	driven:setPlaybackSpeed(1.5)
	Harness.assertEqual(clock:getRescheduleCount(), beforeMaterialSpeed + 1)
	Harness.assertEqual(clock:getTaskCount(), 1)
	driven:cancel()
end)

Harness.test("reaching a numerically equivalent cached deadline still evaluates it", function()
	local clock = FakeClock.new()
	local durationHits = 0
	local driven = createDriven(clock, {
		duration = 10,
		events = {
			{
				time = 10,
				run = function()
					durationHits += 1
				end,
			},
		},
		samples = {
			{
				startTime = 0,
				endTime = 10,
				run = function() end,
			},
		},
	}, "skip" :: "skip", { playbackSpeed = 1.3 })
	driven:play()
	stepPhaseTicks(clock, 128)

	clock:stepRootTo(10 / 1.3, PHASE)
	Harness.assertEqual(durationHits, 1)
	Harness.assertEqual(driven:getStatus(), "completed")
	Harness.assertEqual(clock:getTaskCount(), 0)
end)

Harness.test("material speed seek direction and discontinuity changes refresh deadlines", function()
	do
		local clock = FakeClock.new()
		local driven = createDriven(clock, {
			duration = 1,
			events = { { time = 0.5, run = function() end } },
		}, "skip" :: "skip")
		driven:play()
		local before = clock:getRescheduleCount()
		driven:setPlaybackSpeed(2)
		Harness.assertEqual(clock:getRescheduleCount(), before + 1)
		Harness.assertEqual(clock:getTaskCount(), 1)
		driven:cancel()
	end

	do
		local clock = FakeClock.new()
		local driven = createDriven(clock, {
			duration = 1,
			events = { { time = 0.5, run = function() end } },
		}, "skip" :: "skip")
		driven:play()
		local before = clock:getRescheduleCount()
		driven:seek({ timePosition = 0.75 }, "skip" :: AddressMode)
		Harness.assertEqual(clock:getRescheduleCount(), before + 1)
		Harness.assertEqual(clock:getTaskCount(), 1)
		driven:cancel()
	end

	do
		local clock = FakeClock.new()
		local driven = createDriven(
			clock,
			{
				duration = 1,
				events = { { time = 0.5, run = function() end } },
			},
			"skip" :: "skip",
			{
				position = { timePosition = 0.25 },
				initialMode = "skip" :: AddressMode,
			}
		)
		driven:play()
		local schedulesBefore = clock:getScheduleCount()
		local cancelsBefore = clock:getCancelCount()
		clock:setRate(-1)
		Harness.assertEqual(clock:getScheduleCount(), schedulesBefore + 1)
		Harness.assertEqual(clock:getCancelCount(), cancelsBefore + 1)
		Harness.assertEqual(clock:getTaskCount(), 1)
		driven:cancel()
	end

	do
		local clock = FakeClock.new()
		local hits = 0
		local driven = createDriven(clock, {
			duration = 1,
			events = {
				{
					time = 0.5,
					run = function()
						hits += 1
					end,
				},
			},
		}, "skip" :: "skip")
		driven:play()
		local before = clock:getRescheduleCount()
		clock:jumpTo(0.75)
		Harness.assertEqual(hits, 0)
		Harness.assertEqual(clock:getRescheduleCount(), before + 1)
		Harness.assertEqual(clock:getTaskCount(), 1)
		driven:cancel()
	end
end)

Harness.test("newly scheduled deadlines validate source movement during scheduling", function()
	local clock = FakeClock.new()
	local hits = 0
	local driven = createDriven(clock, {
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function()
					hits += 1
				end,
			},
		},
	}, "skip" :: "skip")
	clock:setDuringNextSchedule(function()
		clock:advanceRootTo(0.75)
	end)

	driven:play()
	Harness.assertEqual(hits, 1)
	Harness.assertNear(driven:getPosition().timePosition, 0.75)
	Harness.assertEqual(clock:getTaskCount(), 1)
	driven:cancel()
end)

Harness.test("sample interval boundaries switch phase ownership while completion stays scheduled", function()
	local clock = FakeClock.new()
	local samples = 0
	local driven = createDriven(clock, {
		duration = 1,
		samples = {
			{
				startTime = 0.2,
				endTime = 0.4,
				run = function()
					samples += 1
				end,
			},
		},
	}, "skip")
	driven:play()
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	Harness.assertEqual(clock:getTaskCount(), 1)
	local beforeStartBoundary = clock:getRescheduleCount()
	clock:stepRootTo(0.2, PHASE)
	Harness.assertEqual(samples, 1)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	Harness.assertEqual(clock:getRescheduleCount(), beforeStartBoundary + 1)
	local beforeEndBoundary = clock:getRescheduleCount()
	clock:stepRootTo(0.4, PHASE)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	Harness.assertEqual(clock:getTaskCount(), 1)
	Harness.assertEqual(clock:getRescheduleCount(), beforeEndBoundary + 1)
	clock:stepRootTo(1, PHASE)
	Harness.assertEqual(driven:getStatus(), "completed")
end)

Harness.test("backward entry at an excluded Sample end retains phase ownership", function()
	local clock = FakeClock.new({ timePosition = 0.8, rate = -1 })
	local positions: { number } = {}
	local driven = createDriven(
		clock,
		{
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
		},
		"skip" :: "skip",
		{
			position = { timePosition = 0.8 },
			initialMode = "skip" :: AddressMode,
		}
	)

	driven:play()
	Harness.assertEqual(#positions, 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)

	clock:stepRootTo(0.01, PHASE)
	Harness.assertEqual(#positions, 1)
	Harness.assertNear(positions[1], 0.79)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)

	clock:stepRootTo(0.02, PHASE)
	Harness.assertEqual(#positions, 2)
	Harness.assertNear(positions[2], 0.78)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	driven:cancel()
end)

Harness.test("event-only duration-side join is observed until forward source movement", function()
	local clock = FakeClock.new()
	local loops = 0
	local zeroLoops: { number } = {}
	local driven = createDriven(clock, {
		duration = 1,
		loop = true,
		events = {
			{
				time = 0,
				run = function(playback)
					table.insert(zeroLoops, playback:getPosition().loopIndex)
				end,
			},
		},
		onLoop = function()
			loops += 1
		end,
	}, "skip" :: "skip", { initialMode = "skip" :: AddressMode })

	driven:play()
	driven:seek({ timePosition = 1, loopIndex = 2 }, "skip" :: AddressMode)
	Harness.assertEqual(driven:getPosition().timePosition, 1)
	Harness.assertEqual(driven:getPosition().loopIndex, 2)
	Harness.assertEqual(loops, 0)
	Harness.assertEqual(#zeroLoops, 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)

	clock:evaluatePhase(PHASE)
	Harness.assertEqual(driven:getPosition().timePosition, 1)
	Harness.assertEqual(driven:getPosition().loopIndex, 2)
	Harness.assertEqual(loops, 0)
	Harness.assertEqual(#zeroLoops, 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)

	clock:stepRootTo(0.0001, PHASE)
	Harness.assertEqual(loops, 1)
	Harness.assertArrayEqual(zeroLoops, { 3 })
	Harness.assertNear(driven:getPosition().timePosition, 0.0001)
	Harness.assertEqual(driven:getPosition().loopIndex, 3)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	Harness.assertEqual(clock:getTaskCount(), 1)
	driven:cancel()
end)

Harness.test("event-only zero-side join is observed until backward source movement", function()
	local clock = FakeClock.new({ rate = -1 })
	local loops = 0
	local durationLoops: { number } = {}
	local driven = createDriven(
		clock,
		{
			duration = 1,
			loop = true,
			events = {
				{
					time = 1,
					run = function() end,
					reverse = function(playback)
						table.insert(durationLoops, playback:getPosition().loopIndex)
					end,
				},
			},
			onLoop = function()
				loops += 1
			end,
		},
		"skip" :: "skip",
		{
			position = { timePosition = 0.5 },
			initialMode = "skip" :: AddressMode,
		}
	)

	driven:play()
	driven:seek({ timePosition = 0, loopIndex = 3 }, "skip" :: AddressMode)
	Harness.assertEqual(driven:getPosition().timePosition, 0)
	Harness.assertEqual(driven:getPosition().loopIndex, 3)
	Harness.assertEqual(loops, 0)
	Harness.assertEqual(#durationLoops, 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)

	clock:evaluatePhase(PHASE)
	Harness.assertEqual(driven:getPosition().timePosition, 0)
	Harness.assertEqual(driven:getPosition().loopIndex, 3)
	Harness.assertEqual(loops, 0)
	Harness.assertEqual(#durationLoops, 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)

	clock:stepRootTo(0.0001, PHASE)
	Harness.assertEqual(loops, 1)
	Harness.assertArrayEqual(durationLoops, { 2 })
	Harness.assertNear(driven:getPosition().timePosition, 0.9999)
	Harness.assertEqual(driven:getPosition().loopIndex, 2)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	Harness.assertEqual(clock:getTaskCount(), 1)
	driven:cancel()
end)

Harness.test("driver preserves a duration-side address until source motion enters the next loop", function()
	local clock = FakeClock.new()
	local loops = 0
	local samples = 0
	local driven = createDriven(clock, {
		duration = 1,
		loop = true,
		samples = {
			{
				startTime = 0,
				endTime = 0.5,
				run = function()
					samples += 1
				end,
			},
		},
		onLoop = function()
			loops += 1
		end,
	}, "skip", { initialMode = "skip" })
	driven:play()
	samples = 0
	driven:seek({ timePosition = 1, loopIndex = 2 }, "skip")
	Harness.assertEqual(driven:getPosition().timePosition, 1)
	Harness.assertEqual(driven:getPosition().loopIndex, 2)
	Harness.assertEqual(loops, 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)
	samples = 0

	clock:stepRootTo(0.1, PHASE)
	Harness.assertEqual(loops, 1)
	Harness.assertEqual(samples, 1)
	Harness.assertNear(driven:getPosition().timePosition, 0.1)
	Harness.assertEqual(driven:getPosition().loopIndex, 3)
	driven:cancel()
end)

Harness.test("paused driven seek callback resume waits for the next phase sample", function()
	local clock = FakeClock.new()
	local eventHits = 0
	local samplePositions: { number } = {}
	local driven = createDriven(clock, {
		duration = 2,
		events = {
			{
				time = 0.75,
				run = function()
					eventHits += 1
				end,
			},
		},
		samples = {
			{
				startTime = 0,
				endTime = 2,
				run = function(_playback, sample)
					table.insert(samplePositions, sample.position.timePosition)
				end,
			},
		},
		onAddress = function(control, info)
			if info.cause == "seek" then
				control:resume()
			end
		end,
	}, "skip" :: "skip")

	driven:play()
	clock:advanceRootTo(0.2)
	driven:pause()
	samplePositions = {}
	clock:advanceRootTo(1.2)
	driven:seek({ timePosition = 0.5 }, "skip" :: AddressMode)

	Harness.assertEqual(driven:getStatus(), "playing")
	Harness.assertNear(driven:getPosition().timePosition, 0.5)
	Harness.assertArrayEqual(samplePositions, { 0.5 })
	Harness.assertEqual(eventHits, 0)
	Harness.assertEqual(clock:getTaskCount(), 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)

	clock:evaluatePhase(PHASE)
	Harness.assertNear(driven:getPosition().timePosition, 0.5)
	Harness.assertArrayEqual(samplePositions, { 0.5, 0.5 })
	Harness.assertEqual(eventHits, 0)
	Harness.assertEqual(clock:getTaskCount(), 1)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)

	clock:stepRootTo(1.3, PHASE)
	Harness.assertNear(driven:getPosition().timePosition, 0.6)
	clock:stepRootTo(1.45, PHASE)
	Harness.assertEqual(eventHits, 1)
	Harness.assertNear(driven:getPosition().timePosition, 0.75)
	driven:cancel()
end)

Harness.test("event-only callback resume releases transient phase ownership into a deadline", function()
	local clock = FakeClock.new()
	local eventHits = 0
	local driven = createDriven(clock, {
		duration = 1,
		events = {
			{
				time = 0.75,
				run = function()
					eventHits += 1
				end,
			},
		},
		onAddress = function(control, info)
			if info.cause == "seek" then
				control:resume()
			end
		end,
	}, "skip" :: "skip")

	driven:play()
	clock:advanceRootTo(0.2)
	driven:pause()
	clock:advanceRootTo(1.2)
	driven:seek({ timePosition = 0.5 }, "skip" :: AddressMode)
	Harness.assertEqual(driven:getStatus(), "playing")
	Harness.assertNear(driven:getPosition().timePosition, 0.5)
	Harness.assertEqual(eventHits, 0)
	Harness.assertEqual(clock:getTaskCount(), 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 1)

	clock:evaluatePhase(PHASE)
	Harness.assertNear(driven:getPosition().timePosition, 0.5)
	Harness.assertEqual(eventHits, 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	Harness.assertEqual(clock:getTaskCount(), 1)

	clock:stepRootTo(1.45, PHASE)
	Harness.assertEqual(eventHits, 1)
	Harness.assertNear(driven:getPosition().timePosition, 0.75)
	Harness.assertEqual(clock:getTaskCount(), 1)
	driven:cancel()
end)

Harness.test("repeated driven pause and callback resume cycles remain scheduled", function()
	local clock = FakeClock.new()
	local driven = createDriven(clock, {
		duration = 2,
		events = {
			{ time = 1.5, run = function() end },
		},
		onAddress = function(control, info)
			if info.cause == "seek" then
				control:resume()
			end
		end,
	}, "skip" :: "skip")
	driven:play()

	for cycle = 1, 2 do
		driven:pause()
		clock:advanceRootTo(cycle)
		driven:seek({ timePosition = cycle * 0.1 }, "skip" :: AddressMode)
		Harness.assertEqual(driven:getStatus(), "playing")
		Harness.assertEqual(clock:getTaskCount(), 0)
		Harness.assertEqual(clock:getPhaseBindingCount(), 1)
		clock:evaluatePhase(PHASE)
		Harness.assertEqual(clock:getTaskCount(), 1)
		Harness.assertEqual(clock:getPhaseBindingCount(), 0)
	end
	driven:cancel()
end)

Harness.test("driven external mutations reconcile the current sample before mutating core", function()
	local clock = FakeClock.new()
	local hits = 0
	local driven, core = createDriven(clock, {
		duration = 2,
		events = {
			{
				time = 0.5,
				run = function()
					hits += 1
				end,
			},
		},
	}, "skip")
	driven:play()
	clock:advanceRootTo(0.4)
	driven:pause()
	Harness.assertNear(core:getPosition().timePosition, 0.4)
	clock:advanceRootTo(2)
	driven:resume()
	Harness.assertNear(core:getPosition().timePosition, 0.4)
	clock:stepRootTo(2.1, PHASE)
	Harness.assertEqual(hits, 1)
	Harness.assertNear(core:getPosition().timePosition, 0.5)
end)

Harness.test("continuous rate change catches up to the old boundary before reanchoring", function()
	local clock = FakeClock.new()
	local order: { string } = {}
	local sampledRates: { number } = {}
	local driven = createDriven(clock, {
		duration = 2,
		events = {
			{
				time = 0.5,
				run = function()
					table.insert(order, "half")
				end,
			},
			{
				time = 0.9,
				run = function()
					table.insert(order, "nine")
				end,
			},
		},
		samples = {
			{
				run = function(_playback, sample)
					table.insert(sampledRates, sample.rate)
				end,
			},
		},
	}, "skip")
	driven:play()
	clock:advanceRootTo(0.6)
	clock:setRate(2)
	Harness.assertArrayEqual(order, { "half" })
	Harness.assertNear(driven:getPosition().timePosition, 0.6)
	Harness.assertEqual(sampledRates[#sampledRates], 2)
	clock:stepRootTo(0.75, PHASE)
	Harness.assertArrayEqual(order, { "half", "nine" })
end)

Harness.test("driver discontinuity mode explicitly selects skip reconstruct or cancellation", function()
	local runs = 0
	local addressReports: { string } = {}
	local sequence = Pulse.sequence({
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function()
					runs += 1
				end,
			},
		},
		onAddress = function(_playback, info)
			table.insert(addressReports, `{info.cause}:{info.mode}`)
		end,
	})

	local skipClock = FakeClock.new()
	local skipDriver = driverFor(skipClock)
	local skip = skipDriver:attach(Pulse.playback(sequence, nil), { discontinuityMode = "skip" })
	skip:play()
	skipClock:jumpTo(0.75)
	Harness.assertEqual(runs, 0)
	Harness.assertNear(skip:getPosition().timePosition, 0.75)
	Harness.assertEqual(addressReports[#addressReports], "seek:skip")

	local reconstructClock = FakeClock.new()
	local reconstructDriver = driverFor(reconstructClock)
	local reconstruct = reconstructDriver:attach(Pulse.playback(sequence, nil), {
		discontinuityMode = "reconstruct",
	})
	reconstruct:play()
	reconstructClock:jumpTo(0.75)
	Harness.assertEqual(runs, 1)
	Harness.assertEqual(addressReports[#addressReports], "seek:reconstruct")

	local cancelClock = FakeClock.new()
	local cancelDriver = driverFor(cancelClock)
	local cancel = cancelDriver:attach(Pulse.playback(sequence, nil), { discontinuityMode = "cancel" })
	cancel:play()
	cancelClock:jumpTo(0.75)
	Harness.assertEqual((cancel:getCompletion() :: Completion).status, "cancelled")
	Harness.assertEqual((cancel:getCompletion() :: Completion).reason, "clockDiscontinuity")
end)

Harness.test("stale reached delivery revalidates after an immediate discontinuity", function()
	local clock = FakeClock.new()
	local hits = 0
	local driven = createDriven(clock, {
		duration = 1,
		events = {
			{
				time = 0.5,
				run = function()
					hits += 1
				end,
			},
		},
	}, "skip")
	driven:play()
	clock:setBeforeNextReached(function()
		clock:jumpTo(0)
	end)
	clock:stepRootTo(0.5, PHASE)
	Harness.assertEqual(hits, 1)
	Harness.assertNear(driven:getPosition().timePosition, 0)
end)

Harness.test("clock mutation during an authored callback is serialized", function()
	local clock = FakeClock.new()
	local order: { string } = {}
	local driven = createDriven(clock, {
		duration = 1,
		events = {
			{
				time = 0.25,
				run = function()
					table.insert(order, "quarter")
					clock:jumpTo(0.75)
				end,
			},
			{
				time = 0.5,
				run = function()
					table.insert(order, "half")
				end,
			},
		},
		onAddress = function(_playback, info)
			if info.cause == "seek" then
				table.insert(order, "address")
			end
		end,
	}, "skip")
	driven:play()
	clock:stepRootTo(0.25, PHASE)
	Harness.assertArrayEqual(order, { "quarter", "address" })
	Harness.assertNear(driven:getPosition().timePosition, 0.75)
end)

Harness.test("phase fanout safely skips a sibling after unsupported attached-raw cancellation", function()
	local clock = FakeClock.new()
	local driver = driverFor(clock)
	local secondCore: Playback
	local secondSamples = 0
	local firstCore = Pulse.playback(
		Pulse.sequence({
			duration = 1,
			samples = {
				{
					run = function(_playback, sample)
						if sample.position.timePosition > 0 then
							-- Defensive coverage only: production hosts must cancel through DrivenPlayback while attached.
							secondCore:cancel("removed")
						end
					end,
				},
			},
		}),
		nil
	)
	secondCore = Pulse.playback(
		Pulse.sequence({
			duration = 1,
			samples = {
				{
					run = function()
						secondSamples += 1
					end,
				},
			},
		}),
		nil
	)
	local first = driver:attach(firstCore, { discontinuityMode = "skip" })
	local second = driver:attach(secondCore, { discontinuityMode = "skip" })
	first:play()
	second:play()
	Harness.assertEqual(secondSamples, 1)
	clock:stepRootTo(0.25, PHASE)
	Harness.assertEqual(secondSamples, 1)
	Harness.assertEqual((second:getCompletion() :: Completion).reason, "removed")
	first:cancel()
end)

Harness.test("phase fanout defers a playback added during dispatch", function()
	local clock = FakeClock.new()
	local driver = driverFor(clock)
	local introduced = false
	local newcomerSamples = 0
	local newcomer: DrivenPlayback? = nil
	local first = driver:attach(
		Pulse.playback(
			Pulse.sequence({
				duration = 1,
				samples = {
					{
						run = function(_playback, sample)
							if sample.position.timePosition > 0 and not introduced then
								introduced = true
								local created = driver:attach(
									Pulse.playback(
										Pulse.sequence({
											duration = 1,
											samples = {
												{
													run = function()
														newcomerSamples += 1
													end,
												},
											},
										}),
										nil
									),
									{ discontinuityMode = "skip" }
								)
								newcomer = created
								created:play()
							end
						end,
					},
				},
			}),
			nil
		),
		{ discontinuityMode = "skip" }
	)
	first:play()
	clock:stepRootTo(0.25, PHASE)
	Harness.assertTrue(newcomer ~= nil)
	Harness.assertEqual(newcomerSamples, 1)
	clock:stepRootTo(0.5, PHASE)
	Harness.assertEqual(newcomerSamples, 2)
	first:cancel()
	local created = assert(newcomer, "newcomer should exist")
	created:cancel()
end)

Harness.test("large multi-loop phase movement samples only the final position once", function()
	local clock = FakeClock.new()
	local eventRuns = 0
	local sampleRuns = 0
	local driven = createDriven(clock, {
		duration = 1,
		loop = true,
		events = {
			{
				time = 0.25,
				run = function()
					eventRuns += 1
				end,
			},
		},
		samples = {
			{
				run = function()
					sampleRuns += 1
				end,
			},
		},
	}, "skip")
	driven:play()
	eventRuns = 0
	sampleRuns = 0
	clock:advanceRootTo(3.5)
	clock:evaluatePhase(PHASE)
	Harness.assertEqual(eventRuns, 4)
	Harness.assertEqual(sampleRuns, 1)
	Harness.assertEqual(driven:getPosition().loopIndex, 3)
	Harness.assertNear(driven:getPosition().timePosition, 0.5)
	driven:cancel()
end)

Harness.test("driver does not filter provider notifications by external revision metadata", function()
	local clock = FakeClock.new()
	local rates: { number } = {}
	local driven = createDriven(clock, {
		duration = 1,
		samples = {
			{
				run = function(_playback, sample)
					table.insert(rates, sample.rate)
				end,
			},
		},
	}, "skip")
	driven:play()
	clock:setRevisionForTest(100)
	clock:setRate(2)
	clock:setRevisionForTest(0)
	clock:setRate(3)
	Harness.assertEqual(rates[#rates], 3)
	driven:cancel()
end)

Harness.test("driven cleanup registration reconciles the current provider coordinate", function()
	local clock = FakeClock.new()
	local driven, core = createDriven(clock, { duration = 2 }, "skip")
	local cleanupPosition = -1
	driven:play()
	clock:advanceRootTo(0.4)
	driven:addCleanup(function()
		cleanupPosition = core:getPosition().timePosition
	end)
	Harness.assertNear(core:getPosition().timePosition, 0.4)
	driven:cancel()
	Harness.assertNear(cleanupPosition, 0.4)
end)

Harness.test("one raw playback has at most one clock driver attachment", function()
	local firstClock = FakeClock.new()
	local secondClock = FakeClock.new()
	local firstDriver = driverFor(firstClock)
	local secondDriver = driverFor(secondClock)
	local raw = Pulse.playback(Pulse.sequence({ duration = 1 }), nil)
	local first = firstDriver:attach(raw, { discontinuityMode = "skip" })
	Harness.assertThrows(function()
		secondDriver:attach(raw, { discontinuityMode = "reconstruct" })
	end, "already attached")
	Harness.assertEqual(first:detach(), raw)
	local second = secondDriver:attach(raw, { discontinuityMode = "skip" })
	second:play()
	second:cancel()
	firstDriver:destroy()
	secondDriver:destroy()
	Harness.assertFalse(firstClock:isDestroyed())
	Harness.assertFalse(secondClock:isDestroyed())
end)

Harness.test("detaching reconciles once and leaves a usable raw playback", function()
	local clock = FakeClock.new()
	local driven, core = createDriven(clock, { duration = 2 }, "skip")
	driven:play()
	clock:advanceRootTo(0.3)
	local detached = driven:detach()
	Harness.assertEqual(detached, core)
	Harness.assertNear(core:getPosition().timePosition, 0.3)
	Harness.assertEqual(clock:getTaskCount(), 0)
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
	Harness.assertFalse(clock:isDestroyed())
	core:evaluate({ position = 0.5, rate = 1 })
	Harness.assertNear(core:getPosition().timePosition, 0.5)
	core:cancel()
end)

Harness.test("driver and provider teardown terminate attachments without destroying a borrowed clock", function()
	local clock = FakeClock.new()
	local driven, _core, driver = createDriven(clock, {
		duration = 2,
		samples = {
			{ run = function() end },
		},
	}, "skip")
	driven:play()
	driver:destroy()
	Harness.assertEqual((driven:getCompletion() :: Completion).status, "failed")
	Harness.assertEqual((driven:getCompletion() :: Completion).reason, "driverDestroyed")
	Harness.assertFalse(clock:isDestroyed())
	Harness.assertEqual(clock:getTaskCount(), 0)
	Harness.assertEqual(clock:getChangedBindingCount(), 0)
	Harness.assertEqual(clock:getPhaseBindingCount(), 0)

	local providerClock = FakeClock.new()
	local providerDriven, _providerCore, providerDriver = createDriven(providerClock, { duration = 2 }, "skip")
	providerDriven:play()
	providerClock:destroy()
	Harness.assertTrue(providerDriver:isDestroyed())
	Harness.assertEqual((providerDriven:getCompletion() :: Completion).reason, "clockDestroyed")
end)
