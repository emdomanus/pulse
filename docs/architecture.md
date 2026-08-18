# Architecture

The dependency direction is deliberately one-way:

```text
SequenceDefinition<ContextT> -> compiler -> immutable Sequence<ContextT>
                                                   |
host TimeSample ------------------------------> raw Playback -> callbacks
                                                   ^
ProviderClock -> optional ClockDriver --------------|
```

The raw core never requires a clock-driver type. `ClockDriver` depends on and drives `Playback`.

## Ownership

| Role | Owns | Does not own |
| --- | --- | --- |
| `Sequence<ContextT>` | Validated immutable events, samples, loop setting, and authored hooks | Invocation context, address mode, clock state, cursor, or lifecycle |
| Raw `Playback` | Context, source/sequence anchor, local speed, traversal cursor and provenance, loop identity, explicit addressing, cleanup generations, completion, callback serialization | Clock reads, scheduling, discontinuity records, revision policy, or wall time |
| Optional `ClockDriver` | Provider validation/reads, changed subscription, previous/current boundary reconciliation, reached deadlines, shared phase fan-out, stale-task protection, attachment discontinuity mode | The borrowed clock, Sequence policy, host domain meaning, or side effects |
| Host | Source samples or provider selection, traversal-versus-address meaning, discontinuity response, materialization policy, context, real frame delta, and side effects | Pulse traversal internals |

Destroying a driver fails its attached live Playbacks with `driverDestroyed`; provider destruction
fails them with `clockDestroyed`. In both cases the provider is borrowed and is never destroyed by
Pulse. Destroying or detaching one attachment releases only its own scheduling membership.

`ClockDriver:attach(raw, ...)` transfers exclusive temporal-control ownership to the returned
`DrivenPlayback` until `detach()`. The raw reference remains structurally callable, but the host
must not mutate it while attached because doing so bypasses driven reconciliation and scheduling
refresh. Detach returns temporal-control ownership together with the still-live raw Playback.

## Raw time and anchors

The core derives a target from the last accepted anchor:

```text
sequencePosition =
    anchorSequence
    + (sample.position - anchorSource) * playbackSpeed
```

`TimeSample.position` already contains source movement, so `TimeSample.rate` is never multiplied
into that displacement. Rate is an atomic description of the source at the sampled coordinate. A
sampler receives `sample.rate * playbackSpeed`, which may be negative or zero.

Core state changes only through `play(sample)`, `evaluate(sample)`, or explicit Playback controls.
`getPosition()` returns the last accepted cursor and never reads or projects implicit time.
At an explicitly addressed duration-side loop join, the exact identity remains visible until a
future forward evaluation consumes the loop crossing and next-cycle zero boundary.

### Mutation timestamps

Pause, speed, seek, cancel, and destroy act at the Playback's currently accepted evaluated
coordinate. A raw host that needs a mutation at a newer coordinate must call `evaluate` first.
The driven facade performs that current provider read/evaluation before external mutations while
playing. Resume is special: the first subsequent sample re-anchors the stored paused position, so
source movement during the pause is not traversed.

## Traversal and sampling

Natural evaluation traverses every crossed discrete boundary exactly once. Equal-time events run
in authored order forward and reverse authored order backward. Loop joins preserve exact identity:
`{ timePosition = duration, loopIndex = n }` and `{ timePosition = 0, loopIndex = n + 1 }` share an
unwrapped coordinate but remain distinct boundary positions.

After all crossed events and loop hooks, each authored `Sample` active at the final local position
runs once. Sample intervals use `[startTime, endTime)` in both traversal directions. A large or
multi-loop jump therefore traverses historical events but does not manufacture historical sampler
ticks. An equal-coordinate evaluation emits no event again and may sample active state once.

Pulse supplies no real frame delta. A particle, mesh, physics, or other accumulator backend must
receive its backend tick from the host outside Pulse.

## Explicit addressing and materialization

Address behavior belongs to each invocation:

| Mode | Historical events | Cleanup generation |
| --- | --- | --- |
| `skip` | Suppressed, including events exactly at the target | Retained; initial placement opens the first generation |
| `reconstruct` | Canonically replayed forward from local zero of the target loop | Opened initially or replaces the current generation |

Cancellation is `Playback:cancel(reason?)`, not an address mode. The same Sequence can be skipped
by one call and reconstructed by another.

Address ordering is fixed:

1. establish or reconstruct the exact target;
2. call `onAddress` with cause `initial` or `seek`;
3. call each active absolute sampler once at the target;
4. establish future traversal provenance (and let an optional driver refresh scheduling).

`onAddress` is the late-materialization seam for host-owned resources, leases, pools, or curve
state at an arbitrary elapsed position. It does not expose provider-change metadata.

## Callback, cleanup, and failure invariants

`Event.run` handles forward traversal; `Event.reverse`, when present, handles backward traversal.
Pulse reverses its cursor, not arbitrary authored side effects. One typed context is retained per
Playback and passed to every authored callback.

`Playback:addCleanup` belongs to the current generation. Reconstruction flushes the replaced
generation in reverse registration order before setup/replay; terminal completion flushes the
remaining generation the same way. Cleanup is not per-event undo.

Same-Playback nonterminal mutations requested inside callbacks are serialized. A terminal request
interrupts remaining equal-time work. Callback and cleanup failures yield one immutable failed
Completion. Catch-up and numeric precision limits fail deterministically rather than silently
dropping authored events.

While a Playback is driven, an authored callback may use its `PlaybackControl` synchronously. Those
calls enter the raw Playback's operation queue and the driver refreshes after the enclosing
evaluation. The callback capability must not be retained and invoked asynchronously while the raw
Playback remains attached; asynchronous control belongs through `DrivenPlayback`.

## Optional driver scheduling

An attachment owns one next-boundary reached task. Attachments share one phase binding per driver
whenever phase evaluation is required: an exact Sample is active, backward movement is poised at
an excluded Sample `endTime`, an outward-matching zero-distance loop join is pending, or a
synchronous callback-side `PlaybackControl:resume()` is awaiting its first post-resume sample. The
excluded endpoint itself still emits no Sample. A pending join retains exact addressed identity
through stationary notifications and is consumed only by actual source-coordinate movement. The
first subsequent phase evaluation clears a pending resume without catch-up; an event-only
attachment then releases phase ownership and schedules its next deadline. Event and completion
boundaries stay schedulable outside these transient states.

Each attachment records its scheduled absolute source coordinate and direction. A phase
notification supplies one shared provider sample to every member; if an attachment's forecast is
unchanged or differs only by bounded binary64 rounding, refresh keeps both the existing task and
its original cached coordinate without another provider read or `rescheduleAt`. Reached checks use
that cached coordinate because it is where the provider task is bound. Only new or materially
changed deadlines receive a post-schedule read, so source movement during the scheduling call
cannot skip a boundary.

For a continuous provider mapping change, the driver reconciles the delivered previous boundary
before using the new rate. For a reported discontinuity it first reconciles natural elapsed motion
through the previous boundary, then applies the attachment's required `skip`, `reconstruct`, or
`cancel` response without traversing the jump. Notifications are serialized internally; external
provider revisions are neither required nor filtered.

The accepted ownership correction and its relationship to the earlier clock-driven design are
recorded in the [Absolute-Time Core Amendment](./todo/absoluteTimeCoreAmendment.md).
