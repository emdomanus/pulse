# Tempo Integration

A current Tempo `Clock` structurally satisfies Pulse's optional provider contract. Pulse has no
Tempo package dependency and does not accept a Tempo runtime or service object; the composition
root supplies the clock, phase, and direction tokens.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pulse = require(ReplicatedStorage.packages.pulse)
local Tempo = require(ReplicatedStorage.packages.tempo)

local driver = Pulse.clockDriver(clock, runtime.phases.heartbeat, {
	forward = Tempo.Enums.Direction.forward,
	backward = Tempo.Enums.Direction.backward,
})
```

## Select the phase explicitly

Do not depend on a clock's default scheduling phase. The host injects the phase on which authored
Pulse callbacks may run. A presentation integration can choose its presentation phase; another
consumer may choose heartbeat.

## Share the driver

```luau
local rawHit = Pulse.playback(hitSequence, hitContext)
local rawTrail = Pulse.playback(trailSequence, trailContext)

local hit = driver:attach(rawHit, { discontinuityMode = "skip" })
local trail = driver:attach(rawTrail, { discontinuityMode = "reconstruct" })

hit:play()
trail:play()
```

Attachment transfers exclusive temporal-control ownership to `hit` and `trail`; do not mutate
`rawHit` or `rawTrail` until the corresponding facade is detached. The event-only hit ordinarily
schedules only its next deadline. An event-only pending loop join temporarily needs phase
observation, as does backward entry poised at an excluded Sample end. The trail and any other
phase-required attachments share one Tempo phase binding rather than binding independently.

The two attachments may select different discontinuity responses even when their Sequences are
identical. This is an invocation/host decision, not reusable authored content.

## Clock changes

Tempo rate changes are continuous mapping changes. ClockDriver catches up through the delivered
previous position boundary before accepting current position/rate and refreshing scheduling.

Tempo seeks or hydration jumps are reported discontinuities. ClockDriver first reconciles natural
elapsed movement through the delivered previous boundary, then translates the position jump to the
attachment's explicit response:

| Mode | Result |
| --- | --- |
| `skip` | Establish the derived target without traversing events in the jump |
| `reconstruct` | Replace cleanup state and replay canonical forward history to the target |
| `cancel` | Cancel with reason `clockDiscontinuity` |

`onAddress` receives the generic core cause `seek` after `skip` or `reconstruct`; raw core callbacks
do not receive Tempo change records. Extra provider metadata, including revisions, is ignored.
Driver notification serialization supplies ordering.

## Mutation timing

Calling a driven control such as `pause`, `setPlaybackSpeed`, or `seek` while playing causes one
current Tempo read/evaluation before the mutation. This gives the operation an exact provider
coordinate without making the raw core clock-aware. Read-only methods do not advance time.

An authored callback's `PlaybackControl` is valid for synchronous callback control through the raw
operation queue. Do not retain and invoke it asynchronously while attached; later control goes
through the driven facade so ClockDriver can reconcile and refresh scheduling.

The Tempo Clock and runtime remain host-owned. `ClockDriver:destroy()` releases Pulse's changed
subscription, phase binding, reached tasks, and attachments but never destroys the clock.
