--!strict

type RequireUnknown = (path: string) -> unknown
type HarnessApi = {
	run: () -> (),
}

local requireUnknown = (require :: unknown) :: RequireUnknown
local Harness = (requireUnknown("./lib/testHarness") :: unknown) :: HarnessApi

requireUnknown("./specs/playback.spec")
Harness.run()
