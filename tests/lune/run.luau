--!strict

local requireAny = require :: any
local Harness = requireAny("./lib/testHarness")

requireAny("./specs/compiler.spec")
requireAny("./specs/fakeClock.spec")
requireAny("./specs/fakeRealTimeScheduler.spec")

Harness.run()
