# Components / Sequence

<div class="api-path">src/pulse/components/sequence/shared/sequence/init.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Public compiled template</span>
  <span class="api-badge">Immutable</span>
</div>

A Sequence is a reusable compiled timeline. Its generic parameter ties every authored callback to
the per-play context required by `Pulse.playback`. It owns no invocation context, live clock,
cursor, or cleanup.

<a id="event"></a>
## Event

```luau
type Event<ContextT> = {
	time: number,
	run: (playback: PlaybackControl, context: ContextT) -> (),
	reverse: ((playback: PlaybackControl, context: ContextT) -> ())?,
}
```

`time` must be finite and within `0..duration`. Events at the same time run in authored order when
moving forward and reverse authored order when moving backward. `reverse` owns undo for authored
side effects; Pulse does not infer rollback from `run` or cleanup registrations.

<a id="update"></a>
## Update

```luau
type Update<ContextT> = {
	startTime: number?,
	endTime: number?,
	run: (
		playback: PlaybackControl,
		dt: number,
		timePosition: number,
		context: ContextT
	) -> (),
}
```

The interval defaults to the full sequence. It must satisfy
`0 <= startTime < endTime <= duration`. `dt` is signed sequence-time overlap for this update during
the phase evaluation; `timePosition` is the current local position. Reverse traversal produces a
negative `dt`.

The per-play context is the final argument so the established `dt` and `timePosition` positions stay
stable.

<a id="sequence-definition"></a>
## SequenceDefinition

```luau
type SequenceDefinition<ContextT> = {
	duration: number,
	loop: boolean?,
	addressPolicy: AddressPolicy?,
	events: { Event<ContextT> }?,
	updates: { Update<ContextT> }?,
	onPlay: ((playback: PlaybackControl, context: ContextT) -> ())?,
	onAddress: ((playback: PlaybackControl, info: AddressInfo, context: ContextT) -> ())?,
	onLoop: ((playback: PlaybackControl, change: LoopChange, context: ContextT) -> ())?,
}
```

| Field | Default | Description |
| --- | --- | --- |
| `duration` | required | Nonnegative finite sequence length; looping requires a positive value |
| `loop` | `false` | Continue across duration and zero boundaries; invalid when duration is zero |
| `addressPolicy` | `"skip"` | Policy for manual seeks and discontinuous clock jumps |
| `events` | `{}` | Discrete authored occurrences |
| `updates` | `{}` | Continuous active intervals |
| `onPlay` | none | Opens each initial or rebuilt cleanup generation |
| `onAddress` | none | Materializes state after a successful non-natural position change |
| `onLoop` | none | Runs at each logical loop crossing before observers |

The compiler clones, validates, sorts, and freezes runtime data. Input arrays must be dense.
At `duration = 0`, only non-looping instantaneous behavior is valid; no positive update interval can
fit within the Sequence.

<a id="sequence-definition-on-address"></a>
### SequenceDefinition.onAddress

```luau
onAddress: ((
	playback: PlaybackControl,
	info: AddressInfo,
	context: ContextT
) -> ())?
```

Runs after Pulse establishes the exact target of an initial placement, accepted seek, or accepted
clock discontinuity. `info.mode` distinguishes event reconstruction from a silent skip. A cancelled
address does not invoke the callback.

The callback runs inside Playback's serialized mutation operation. `playback:getPosition()` equals
`info.target`; a reentrant nonterminal mutation is queued until the callback returns, while a
terminal request interrupts the remaining operation. Pulse does not synthesize an `Update.run`
sample during reconstruction or skip, so this callback is the explicit seam for materializing
host-defined active spans and sampled values.

<a id="sequence"></a>
## Sequence

```luau
type Sequence<ContextT> = {
	getDuration: (self: Sequence<ContextT>) -> number,
	isLooping: (self: Sequence<ContextT>) -> boolean,
	getAddressPolicy: (self: Sequence<ContextT>) -> AddressPolicy,
}
```

### Methods

| Method | Returns | Description |
| --- | --- | --- |
| [`getDuration`](#sequence-get-duration) | `number` | Compiled nonnegative duration |
| [`isLooping`](#sequence-is-looping) | `boolean` | Whether traversal crosses indefinitely between cycles |
| [`getAddressPolicy`](#sequence-get-address-policy) | `AddressPolicy` | Discontinuity and seek policy |

<a id="pulse-sequence"></a>
## Pulse.sequence

```luau
Pulse.sequence<ContextT>(definition: SequenceDefinition<ContextT>) -> Sequence<ContextT>
```

Compiles and freezes a raw definition. Invalid definitions raise at the caller boundary.

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

Returns whether the sequence has unbounded logical loop identities.

<a id="sequence-get-address-policy"></a>
### Sequence:getAddressPolicy

```luau
Sequence:getAddressPolicy() -> AddressPolicy
```

Returns the policy used by Playback for manual seeks and discontinuous provider changes.
