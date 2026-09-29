--!strict
-- selene: allow(incorrect_standard_library_use)
local Pulse = require("../../src")
type Context = { actorId: number }
local function legacySample(_playback: Pulse.PlaybackControl, _position: { timePosition: number }) end
local function rejects(
	playback: Pulse.Playback,
	address: Pulse.AddressInfo,
	completion: Pulse.Completion,
	sequence: Pulse.Sequence<Context>
)
	playback.play = playback.play -- EXPECT_ERROR
	address.mode = "skip" -- EXPECT_ERROR
	address.target.timePosition = 2 -- EXPECT_ERROR
	completion.status = "cancelled" -- EXPECT_ERROR
	playback:seek({ timePosition = 0 }, "replay") -- EXPECT_ERROR
	Pulse.playback(sequence, { actorId = "wrong" }) -- EXPECT_ERROR
	local sample: Pulse.Sample<Context> = { run = legacySample } -- EXPECT_ERROR
	return sample
end
return rejects
