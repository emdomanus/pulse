# Components / Playback

<div class="api-path">src/pulse/components/playback/shared/playback.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Public live object</span>
  <span class="api-badge">Single lifecycle</span>
  <span class="api-badge">Clock anchored</span>
</div>

A Playback is one live traversal of a reusable
[`Sequence<ContextT>`](./sequence.md#sequence) through a
[`TemporalAdapter`](../managers/temporalAdapter.md#temporal-adapter). Construction is inert; call
[`play`](#playback-play) after registering observers. The constructor also receives the exact
per-play context delivered to every authored callback.

<a id="playback-options"></a>
## PlaybackOptions

```luau
type PlaybackOptions = {
	playbackSpeed: number?,
	position: SequenceAddress?,
}
```

| Field | Default | Description |
| --- | --- | --- |
| `playbackSpeed` | `1` | Finite sequence-local clock-displacement multiplier |
| `position` | `{ timePosition = 0 }` | Initial address reconstructed when play begins |

Negative speed reverses traversal, and zero speed makes the Playback dormant without pausing its
lifecycle. For looping Sequences, `position.loopIndex` selects the exact logical cycle.

<a id="playback-control"></a>
## PlaybackControl

The capability passed to authored event, update, setup, and loop callbacks. It contains the
Playback control and read methods, but not `play`, observers, or completion access.

```luau
type PlaybackControl = {
	pause: (self: PlaybackControl) -> (),
	resume: (self: PlaybackControl) -> (),
	setPlaybackSpeed: (self: PlaybackControl, speed: number) -> (),
	getPlaybackSpeed: (self: PlaybackControl) -> number,
	seek: (self: PlaybackControl, address: SequenceAddress) -> boolean,
	getPosition: (self: PlaybackControl) -> PlaybackPosition,
	getStatus: (self: PlaybackControl) -> Status,
	addCleanup: (self: PlaybackControl, cleanup: () -> ()) -> (),
	cancel: (self: PlaybackControl, reason: string?) -> (),
	destroy: (self: PlaybackControl) -> (),
}
```

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
	play: (self: Playback) -> Playback,
	onEnded: (self: Playback, callback: (Completion) -> ()) -> Release,
	onLooped: (self: Playback, callback: (LoopChange) -> ()) -> Release,
	isAlive: (self: Playback) -> boolean,
	getCompletion: (self: Playback) -> Completion?,
}
```

## Summary

### Lifecycle

| Method | Signature | Description |
| --- | --- | --- |
| [`play`](#playback-play) | `() -> Playback` | Starts the one lifecycle |
| [`pause`](#playback-pause) | `() -> ()` | Reconciles and detaches without catching up paused clock time |
| [`resume`](#playback-resume) | `() -> ()` | Re-anchors and resumes scheduling |
| [`cancel`](#playback-cancel) | `(reason: string?) -> ()` | Completes as `cancelled` |
| [`destroy`](#playback-destroy) | `() -> ()` | Completes as `destroyed` and retires observers |
| [`isAlive`](#playback-is-alive) | `() -> boolean` | Tests whether no terminal Completion exists |

### Timeline

| Method | Signature | Description |
| --- | --- | --- |
| [`setPlaybackSpeed`](#playback-set-playback-speed) | `(speed: number) -> ()` | Reconciles, re-anchors, and reschedules without snapping |
| [`getPlaybackSpeed`](#playback-get-playback-speed) | `() -> number` | Reads the sequence-local multiplier |
| [`seek`](#playback-seek) | `(SequenceAddress) -> boolean` | Applies the Sequence address policy |
| [`getPosition`](#playback-get-position) | `() -> PlaybackPosition` | Reads a cloned current position |
| [`getStatus`](#playback-get-status) | `() -> Status` | Reads active or terminal state |

### Ownership and observation

| Method | Signature | Description |
| --- | --- | --- |
| [`addCleanup`](#playback-add-cleanup) | `(cleanup: () -> ()) -> ()` | Adds generation-scoped LIFO cleanup |
| [`onEnded`](#playback-on-ended) | `((Completion) -> ()) -> Release` | Observes the single terminal result |
| [`onLooped`](#playback-on-looped) | `((LoopChange) -> ()) -> Release` | Observes logical loop crossings |
| [`getCompletion`](#playback-get-completion) | `() -> Completion?` | Reads the immutable terminal result |

<a id="pulse-playback"></a>
## Pulse.playback

```luau
Pulse.playback<ContextT>(
	sequence: Sequence<ContextT>,
	adapter: TemporalAdapter,
	context: ContextT,
	options: PlaybackOptions?
) -> Playback
```

Creates an idle Playback and retains `context` for its authored callbacks. The generic Sequence
type requires the matching context shape at analysis time. Pulse does not clone or interpret the
context; the host owns any objects and capabilities it contains. Pulse releases its retained
reference after terminal cleanup and before Ended observers run.

Construction does not read, attach to, or schedule against the clock until `Playback:play`. An
invalid initial speed or address raises during construction.

<a id="playback-play"></a>
### Playback:play

```luau
Playback:play() -> Playback
```

Starts an idle Playback, attaches to the adapter, opens the first setup/cleanup generation, and
reconstructs authored events from the current loop's zero boundary to the initial position. It then
schedules the next boundary and joins continuous execution only if update work requires it.

For a non-looping zero-duration Sequence, `onPlay` and time-zero events run during this call, then
the Playback completes, drains cleanup, and emits Ended synchronously without scheduling.

Calling `play` after the Playback has left `idle` is an idempotent no-op. A terminal Playback cannot
be replayed; construct another Playback from the same Sequence.

<a id="playback-pause"></a>
### Playback:pause

```luau
Playback:pause() -> ()
```

Reconciles to the current sample, cancels the reached task, leaves continuous execution, detaches
from clock changes, and enters `paused`. Provider clock movement while paused is not caught up.
Calls outside `playing` do nothing.

<a id="playback-resume"></a>
### Playback:resume

```luau
Playback:resume() -> ()
```

Re-anchors the paused sequence position to the current clock sample, reattaches, and restores only
the scheduling work currently needed. Calls outside `paused` do nothing.

<a id="playback-set-playback-speed"></a>
### Playback:setPlaybackSpeed

```luau
Playback:setPlaybackSpeed(speed: number) -> ()
```

Sets a finite sequence-local multiplier. A playing Playback first reconciles under the old speed,
then re-anchors and reschedules under the new speed. A paused Playback changes speed without moving.
Calls on idle or terminal Playbacks do not change the configured value; use `PlaybackOptions` for
the initial speed.

<a id="playback-get-playback-speed"></a>
### Playback:getPlaybackSpeed

```luau
Playback:getPlaybackSpeed() -> number
```

Returns the current local multiplier.

<a id="playback-seek"></a>
### Playback:seek

```luau
Playback:seek(address: SequenceAddress) -> boolean
```

Validates the address, reconciles live timeline work, and applies the Sequence's address policy:

| Policy | Behavior |
| --- | --- |
| `skip` | Moves the cursor without replaying events or replacing the cleanup generation |
| `rebuild` | Disposes the current generation, calls `onPlay`, and replays forward from local zero to the target |
| `cancel` | Completes the Playback as `cancelled` with reason `seekCancelled` |

Returns `true` when an active Playback accepted the request for serialized processing. Returns
`false` for idle, terminal, or currently terminating Playbacks. Invalid addresses raise.

<a id="playback-get-position"></a>
### Playback:getPosition

```luau
Playback:getPosition() -> PlaybackPosition
```

Returns a new position record. While playing, the read projects the latest safe clock sample from
the current anchor; it does not itself deliver events. At exact loop joins, `{ timePosition =
duration, loopIndex = n }` and `{ timePosition = 0, loopIndex = n + 1 }` remain distinct authored
boundary identities even though their unwrapped coordinate is equal.

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

Registers cleanup on the current generation. Cleanup runs in reverse registration order during a
`rebuild` or terminal completion. A callback registered after completion runs immediately. Cleanup
is not an occurrence-specific reverse callback; use `Event.reverse` for traversal undo.

If generation cleanup throws, Pulse continues draining the remaining callbacks and fails with
reason `cleanupFailed`.

<a id="playback-cancel"></a>
### Playback:cancel

```luau
Playback:cancel(reason: string?) -> ()
```

Requests terminal status `cancelled`, releases scheduling ownership, drains cleanup, and emits
Ended once. A terminal request made inside an authored callback interrupts remaining equal-time
work after that callback returns.

<a id="playback-destroy"></a>
### Playback:destroy

```luau
Playback:destroy() -> ()
```

Requests terminal status `destroyed`. Calling it after completion clears retained Ended and Looped
observer bindings. It does not destroy the Sequence, adapter, or provider clock.

<a id="playback-on-ended"></a>
### Playback:onEnded

```luau
Playback:onEnded(callback: (completion: Completion) -> ()) -> Release
```

Observes the single immutable Completion. A callback registered after completion is invoked
synchronously and receives a no-op Release. Observer errors are isolated and do not change the
Playback result. Reentrant registration during Ended delivery is not invoked recursively.

<a id="playback-on-looped"></a>
### Playback:onLooped

```luau
Playback:onLooped(callback: (change: LoopChange) -> ()) -> Release
```

Observes each logical cycle crossing while alive. The authored `SequenceDefinition.onLoop` runs
first. Forward ordering is duration events, authored loop callback, Looped observers, then the next
cycle's zero events. Reverse traversal mirrors that order from zero into the previous duration.

<a id="playback-is-alive"></a>
### Playback:isAlive

```luau
Playback:isAlive() -> boolean
```

Returns `true` until a Completion is published. Paused Playbacks are alive.

<a id="playback-get-completion"></a>
### Playback:getCompletion

```luau
Playback:getCompletion() -> Completion?
```

Returns `nil` while alive, then the frozen terminal result. Common implementation failure reasons
include `callbackFailed`, `cleanupFailed`, `clockReadFailed`, `adapterDestroyed`,
`catchUpLimitExceeded`, and `numericOverflow`; `reason` remains a string because cancellation may
carry a host-authored reason.
