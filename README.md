# Pulse

Pulse is a small, strictly typed sequence playback runtime for Roblox. It compiles reusable event
and update timelines, then plays them against a borrowed scheduling-capable clock.

Pulse owns sequence-local traversal, playback speed, seeks, looping, cleanup, and lifecycle. The
clock provider owns time and scheduling. VFX, skills, cutscenes, and other consumers own the
meaning and side effects of callbacks.

```luau
local Pulse = require(ReplicatedStorage.packages.pulse)
local Tempo = require(ReplicatedStorage.packages.tempo)

local sequence = Pulse.builder()
	:duration(1.5)
	:event({
		time = 0.2,
		run = function(playback)
			print("hit", playback:getPosition().timePosition)
		end,
	})
	:compile()

local adapter = Pulse.temporalAdapter(clock, runtime.phases.heartbeat, {
	forward = Tempo.Enums.Direction.forward,
	backward = Tempo.Enums.Direction.backward,
})

local playback = Pulse.playback(sequence, adapter)
playback:play()
```

One `TemporalAdapter` may serve many playbacks. Event-only playbacks schedule only their next
boundary. Updating playbacks lazily share the adapter's single phase binding.

## Development

Install the pinned Rokit tools, then use the guarded verification scripts:

```powershell
rokit install
pesde install
.\scripts\verify\tests.ps1
.\scripts\verify\analyze.ps1
.\scripts\verify\stylua.ps1
.\scripts\verify\selene.ps1
npm install
npm run docs:build
```

Start with the [documentation overview](./docs/index.md), the
[getting-started guide](./docs/guides/getting-started.md), or the
[API reference](./docs/api/index.md).
