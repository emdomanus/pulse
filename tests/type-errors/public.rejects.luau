--!strict
-- selene: allow(incorrect_standard_library_use)
local Pulse = require("../../src")
type Context = { actorId: number }
local function rejects(
	playback: Pulse.Playback,
	sample: Pulse.SampleInfo,
	completion: Pulse.Completion,
	sequence: Pulse.Sequence<Context>
)
	playback.play = playback.play -- EXPECT_ERROR
	sample.rate = 2 -- EXPECT_ERROR
	sample.position.timePosition = 2 -- EXPECT_ERROR
	completion.status = "cancelled" -- EXPECT_ERROR
	playback:seek({ timePosition = 0 }, "replay") -- EXPECT_ERROR
	Pulse.playback(sequence, { actorId = "wrong" }) -- EXPECT_ERROR
end
return rejects
