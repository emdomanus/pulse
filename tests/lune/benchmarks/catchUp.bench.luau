--!strict

local requireAny = require :: any
local process = requireAny("@lune/process")
local FakeClock = requireAny("../lib/fakeClock")

local configured = process.env.PULSE_CATCHUP_BENCH_COUNT
local workCount = if configured == nil then 25_000 else tonumber(configured)
assert(
	workCount ~= nil and workCount > 0 and workCount % 1 == 0,
	"PULSE_CATCHUP_BENCH_COUNT must be a positive integer"
)

local clock = FakeClock.new()
local completed = 0
local id = 0
id = clock:bindToReached(1, clock.directions.forward, function()
	completed += 1
	if completed < workCount then
		assert(clock:rescheduleAt(id, completed + 1, "benchmark"))
	end
end, "benchmark")

local started = os.clock()
clock:stepRootTo(workCount, "benchmark")
local elapsed = os.clock() - started

assert(completed == workCount, `expected {workCount} synchronous callbacks, got {completed}`)
assert(clock:getTaskCount() == 0, "benchmark left scheduled work behind")
print(`Pulse synchronous catch-up profile: {workCount} callbacks in {elapsed} seconds`)
print("This fixture measures a configurable sample; it does not define the runtime catch-up safety limit.")
