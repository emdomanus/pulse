# Types / Definitions

<div class="api-path">src/pulse/types/def/init.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Public shared types</span>
  <span class="api-badge">Frozen value records</span>
</div>

<a id="release"></a>
## Release

```luau
type Release = () -> ()
```

An idempotent observer or binding release callback.

<a id="traversal-direction"></a>
## TraversalDirection

```luau
type TraversalDirection = "forward" | "backward"
```

The actual direction through sequence coordinates after provider displacement and local playback
speed are combined.

<a id="address-policy"></a>
## AddressPolicy

```luau
type AddressPolicy = "skip" | "rebuild" | "cancel"
```

| Value | Manual seek or discontinuous clock change |
| --- | --- |
| `skip` | Adopt the target without replaying authored events or replacing cleanup |
| `rebuild` | Dispose the generation, rerun setup, and reconstruct forward to the target |
| `cancel` | Complete as cancelled rather than adopting the target |

Normal continuous traversal and clock-rate changes do not use this policy.

<a id="sequence-address"></a>
## SequenceAddress

```luau
type SequenceAddress = {
	timePosition: number,
	loopIndex: number?,
}
```

An authored local address. `timePosition` must lie within the inclusive sequence duration.
`loopIndex` defaults to zero, must be an exactly representable integer, and must be zero for a
non-looping Sequence.

At a loop join, `{ timePosition = duration, loopIndex = n }` and `{ timePosition = 0, loopIndex = n
+ 1 }` are distinct addresses with the same unwrapped coordinate.

<a id="playback-position"></a>
## PlaybackPosition

```luau
type PlaybackPosition = {
	timePosition: number,
	loopIndex: number,
	unwrappedTimePosition: number,
}
```

| Field | Description |
| --- | --- |
| `timePosition` | Authored local position within the current loop identity |
| `loopIndex` | Signed logical cycle identity; always zero when non-looping |
| `unwrappedTimePosition` | Unwrapped sequence coordinate used by traversal and anchors |

Playback returns a fresh record so callers cannot mutate internal cursor state.

<a id="loop-change"></a>
## LoopChange

```luau
type LoopChange = {
	fromLoopIndex: number,
	toLoopIndex: number,
	direction: TraversalDirection,
}
```

A frozen logical loop crossing delivered to authored and observer callbacks.

<a id="active-status"></a>
## ActiveStatus

```luau
type ActiveStatus = "idle" | "playing" | "paused"
```

<a id="terminal-status"></a>
## TerminalStatus

```luau
type TerminalStatus = "completed" | "cancelled" | "destroyed" | "failed"
```

`completed` is natural non-looping boundary completion. `cancelled` is policy or host cancellation.
`destroyed` is explicit Playback destruction. `failed` represents callback, cleanup, provider,
safety-limit, or numeric failure.

<a id="status"></a>
## Status

```luau
type Status = ActiveStatus | TerminalStatus
```

<a id="completion"></a>
## Completion

```luau
type Completion = {
	status: TerminalStatus,
	reason: string?,
}
```

The single frozen terminal result retained by Playback. The reason may be authored for cancellation
or implementation-provided for a deterministic failure.
