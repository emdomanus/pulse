# Absolute-Time Core Amendment

Status: accepted and implemented

Date: 2026-08-17

## Relationship to the temporal scheduling amendment

This record supersedes the public ownership and API decisions in
[`temporalSchedulingAmendment.md`](./temporalSchedulingAmendment.md) that made a scheduling adapter
mandatory, stored discontinuity policy in a reusable Sequence, and defined accumulator-style
continuous callbacks. The earlier document remains unchanged as historical context for the
clock-driven design that existed before this correction.

The earlier traversal, lifecycle, ordering, cleanup, failure, and scheduling-efficiency goals are
retained where they describe genuine Pulse behavior. This amendment changes which layer owns time
and discontinuity choices.

## Context

The previous public construction shape coupled every Playback to a clock adapter. A Sequence
compiled one address policy that was consulted both for manual seeks and provider discontinuities.
Continuous callbacks received signed overlap deltas and could run once for each crossed loop.

Those choices mixed three concerns:

1. reusable authored sequence content;
2. stateful absolute event traversal;
3. a particular provider clock's scheduling/change protocol.

They also made host reconciliation choices immutable authoring data. Late streaming, prediction,
and presentation composition need to choose those behaviors per invocation and per change, not per
Sequence.

## Decision

Pulse is split into a raw absolute-time core and an optional clock-driving layer.

```text
ProviderClock -> ClockDriver -> raw Playback -> Sequence callbacks
host samples --------------------^  ^
host address/lifecycle controls -----|
```

Dependencies point toward the core. Raw Playback types and implementation do not require or import
ClockDriver, provider-change, revision, scheduling, or discontinuity types.

## Raw core contract

The finite source sample is:

```luau
type TimeSample = {
	position: number,
	rate: number,
}
```

`position` is the absolute source coordinate. `rate` is metadata describing the source rate at
that sample. The sequence target is always:

```text
anchorSequence + (position - anchorSource) * playbackSpeed
```

Rate is not multiplied into position displacement because source movement is already present in
the absolute position. The rate reported to an authored sampler is `rate * playbackSpeed`.

Raw construction and operation are:

```luau
local playback = Pulse.playback(sequence, context, options)
playback:play(initialSample)
playback:evaluate(nextSample)
```

Core position advances only when a sample or explicit address operation is accepted. There is no
implicit clock projection in `getPosition` and no wall-time read.

## Absolute Sample callbacks

The former continuous delta contract is removed rather than aliased. Sequence authoring now uses:

```luau
type SampleInfo = {
	position: PlaybackPosition,
	rate: number,
}
```

Each active Sample runs once at the final position of an evaluation. Intervals are
`[startTime, endTime)` in both directions. Large and multi-loop jumps traverse all discrete Events
but do not create historical Sample calls. Equal-coordinate evaluation can Sample again without
replaying Events.

Pulse does not provide a real frame delta. Simulation backends obtain that from their host tick.

## Explicit address operations

Sequence-owned address policy is removed. The canonical operation is:

```luau
playback:seek(address, "skip")
playback:seek(address, "reconstruct")
```

`skip` establishes the cursor without historical discrete traversal and retains the generation.
`reconstruct` flushes the previous generation LIFO, opens a new generation, and replays canonical
forward history from local zero of the target loop. Initial mode lives in `PlaybackOptions`.

Cancellation is a lifecycle operation, `playback:cancel(reason?)`, and is not an address mode.
One compiled Sequence can therefore be skipped and reconstructed by different calls and
Playbacks.

`onAddress` remains. Its provider-neutral cause is `initial` or `seek`, and its ordering is:

1. establish/reconstruct the target;
2. invoke `onAddress`;
3. invoke active Samples once at the target;
4. prepare future traversal ownership.

This keeps an explicit seam for late host materialization without exposing clock-change metadata.

## Mutation timestamp rule

Raw pause, speed, seek, cancel, and destroy operations act at the Playback's most recently accepted
evaluated coordinate. A host requiring a mutation at a newer coordinate must evaluate that
`TimeSample` first.

Resume marks the Playback pending. Its first subsequent evaluation re-anchors the stored paused
sequence position at the new source coordinate and does not traverse source time elapsed while
paused.

A `DrivenPlayback` performs the needed current provider read/evaluation before an external mutation
while playing. Thus the convenience layer provides exact current-clock semantics without giving
the core an implicit time source.

## Retained core invariants

