# Components / Sequence

<div class="api-path">src/pulse/components/sequence/shared/sequence/init.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Public compiled template</span>
  <span class="api-badge">Immutable</span>
</div>

A Sequence is a reusable compiled timeline. It owns authored boundaries and policies, but no live
clock, cursor, or cleanup.

<a id="event"></a>
## Event

```luau
type Event = {
	time: number,
	run: (playback: PlaybackContext) -> (),
	reverse: ((playback: PlaybackContext) -> ())?,
}
```

`time` must be finite and within `0..duration`. Events at the same time run in authored order when
moving forward and reverse authored order when moving backward. `reverse` owns undo for authored
side effects; Pulse does not infer rollback from `run` or cleanup registrations.

<a id="update"></a>
## Update

```luau
type Update = {
	startTime: number?,
	endTime: number?,
	run: (playback: PlaybackContext, dt: number, timePosition: number) -> (),
}
```

The interval defaults to the full sequence. It must satisfy
`0 <= startTime < endTime <= duration`. `dt` is signed sequence-time overlap for this update during
the phase evaluation; `timePosition` is the current local position. Reverse traversal produces a
negative `dt`.

<a id="sequence-definition"></a>
## SequenceDefinition

```luau
type SequenceDefinition = {
	duration: number,
	loop: boolean?,
	addressPolicy: AddressPolicy?,
	events: { Event }?,
	updates: { Update }?,
	onPlay: ((playback: PlaybackContext) -> ())?,
	onLoop: ((playback: PlaybackContext, change: LoopChange) -> ())?,
}
```

| Field | Default | Description |
| --- | --- | --- |
| `duration` | required | Positive finite sequence length |
| `loop` | `false` | Continue across duration and zero boundaries |
| `addressPolicy` | `"skip"` | Policy for manual seeks and discontinuous clock jumps |
| `events` | `{}` | Discrete authored occurrences |
| `updates` | `{}` | Continuous active intervals |
| `onPlay` | none | Opens each initial or rebuilt cleanup generation |
| `onLoop` | none | Runs at each logical loop crossing before observers |

The compiler clones, validates, sorts, and freezes runtime data. Input arrays must be dense.

<a id="sequence"></a>
## Sequence

```luau
type Sequence = {
	getDuration: (self: Sequence) -> number,
	isLooping: (self: Sequence) -> boolean,
	getAddressPolicy: (self: Sequence) -> AddressPolicy,
}
```

### Methods

| Method | Returns | Description |
| --- | --- | --- |
| [`getDuration`](#sequence-get-duration) | `number` | Compiled positive duration |
| [`isLooping`](#sequence-is-looping) | `boolean` | Whether traversal crosses indefinitely between cycles |
| [`getAddressPolicy`](#sequence-get-address-policy) | `AddressPolicy` | Discontinuity and seek policy |

<a id="pulse-sequence"></a>
## Pulse.sequence

```luau
Pulse.sequence(definition: SequenceDefinition) -> Sequence
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
