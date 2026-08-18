--!strict

type RequireUnknown = (path: string) -> unknown
type Event = {
	time: number,
	run: (playback: unknown, context: unknown) -> (),
}
type Sample = {
	startTime: number?,
	endTime: number?,
	run: (playback: unknown, sample: unknown, context: unknown) -> (),
}
type Sequence = {}
type Playback = {
	play: (self: Playback, sample: { position: number, rate: number }) -> Playback,
	evaluate: (self: Playback, sample: { position: number, rate: number }) -> boolean,
	getStatus: (self: Playback) -> string,
}
type DirectionToken = {
	name: "forward" | "backward",
}
type FakeClock = {
	directions: {
		forward: DirectionToken,
		backward: DirectionToken,
	},
	stepRootTo: (self: FakeClock, rootTime: number, phase: string) -> (),
	getReadCount: (self: FakeClock) -> number,
	getRescheduleCount: (self: FakeClock) -> number,
}
type FakeClockModule = {
	new: () -> FakeClock,
}
type DrivenPlayback = {
	play: (self: DrivenPlayback) -> DrivenPlayback,
}
type ClockDriver = {
	attach: (
		self: ClockDriver,
		playback: Playback,
		options: { discontinuityMode: "skip" | "reconstruct" | "cancel" }
	) -> DrivenPlayback,
	destroy: (self: ClockDriver) -> (),
}
type PulseApi = {
	sequence: (definition: { duration: number, events: { Event }?, samples: { Sample }? }) -> Sequence,
	playback: (sequence: Sequence, context: unknown, options: { playbackSpeed: number }?) -> Playback,
	clockDriver: (
		clock: FakeClock,
		phase: string,
		directions: {
			forward: DirectionToken,
			backward: DirectionToken,
		}
	) -> ClockDriver,
}
type TransformHandle = {
	requireModule: (relativePath: string) -> unknown,
	cleanup: () -> (),
}
type TransformModule = {
	write: (options: { packageRoot: string, tempDir: string }) -> TransformHandle,
}

local requireUnknown = (require :: unknown) :: RequireUnknown
local FakeClock = (requireUnknown("../lib/fakeClock") :: unknown) :: FakeClockModule
local Transform = (requireUnknown("../lib/luneRequireTransform") :: unknown) :: TransformModule
local transformed = Transform.write({
	packageRoot = "src",
	tempDir = ".lune-pulse-reconciliation-benchmark",
})
local Pulse = (transformed.requireModule("init.luau") :: unknown) :: PulseApi
transformed.cleanup()

local PHASE = "simulation"

local function profile(workCount: number): number
	local events: { Event } = table.create(workCount)
	local callbacks = 0
	for index = 1, workCount do
		events[index] = {
			time = index,
			run = function()
				callbacks += 1
			end,
		}
	end

	local sequence = Pulse.sequence({
		duration = workCount + 1,
		events = events,
	})
	local playback = Pulse.playback(sequence, nil)
	playback:play({ position = 0, rate = 1 })

	local started = os.clock()
	playback:evaluate({ position = workCount + 1, rate = 1 })
	local elapsed = os.clock() - started
	assert(callbacks == workCount, `expected {workCount} callbacks, got {callbacks}`)
	assert(playback:getStatus() == "completed", "benchmark playback did not complete")
	return elapsed
end

local function profileDriverFanout(attachmentCount: number, tickCount: number, playbackSpeed: number): (number, number)
	local clock = FakeClock.new()
	local driver = Pulse.clockDriver(clock, PHASE, clock.directions)
	local callbacks = 0
	local sequence = Pulse.sequence({
		duration = 10,
		samples = {
			{
				startTime = 0,
				endTime = 10,
				run = function()
					callbacks += 1
				end,
			},
		},
	})
	for _ = 1, attachmentCount do
		local driven = driver:attach(Pulse.playback(sequence, nil, { playbackSpeed = playbackSpeed }), {
			discontinuityMode = "skip" :: "skip",
		})
		driven:play()
	end

	local readsBefore = clock:getReadCount()
	local reschedulesBefore = clock:getRescheduleCount()
	local started = os.clock()
	for tick = 1, tickCount do
		clock:stepRootTo(tick / (tickCount + 1), PHASE)
	end
	local elapsed = os.clock() - started
	local reads = clock:getReadCount() - readsBefore
	local reschedules = clock:getRescheduleCount() - reschedulesBefore
	assert(
		callbacks == attachmentCount * (tickCount + 1),
		`expected {attachmentCount * (tickCount + 1)} Sample callbacks, got {callbacks}`
	)
	assert(reads == tickCount, `expected {tickCount} shared phase reads, got {reads}`)
	assert(reschedules == 0, `expected no unchanged-deadline reschedules, got {reschedules}`)
	driver:destroy()
	return elapsed, callbacks
end

for _, workCount in { 512, 1_024, 2_048, 4_096 } do
	local samples: { number } = table.create(5)
	for run = 1, 5 do
		samples[run] = profile(workCount)
	end
	table.sort(samples)
	local minimum = samples[1]
	local median = samples[3]
	local maximum = samples[5]
	local throughput = workCount / median
	print(
		`Pulse core evaluation profile: {workCount} occurrences, {median} second median ({minimum}-{maximum}; {throughput} occurrences/s)`
	)
end

print("Pulse reconciliation safety limit: 4096 committed callbacks or loop boundaries per evaluation")

for _, playbackSpeed in { 1, 1.3 } do
	local driverElapsed, driverCallbacks = profileDriverFanout(64, 128, playbackSpeed)
	print(
		`Pulse driver phase fanout profile at {playbackSpeed}x: {driverCallbacks} Sample callbacks in {driverElapsed} seconds (128 shared reads; 0 unchanged-deadline reschedules)`
	)
end
