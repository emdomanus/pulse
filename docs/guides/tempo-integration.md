# Tempo Integration

A current Tempo `Clock` structurally satisfies Pulse's provider contract. Pulse does not accept a
Tempo runtime or service object; the composition root supplies the clock, phase, and direction
tokens.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pulse = require(ReplicatedStorage.packages.pulse)
local Tempo = require(ReplicatedStorage.packages.tempo)

local adapter = Pulse.temporalAdapter(clock, runtime.phases.heartbeat, {
	forward = Tempo.Enums.Direction.forward,
	backward = Tempo.Enums.Direction.backward,
})
```

## Select the phase explicitly

Do not depend on a clock's default scheduling phase. The host should inject the phase on which
Pulse may run authored callbacks. A presentation integration can choose its presentation phase;
another standalone consumer may choose heartbeat.

## Share the adapter

```luau
local hit = Pulse.playback(hitSequence, adapter)
local trail = Pulse.playback(trailSequence, adapter)

hit:play()
trail:play()
```

The event-only hit schedules its next deadline and creates no phase binding. The trail joins the
adapter's shared phase binding only while its update interval needs continuous work. Additional
updating playbacks on the same adapter do not bind the Tempo phase independently.

## Clock changes

Tempo rate changes are continuous mapping changes: Pulse reconciles to the change boundary,
preserves playback position, and reschedules. Tempo seeks or hydration jumps are discontinuities:
Pulse applies the Sequence's `skip`, `rebuild`, or `cancel` address policy.

The Tempo clock and runtime remain host-owned. Destroying a Pulse adapter only releases Pulse's
changed subscription, phase binding, scheduled tasks, and attached playbacks.
