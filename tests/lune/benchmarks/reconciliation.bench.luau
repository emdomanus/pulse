--!strict

local requireAny = require :: any
local FakeClock = requireAny("../lib/fakeClock")
local Transform = requireAny("../lib/luneRequireTransform")

local transformedPackage = Transform.write({
	packageRoot = "src",
	tempDir = "tests/lune/.tmp/pulse-reconciliation-benchmark",
})
local Pulse = transformedPackage.requireModule("pulse/init.luau") :: any
transformedPackage.cleanup()

local function profile(workCount: number): number
	local events = table.create(workCount)
	local callbacks = 0
	for index = 1, workCount do
		events[index] = {
			time = index,
			run = function()
				callbacks += 1
			end,
			reverse = "ignore",
		}
	end

	local clock = FakeClock.new()
	local runtime = Pulse.new()
	local sequence = Pulse.sequence({
		duration = workCount + 1,
		events = events,
	})
	local playback = runtime:createPlayback(sequence, {
		clock = clock,
		directions = clock.directions,
		phase = "benchmark",
	})
	playback:play()

	local started = os.clock()
	clock:stepRootTo(workCount + 1, "benchmark")
	local elapsed = os.clock() - started
	assert(callbacks == workCount, `expected {workCount} callbacks, got {callbacks}`)
	assert(playback:getStatus() == "completed", "benchmark playback did not complete")
	assert(clock:getTaskCount() == 0, "benchmark left scheduled work behind")
	runtime:destroy()
	return elapsed
end

for _, workCount in { 512, 1_024, 2_048, 4_096 } do
	local samples = table.create(5)
	for run = 1, 5 do
		samples[run] = profile(workCount)
	end
	table.sort(samples)
	local minimum = samples[1]
	local median = samples[3]
	local maximum = samples[5]
	local throughput = workCount / median
	print(
		`Pulse reconciliation profile: {workCount} occurrences, {median} second median ({minimum}-{maximum}; {throughput} occurrences/s)`
	)
end

print("Pulse M1 reconciliation safety limit: 4096 committed occurrences or loop boundaries per reconcile")
