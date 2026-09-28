# Tempo Integration

Modern Tempo separates clock state from scheduling bindings and delivers argument-free change
invalidations. Pulse's optional provider contract still consumes a change record. The host supplies
a small adapter; neither Pulse nor the adapter owns or destroys the borrowed clock. Pulse keeps no
Tempo package dependency.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pulse = require(ReplicatedStorage.packages.pulse)
local Tempo = require(ReplicatedStorage.packages.tempo)

type Phase = "heartbeat"
local function tempoProvider(clock: Tempo.Clock<Phase>): Pulse.ProviderClock<Phase, Tempo.Direction>
    local initialMapping = clock:getMapping()
    return {
        read = function() return clock:read() end,
        isDestroyed = function() return clock:isDestroyed() end,
        bindToChanged = function(_, callback, runInitially)
            return clock:bindToChanged(function()
                -- Each dispatch owns its record, including reentrant changes.
                local change: Tempo.ClockChange = {
                    kind = "mapping", current = initialMapping,
                    currentTimePosition = 0, currentParentTimePosition = 0,
                    discontinuous = false,
                }
                clock:readChangeInto(change)
                callback(change)
            end, runInitially)
        end,
        bindToReached = function(_, position, direction, callback, phase)
            return clock:bindToReached(position, direction, callback, phase)
        end,
        cancel = function(_, id) return clock:cancel(id) end,
        rescheduleAt = function(_, id, position, phase)
            return clock:rescheduleAt(id, position, phase)
        end,
        bindPhase = function(_, phase, callback) return clock:bindPhase(phase, callback) end,
    }
end

-- The host creates state with runtime:createClock(), then runtime:bindClock(state.reader).
local provider = tempoProvider(clock)
local driver = Pulse.clockDriver(provider, "heartbeat" :: Phase, {
    forward = Tempo.Enums.Direction.forward,
    backward = Tempo.Enums.Direction.backward,
})
```

A provider that already delivers records can forward its callback directly. Bind concrete provider
methods in this adapter rather than casting a provider with a different recursive `self` type to
`ProviderClock`. This preserves the solver's checks on phase, direction, and callback contracts.

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

The Tempo Clock and runtime remain host-owned. `ClockDriver:deconstruct()` releases Pulse's changed
subscription, phase binding, reached tasks, and attachments but never destroys the clock.
