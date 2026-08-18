# Components / Playback

<div class="api-path">src/pulse/components/playback/shared/playback/init.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Public raw core</span>
  <span class="api-badge">Externally sampled</span>
  <span class="api-badge">Single lifecycle</span>
</div>

A Playback is one live traversal of a reusable
[`Sequence<ContextT>`](./sequence.md#sequence). It owns no clock and advances only through finite
[`TimeSample`](../types/definitions.md#time-sample) values supplied to `play` and `evaluate`.
Construction is inert so observers can be registered before synchronous work begins.

<a id="playback-options"></a>
## PlaybackOptions

```luau
type PlaybackOptions = {
	playbackSpeed: number?,
	position: SequenceAddress?,
	initialMode: AddressMode?,
}
```

| Field | Default | Description |
| --- | --- | --- |
| `playbackSpeed` | `1` | Finite local multiplier applied to source displacement and sampled rate |
| `position` | `{ timePosition = 0 }` | Exact initial address established by `play` |
| `initialMode` | `"reconstruct"` | Reconstructs history or skips directly to the initial address |

Negative speed reverses mapping and zero speed prevents source displacement from moving the
sequence. For a looping Sequence, `position.loopIndex` selects the exact logical cycle. Choose
`initialMode = "skip"` for late materialization that must not replay historical one-shot Events.

<a id="playback-control"></a>
## PlaybackControl

The capability passed to authored Event, Sample, setup, address, and loop callbacks. It contains
control and read methods, but not `play`, `evaluate`, observers, or completion access.

```luau
type PlaybackControl = {
	pause: (self: PlaybackControl) -> (),
	resume: (self: PlaybackControl) -> (),
	setPlaybackSpeed: (self: PlaybackControl, speed: number) -> (),
	getPlaybackSpeed: (self: PlaybackControl) -> number,
	seek: (self: PlaybackControl, address: SequenceAddress, mode: AddressMode) -> boolean,
	getPosition: (self: PlaybackControl) -> PlaybackPosition,
	getStatus: (self: PlaybackControl) -> Status,
	addCleanup: (self: PlaybackControl, cleanup: () -> ()) -> (),
	cancel: (self: PlaybackControl, reason: string?) -> (),
	destroy: (self: PlaybackControl) -> (),
}
```

For a raw host, this capability follows the Playback's lifetime. When the Playback is attached to
a `ClockDriver`, callback code may use it synchronously and its mutations serialize through the raw
operation queue. It must not retain the capability and invoke it asynchronously while driven;
later temporal control must use the attachment's `DrivenPlayback` facade.

<a id="ended-callback"></a>
## EndedCallback

```luau
type EndedCallback = (completion: Completion) -> ()
```

An observer for the Playback's single immutable terminal result.

<a id="looped-callback"></a>
## LoopedCallback

```luau
type LoopedCallback = (change: LoopChange) -> ()
```

An observer for logical forward or backward loop crossings.

<a id="playback"></a>
## Playback

```luau
type Playback = PlaybackControl & {
	play: (self: Playback, sample: TimeSample) -> Playback,
	evaluate: (self: Playback, sample: TimeSample) -> boolean,
	onEnded: (self: Playback, callback: EndedCallback) -> Release,
	onLooped: (self: Playback, callback: LoopedCallback) -> Release,
	isAlive: (self: Playback) -> boolean,
	getCompletion: (self: Playback) -> Completion?,
}
```

## Summary

### Lifecycle and time

| Method | Signature | Description |
| --- | --- | --- |
| [`play`](#playback-play) | `(TimeSample) -> Playback` | Establishes the first address and starts the lifecycle |
| [`evaluate`](#playback-evaluate) | `(TimeSample) -> boolean` | Traverses to an absolute source sample and samples final state |
| [`pause`](#playback-pause) | `() -> ()` | Pauses at the accepted coordinate |
| [`resume`](#playback-resume) | `() -> ()` | Makes the next sample a no-catch-up re-anchor |
| [`cancel`](#playback-cancel) | `(reason: string?) -> ()` | Completes as `cancelled` |
| [`destroy`](#playback-destroy) | `() -> ()` | Completes as `destroyed` and retires observers |
| [`isAlive`](#playback-is-alive) | `() -> boolean` | Tests whether no terminal Completion exists |

### Timeline

| Method | Signature | Description |
| --- | --- | --- |
| [`setPlaybackSpeed`](#playback-set-playback-speed) | `(number) -> ()` | Re-anchors local mapping at the accepted coordinate |
| [`getPlaybackSpeed`](#playback-get-playback-speed) | `() -> number` | Reads the local multiplier |
| [`seek`](#playback-seek) | `(SequenceAddress, AddressMode) -> boolean` | Explicitly skips or reconstructs |
| [`getPosition`](#playback-get-position) | `() -> PlaybackPosition` | Reads a cloned accepted position |
| [`getStatus`](#playback-get-status) | `() -> Status` | Reads active or terminal state |

### Ownership and observation

| Method | Signature | Description |
| --- | --- | --- |
| [`addCleanup`](#playback-add-cleanup) | `(() -> ()) -> ()` | Adds generation-scoped LIFO cleanup |
| [`onEnded`](#playback-on-ended) | `(EndedCallback) -> Release` | Observes the terminal result |
| [`onLooped`](#playback-on-looped) | `(LoopedCallback) -> Release` | Observes logical loop crossings |
| [`getCompletion`](#playback-get-completion) | `() -> Completion?` | Reads the immutable terminal result |

<a id="pulse-playback"></a>
## Pulse.playback

```luau
Pulse.playback<ContextT>(
	sequence: Sequence<ContextT>,
	context: ContextT,
	options: PlaybackOptions?
) -> Playback
```

Creates an idle raw Playback and retains `context` for authored callbacks. The Sequence's invariant
generic requires the matching context type at analysis time. Pulse does not clone or interpret the
context and releases its retained reference during terminal cleanup before Ended observers run.

No provider or driver is required. Invalid initial speed, address, or mode raises during
construction.

<a id="playback-play"></a>
### Playback:play

```luau
Playback:play(sample: TimeSample) -> Playback
```

Copies and validates the first source sample, enters `playing`, and establishes the configured
initial address. `reconstruct` opens the first generation and replays Events canonically forward
from local zero of the selected loop; `skip` opens the generation and suppresses historical Events,
including Events exactly at the target.

Ordering is: setup/reconstruction or placement, `onAddress`, each active Sample once, then future
traversal provenance. For a non-looping zero-duration Sequence, outward motion completes
synchronously after this work. Calling `play` after leaving `idle` is an idempotent no-op; construct
another Playback to run the Sequence again.

<a id="playback-evaluate"></a>
### Playback:evaluate

```luau
Playback:evaluate(sample: TimeSample) -> boolean
```

Maps the absolute source displacement through:

```text
target = anchorSequence + (sample.position - anchorSource) * playbackSpeed
```

Pulse never multiplies the displacement by `sample.rate`. It traverses every crossed discrete
boundary exactly once, preserving equal-time ordering, reverse callbacks, loop hooks, loop
observers, and exact loop-boundary provenance. It then accepts/re-anchors the sample and invokes
each Sample active at the final `[startTime, endTime)` position once with effective rate
`sample.rate * playbackSpeed`.

A multi-loop jump does not synthesize one Sample callback per crossed loop. Equal-position
evaluation emits no discrete Event again but may Sample active state once. Returns `true` when a
playing Playback accepted the evaluation for serialized processing; returns `false` otherwise.
Invalid samples raise before the status check.

<a id="playback-pause"></a>
### Playback:pause

```luau
Playback:pause() -> ()
```

Enters `paused` at the currently accepted evaluated coordinate. The raw core has no implicit clock
to reconcile. If the mutation belongs at a newer coordinate, call `evaluate(newerSample)` first.
Calls outside `playing` do nothing.

<a id="playback-resume"></a>
### Playback:resume

```luau
Playback:resume() -> ()
```

Returns a paused Playback to `playing`, but leaves it pending until the next `evaluate`. That first
sample is accepted as a new source anchor at the stored sequence position, invokes active Samples,
and does not traverse source motion that occurred while paused. Calls outside `paused` do nothing.

<a id="playback-set-playback-speed"></a>
### Playback:setPlaybackSpeed

```luau
Playback:setPlaybackSpeed(speed: number) -> ()
```

Sets a finite local multiplier for a playing or paused Playback. The mapping re-anchors at the
currently accepted source/sequence coordinate, so the position does not snap. A raw host requiring
the speed change at newer source time must evaluate that sample first. Calls on idle or terminal
Playbacks do not alter the configured value; use `PlaybackOptions` for initial speed.

<a id="playback-get-playback-speed"></a>
### Playback:getPlaybackSpeed

```luau
Playback:getPlaybackSpeed() -> number
```

Returns the current local multiplier.

<a id="playback-seek"></a>
### Playback:seek

```luau
Playback:seek(address: SequenceAddress, mode: AddressMode) -> boolean
```

Validates and applies one explicit address operation at the currently accepted coordinate:

| Mode | Behavior |
| --- | --- |
| `skip` | Places the cursor without historical Events or cleanup-generation replacement |
| `reconstruct` | Flushes the old generation LIFO, opens a new one, and replays canonical forward history to the target |

Both modes then call `onAddress` with cause `seek`, invoke active Samples once at the target, and
refresh future traversal provenance. Cancellation is not an address mode; call `cancel` explicitly.

Returns `true` when a playing or paused Playback accepted the request. Returns `false` for idle,
terminal, or terminating Playbacks. Invalid addresses or modes raise. Reentrant calls are queued
behind the current authored callback.

<a id="playback-get-position"></a>
### Playback:getPosition

```luau
Playback:getPosition() -> PlaybackPosition
```

Returns a new record for the accepted cursor. It never reads, interpolates, or projects implicit
clock/wall time. Exact loop-join identities remain distinct even when their unwrapped coordinate is
equal. An explicit duration-side address remains on that side; a later forward evaluation performs
the still-future loop hook and next-cycle zero work.

<a id="playback-get-status"></a>
### Playback:getStatus

```luau
Playback:getStatus() -> Status
```

Returns `idle`, `playing`, `paused`, or the final terminal status.

<a id="playback-add-cleanup"></a>
### Playback:addCleanup

```luau
Playback:addCleanup(cleanup: () -> ()) -> ()
```

Registers cleanup on the current generation. Cleanup runs in reverse registration order during
reconstruction or terminal completion. A callback registered after completion runs immediately.
Cleanup is not an Event-specific reverse action; use `Event.reverse` for traversal undo.

If generation cleanup throws, Pulse continues draining the remaining callbacks and fails with
reason `cleanupFailed`.

<a id="playback-cancel"></a>
### Playback:cancel

```luau
Playback:cancel(reason: string?) -> ()
```

Requests terminal status `cancelled`, drains cleanup, and publishes Ended once. A terminal request
made inside an authored callback interrupts remaining equal-time work after that callback returns.

<a id="playback-destroy"></a>
### Playback:destroy

```luau
Playback:destroy() -> ()
```

Requests terminal status `destroyed`. Calling it after completion clears retained observer
bindings. It does not destroy the immutable Sequence or any external resource not registered as
cleanup.

<a id="playback-on-ended"></a>
### Playback:onEnded

```luau
Playback:onEnded(callback: EndedCallback) -> Release
```

Observes the single immutable Completion. Registration after completion invokes the callback
synchronously and returns a no-op Release. Observer errors are isolated and do not change the
result; registration during Ended delivery is not invoked recursively.

<a id="playback-on-looped"></a>
### Playback:onLooped

```luau
Playback:onLooped(callback: LoopedCallback) -> Release
```

Observes logical cycle crossings while alive. The authored `onLoop` hook runs first. Forward
ordering is duration Events, authored loop hook, Looped observers, then next-cycle zero Events;
backward traversal mirrors it from zero into the previous duration.

<a id="playback-is-alive"></a>
### Playback:isAlive

```luau
Playback:isAlive() -> boolean
```

Returns `true` until a Completion is published. Idle and paused Playbacks are alive.

<a id="playback-get-completion"></a>
### Playback:getCompletion

```luau
Playback:getCompletion() -> Completion?
```

Returns `nil` while alive, then the frozen result. Core failure reasons include `callbackFailed`,
`cleanupFailed`, `operationFailed`, `catchUpLimitExceeded`, and `numericOverflow`; the optional
driver adds provider and scheduling failure reasons.
