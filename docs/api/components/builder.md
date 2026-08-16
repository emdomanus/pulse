# Components / Builder

<div class="api-path">src/pulse/components/sequence/shared/sequence/builder.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Public authoring helper</span>
  <span class="api-badge">Mutable until compile</span>
</div>

<a id="builder"></a>
## Builder

```luau
type Builder = {
	duration: (self: Builder, seconds: number) -> Builder,
	loop: (self: Builder, enabled: boolean?) -> Builder,
	addressPolicy: (self: Builder, policy: AddressPolicy) -> Builder,
	event: (self: Builder, event: Event) -> Builder,
	update: (self: Builder, update: Update) -> Builder,
	onPlay: (self: Builder, callback: (PlaybackContext) -> ()) -> Builder,
	onLoop: (self: Builder, callback: (PlaybackContext, LoopChange) -> ()) -> Builder,
	compile: (self: Builder) -> Sequence,
}
```

## Summary

| Method | Description |
| --- | --- |
| [`duration`](#builder-duration) | Sets the required positive duration |
| [`loop`](#builder-loop) | Enables or disables looping |
| [`addressPolicy`](#builder-address-policy) | Selects `skip`, `rebuild`, or `cancel` |
| [`event`](#builder-event) | Appends one event |
| [`update`](#builder-update) | Appends one continuous interval |
| [`onPlay`](#builder-on-play) | Sets generation setup |
| [`onLoop`](#builder-on-loop) | Sets the authored loop observer |
| [`compile`](#builder-compile) | Validates and returns an immutable Sequence |

<a id="pulse-builder"></a>
## Pulse.builder

```luau
Pulse.builder() -> Builder
```

Creates an empty builder. The default address policy is `skip`; looping defaults to `false`.

<a id="builder-duration"></a>
### Builder:duration

```luau
Builder:duration(seconds: number) -> Builder
```

Sets the required sequence duration and returns the same Builder.

<a id="builder-loop"></a>
### Builder:loop

```luau
Builder:loop(enabled: boolean?) -> Builder
```

Enables looping when omitted or `true`, and disables it when `false`.

<a id="builder-address-policy"></a>
### Builder:addressPolicy

```luau
Builder:addressPolicy(policy: AddressPolicy) -> Builder
```

Sets the policy for Playback seeks and discontinuous clock changes.

<a id="builder-event"></a>
### Builder:event

```luau
Builder:event(event: Event) -> Builder
```

Copies and appends an event. Compilation preserves authored order for equal times.

<a id="builder-update"></a>
### Builder:update

```luau
Builder:update(update: Update) -> Builder
```

Copies and appends a continuous update interval.

<a id="builder-on-play"></a>
### Builder:onPlay

```luau
Builder:onPlay(callback: (PlaybackContext) -> ()) -> Builder
```

Sets the callback that opens each initial or rebuilt generation.

<a id="builder-on-loop"></a>
### Builder:onLoop

```luau
Builder:onLoop(callback: (PlaybackContext, LoopChange) -> ()) -> Builder
```

Sets the authored loop callback. It runs before callbacks registered with `Playback:onLooped`.

<a id="builder-compile"></a>
### Builder:compile

```luau
Builder:compile() -> Sequence
```

Validates the accumulated definition and returns a frozen reusable Sequence. The Builder remains a
mutable authoring object; do not mutate it concurrently while compiling.