The split does not remove state needed for deterministic traversal:

- equal-time authored order and mirrored reverse order;
- before/after exact-boundary provenance;
- `Event.reverse` callbacks;
- signed loop identity and unwrapped coordinates;
- distinct duration/next-zero identities at loop joins;
- zero-duration non-looping behavior;
- cleanup generations and LIFO disposal;
- protected callbacks and immutable terminal Completion;
- terminal interruption of remaining equal-time work;
- same-Playback reentrant nonterminal serialization;
- deterministic catch-up and numeric-precision failure rather than silent event loss.

## Optional ClockDriver

ClockDriver owns only provider composition:

- protective provider validation and reads;
- one changed subscription for an active driver grouping;
- one next-boundary task per event/boundary-driven attachment;
- one lazy shared phase binding for exact active Samples, backward entry poised at an excluded
  Sample end, outward pending zero-distance loop joins, and callback-side raw resumes awaiting
  their first post-resume sample;
- linear snapshot fan-out;
- stale reached-task generations;
- previous/current provider-boundary reconciliation;
- translation of reported discontinuities to an attachment-selected response.

Attachment requires an explicit `discontinuityMode` of `skip`, `reconstruct`, or `cancel`. There is
no default and no Sequence lookup.

For a discontinuity, the driver reconciles natural movement through the delivered previous
boundary under the preceding mapping, projects the current provider coordinate, accepts it as a new
source anchor, and invokes explicit core seek/cancel behavior. The jump itself is never sent through
natural event traversal.

For a continuous rate/mapping change, the previous boundary is reconciled before current position
and the latest provider sample are accepted, then deadlines and phase membership are refreshed.

The driver borrows the clock. Driver destruction or provider destruction safely terminates
attachments and releases Pulse bindings/tasks but never destroys the provider.

Attachment transfers exclusive temporal-control ownership to the returned `DrivenPlayback` until
detach. Hosts must not mutate the retained raw handle while attached. A `PlaybackControl` delivered
to authored callback code remains valid synchronously through the raw operation queue, after which
the driver refreshes; it is not an asynchronous driven-control handle.

Phase notifications reuse their one shared provider sample. Each attachment retains the absolute
source coordinate and direction of its reached task. A forecast coordinate that is unchanged or
equivalent within a bounded binary64 rounding tolerance keeps the task and its original cached
coordinate, so refresh performs no attachment-local read or `rescheduleAt`; reached checks use the
coordinate where that task was actually bound. Only new or materially changed deadlines retain
post-schedule validation for source movement during scheduling.

A synchronous callback-side `PlaybackControl:resume()` may finish its enclosing driver evaluation
without a current provider snapshot. Its raw forecast temporarily requires phase evaluation with no
source deadline. The first subsequent phase sample clears that pending resume without catch-up;
event-only playback then releases phase ownership and schedules its next deadline.

## Revision handling

External provider revisions are not part of the raw or driven public contract and are not filtered.
ClockDriver serializes received changed, reached, phase, and control notifications in its own queue.
Stale reached work uses private task generations. No concrete ordering hole remained that justified
a second revision policy layered over the provider.

## Public removals and replacements

| Removed | Replacement |
| --- | --- |
| mandatory `Pulse.temporalAdapter(...)` argument to `Pulse.playback` | raw `Pulse.playback(sequence, context, options?)`; optional `Pulse.clockDriver(...)` |
| Sequence-owned address policy field/builder/getter/type | per-call `AddressMode` and attachment `DriverDiscontinuityMode` |
| implicit no-argument raw `Playback:play()` | `Playback:play(TimeSample)` |
| clock-driven raw progression | `Playback:evaluate(TimeSample)` |
| accumulator-style continuous definition and builder method | absolute `Sample`, `samples`, and `Builder:sample` |
| provider-specific address cause | core `AddressCause = "initial" | "seek"` |
| one-argument `seek(address)` | `seek(address, "skip" | "reconstruct")` |

No compatibility aliases are provided because retaining the names would hide changed semantics.

## Consequences

Hosts can unit-test and evaluate Pulse without clocks. Reusable Sequence declarations no longer
encode streaming or reconciliation decisions. Scheduling remains available as an optimization and
integration convenience, with its ownership and failure modes visible at the attachment boundary.

The cost is an intentional breaking API change and a stricter host responsibility: raw callers
must choose exact samples and address modes. This explicitness is the desired contract.
