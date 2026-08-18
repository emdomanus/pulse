# Pulse

Pulse is a small, strictly typed absolute-time sequence runtime for Roblox. It compiles reusable
event and sampled timelines, then evaluates them from finite source samples supplied by a host.
The core has no clock, scheduler, frame loop, or discontinuity policy.

Pulse owns sequence-local anchors, playback speed, ordered event traversal, reverse callbacks,
loop identity, explicit addressing, cleanup generations, and lifecycle. Hosts own the meaning of
time and presentation side effects. An optional `ClockDriver` adapts scheduling-capable clocks to
the same raw core.

## Raw host-driven playback

```luau
local Pulse = require(ReplicatedStorage.packages.pulse)

type HitContext = {
	worldPosition: Vector3,
}

local builder: Pulse.Builder<HitContext> = Pulse.builder()
local sequence = builder
	:duration(1.5)
	:event({
		time = 0.2,
		run = function(playback, context)
			print("hit", context.worldPosition, playback:getPosition().timePosition)
		end,
	})
	:sample({
		startTime = 0.2,
		endTime = 1.0,
		run = function(_playback, sample, _context)
			-- Absolute sampled state; no dt accumulation.
			print(sample.position.timePosition, sample.rate)
		end,
	})
	:compile()

local playback = Pulse.playback(sequence, {
	worldPosition = targetPosition,
})

playback:play({ position = 100, rate = 1 })
playback:evaluate({ position = 100.5, rate = 1 })
playback:evaluate({ position = 101, rate = 1 })
```

`TimeSample.position` is an absolute source coordinate. Pulse maps its displacement through
`playbackSpeed`; it never multiplies displacement by `TimeSample.rate`. The rate is atomic metadata
used for direction and reported to active samplers after local speed is applied.

## Optional clock-driven playback

```luau
local Tempo = require(ReplicatedStorage.packages.tempo)

local driver = Pulse.clockDriver(clock, runtime.phases.heartbeat, {
	forward = Tempo.Enums.Direction.forward,
	backward = Tempo.Enums.Direction.backward,
})

local raw = Pulse.playback(sequence, {
	worldPosition = targetPosition,
})
local driven = driver:attach(raw, {
	discontinuityMode = "reconstruct",
})

driven:play()
```

`attach` transfers exclusive temporal-control ownership to `driven` until `driven:detach()`; do not
mutate `raw` while it is attached. One driver may serve many playbacks. Attachments lazily share
one phase binding while an exact Sample is active, reverse movement is poised to enter a Sample at
its excluded end, or an outward zero-distance loop join awaits actual source movement. Ordinary
event-only playback keeps only one next-boundary deadline. The attachment must explicitly select
`"skip"`, `"reconstruct"`, or `"cancel"` for provider discontinuities; reusable Sequences contain
no such decision.

For late materialization, choose `initialMode = "skip"` and use `onAddress` to establish host-owned
resources at the exact addressed position without replaying historical one-shot events.

Pulse has no package dependency on Tempo. A Tempo Clock is one structural provider; any
scheduling-capable clock satisfying `ProviderClock` may be injected. Destroying a driver never
destroys its borrowed clock.

## Development

Install the pinned Rokit tools, then use the guarded verification scripts:

```powershell
rokit install
pesde install
.\scripts\verify\tests.ps1
.\scripts\verify\analyze.ps1
.\scripts\verify\stylua.ps1
.\scripts\verify\selene.ps1
.\scripts\verify\benchmark.ps1
npm install
npm run docs:build
```

Start with the [documentation overview](./docs/index.md), the
[getting-started guide](./docs/guides/getting-started.md), or the
[API reference](./docs/api/index.md).
