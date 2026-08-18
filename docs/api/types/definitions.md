# Types / Definitions

<div class="api-path">src/pulse/types/def/init.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Public shared types</span>
  <span class="api-badge">Frozen callback records</span>
</div>

<a id="release"></a>
## Release

```luau
type Release = () -> ()
```

An idempotent observer or provider-binding release callback.

<a id="traversal-direction"></a>
## TraversalDirection

```luau
type TraversalDirection = "forward" | "backward"
```

Direction through sequence coordinates after source displacement and local playback speed are
combined.

<a id="address-mode"></a>
## AddressMode

```luau
type AddressMode = "reconstruct" | "skip"
```

| Value | Explicit address behavior |
| --- | --- |
| `reconstruct` | Replace/open the cleanup generation and replay canonical forward history to the target |
| `skip` | Place the cursor without historical event traversal or generation replacement |

Cancellation is the separate `Playback:cancel` lifecycle operation. An address mode is selected by
each initial placement or seek, never stored in a Sequence.

<a id="address-cause"></a>
## AddressCause

```luau
type AddressCause = "initial" | "seek"
```

Why the raw core established a position without natural traversal. Provider-specific causes do not
enter this type.

<a id="time-sample"></a>
## TimeSample

```luau
type TimeSample = {
	position: number,
	rate: number,
}
```

Both fields must be finite. `position` is the absolute source coordinate. `rate` atomically
describes the source rate at that coordinate; it selects future direction and feeds sampled
metadata. Pulse never multiplies position displacement by rate. The record contains no revision,
epoch, boundary, discontinuity, prediction, network, or authority metadata.

<a id="sequence-address"></a>
## SequenceAddress

```luau
type SequenceAddress = {
	timePosition: number,
	loopIndex: number?,
}
```

`timePosition` must be finite and inside the inclusive sequence duration. `loopIndex` defaults to
zero, must be an exactly representable integer, and must be zero for a non-looping Sequence.

At a loop join, `{ timePosition = duration, loopIndex = n }` and `{ timePosition = 0, loopIndex = n
+ 1 }` are distinct exact addresses with the same unwrapped coordinate.

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
| `timePosition` | Local authored position in the current loop identity |
| `loopIndex` | Signed logical cycle identity; zero for a non-looping Sequence |
| `unwrappedTimePosition` | Absolute sequence coordinate used by anchors and traversal |

Public reads return new records; callback records freeze nested positions.

<a id="sample-info"></a>
## SampleInfo

```luau
type SampleInfo = {
	position: PlaybackPosition,
	rate: number,
}
```

The immutable record passed to an active `Sample.run`. `position` is the final absolute Playback
position for this evaluation. `rate` is `TimeSample.rate * playbackSpeed`, so it is signed and may
be zero. There is intentionally no delta field.

<a id="address-info"></a>
## AddressInfo

```luau
type AddressInfo = {
	cause: AddressCause,
	mode: AddressMode,
	from: PlaybackPosition?,
	target: PlaybackPosition,
}
```

An immutable report delivered to `SequenceDefinition.onAddress`. `from` is `nil` for initial
placement and is the accepted pre-seek cursor for a later explicit seek. `target` preserves loop
and authored-boundary identity.

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

`completed` is natural non-looping boundary completion. `cancelled` is a host lifecycle decision.
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

The single frozen terminal result retained by Playback. The reason may be supplied by a host
cancellation or by a deterministic core/driver failure.
