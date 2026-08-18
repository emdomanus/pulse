# Components / Sequence

<div class="api-path">src/pulse/components/sequence/shared/sequence/init.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Public compiled template</span>
  <span class="api-badge">Immutable</span>
</div>

A Sequence is a reusable compiled timeline. Its generic parameter ties every authored callback to
the per-play context required by `Pulse.playback`. It owns no invocation context, address mode,
clock metadata, cursor, or cleanup.

<a id="event"></a>
## Event

```luau
type Event<ContextT> = {
	time: number,
	run: (playback: PlaybackControl, context: ContextT) -> (),
	reverse: ((playback: PlaybackControl, context: ContextT) -> ())?,
}
```

`time` must be finite and within `0..duration`. Equal-time events run in authored order forward
and reverse authored order backward. `reverse` owns domain-specific undo; Pulse does not infer
rollback from `run` or cleanup registrations.

<a id="sample"></a>
## Sample

```luau
type Sample<ContextT> = {
	startTime: number?,
	endTime: number?,
	run: (
		playback: PlaybackControl,
		sample: SampleInfo,
		context: ContextT
	) -> (),
}
```

The interval defaults to the full sequence and must satisfy
`0 <= startTime < endTime <= duration`. Membership is direction-independent and half-open:
`[startTime, endTime)`. Each active Sample runs once after a natural evaluation reaches its final
position, after an initial address, and after a seek. `SampleInfo` contains the absolute final
Playback position and signed effective rate, with no delta.

A large or multi-loop jump traverses every crossed Event but runs an active Sample only once at the
final position. Equal-coordinate evaluation may run it once again without duplicating Events.

<a id="sequence-definition"></a>
## SequenceDefinition

```luau
type SequenceDefinition<ContextT> = {
	duration: number,
	loop: boolean?,
	events: { Event<ContextT> }?,
	samples: { Sample<ContextT> }?,
	onPlay: ((playback: PlaybackControl, context: ContextT) -> ())?,
	onAddress: ((playback: PlaybackControl, info: AddressInfo, context: ContextT) -> ())?,
	onLoop: ((playback: PlaybackControl, change: LoopChange, context: ContextT) -> ())?,
}
```

| Field | Default | Description |
| --- | --- | --- |
| `duration` | required | Nonnegative finite sequence length; looping requires a positive value |
| `loop` | `false` | Traverse through logical cycles indefinitely |
| `events` | `{}` | Discrete authored occurrences |
| `samples` | `{}` | Absolute sampled intervals |
| `onPlay` | none | Opens each initial or reconstructed cleanup generation |
| `onAddress` | none | Materializes state at an initial or explicitly sought position |
| `onLoop` | none | Runs at each logical loop crossing before observers |

The compiler clones, validates, sorts, and freezes runtime data. Input arrays must be dense. At
`duration = 0`, only non-looping instantaneous behavior is valid; no positive Sample interval can
fit.

<a id="sequence-definition-on-address"></a>
### SequenceDefinition.onAddress

```luau
onAddress: ((
	playback: PlaybackControl,
	info: AddressInfo,
	context: ContextT
) -> ())?
```

Runs after Pulse establishes/reconstructs the exact target and before active Samples run there.
`info.cause` is `initial` or `seek`; `info.mode` distinguishes reconstruction from a skip. The
callback runs inside Playback's serialized operation, and `playback:getPosition()` equals
`info.target`.

This is the generic late-materialization seam for host-owned resources, leases, pools, and curve
state at an arbitrary elapsed position. A nonterminal mutation requested reentrantly is queued
until the callback returns; a terminal request interrupts the remainder of the address operation.

<a id="sequence"></a>
## Sequence

```luau
type Sequence<ContextT> = {
	getDuration: (self: Sequence<ContextT>) -> number,
	isLooping: (self: Sequence<ContextT>) -> boolean,
}
```

### Methods

| Method | Returns | Description |
| --- | --- | --- |
| [`getDuration`](#sequence-get-duration) | `number` | Compiled nonnegative duration |
| [`isLooping`](#sequence-is-looping) | `boolean` | Whether traversal crosses indefinitely between cycles |

<a id="pulse-sequence"></a>
## Pulse.sequence

```luau
Pulse.sequence<ContextT>(definition: SequenceDefinition<ContextT>) -> Sequence<ContextT>
```

Compiles and freezes a raw definition. Invalid definitions raise at the caller boundary. The
result has no clock or discontinuity choice, so different Playback invocations may address it
differently.

<a id="sequence-get-duration"></a>
### Sequence:getDuration

```luau
Sequence:getDuration() -> number
```

Returns the authored duration.

<a id="sequence-is-looping"></a>
### Sequence:isLooping

```luau
Sequence:isLooping() -> boolean
```

Returns whether the Sequence has unbounded logical loop identities.
