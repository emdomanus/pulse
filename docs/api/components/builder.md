# Components / Builder

<div class="api-path">src/pulse/components/sequence/shared/sequence/builder.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Public authoring helper</span>
  <span class="api-badge">Mutable until compile</span>
</div>

<a id="builder"></a>
## Builder

```luau
type Builder<ContextT> = {
	duration: (self: Builder<ContextT>, seconds: number) -> Builder<ContextT>,
	loop: (self: Builder<ContextT>, enabled: boolean?) -> Builder<ContextT>,
	addressPolicy: (self: Builder<ContextT>, policy: AddressPolicy) -> Builder<ContextT>,
	event: (self: Builder<ContextT>, event: Event<ContextT>) -> Builder<ContextT>,
	update: (self: Builder<ContextT>, update: Update<ContextT>) -> Builder<ContextT>,
	onPlay: (self: Builder<ContextT>, callback: (PlaybackControl, ContextT) -> ()) -> Builder<ContextT>,
	onAddress: (
		self: Builder<ContextT>,
		callback: (PlaybackControl, AddressInfo, ContextT) -> ()
	) -> Builder<ContextT>,
	onLoop: (
		self: Builder<ContextT>,
		callback: (PlaybackControl, LoopChange, ContextT) -> ()
	) -> Builder<ContextT>,
	compile: (self: Builder<ContextT>) -> Sequence<ContextT>,
}
```

## Summary

| Method | Description |
| --- | --- |
| [`duration`](#builder-duration) | Sets the required nonnegative duration |
| [`loop`](#builder-loop) | Enables or disables looping |
| [`addressPolicy`](#builder-address-policy) | Selects `skip`, `rebuild`, or `cancel` |
| [`event`](#builder-event) | Appends one event |
| [`update`](#builder-update) | Appends one continuous interval |
| [`onPlay`](#builder-on-play) | Sets generation setup |
| [`onAddress`](#builder-on-address) | Sets address materialization |
| [`onLoop`](#builder-on-loop) | Sets the authored loop observer |
| [`compile`](#builder-compile) | Validates and returns an immutable Sequence |

<a id="pulse-builder"></a>
## Pulse.builder

```luau
Pulse.builder<ContextT>() -> Builder<ContextT>
```

Creates an empty builder. The default address policy is `skip`; looping defaults to `false`.
Luau infers a parameterless generic constructor from its expected type:

```luau
local builder: Pulse.Builder<PresentationContext> = Pulse.builder()
```

<a id="builder-duration"></a>
### Builder:duration

```luau
Builder<ContextT>:duration(seconds: number) -> Builder<ContextT>
```

Sets the required sequence duration and returns the same Builder. Zero is valid only for a
non-looping Sequence.

<a id="builder-loop"></a>
### Builder:loop

```luau
Builder<ContextT>:loop(enabled: boolean?) -> Builder<ContextT>
```

Enables looping when omitted or `true`, and disables it when `false`.

<a id="builder-address-policy"></a>
### Builder:addressPolicy

```luau
Builder<ContextT>:addressPolicy(policy: AddressPolicy) -> Builder<ContextT>
```

Sets the policy for Playback seeks and discontinuous clock changes.

<a id="builder-event"></a>
### Builder:event

```luau
Builder<ContextT>:event(event: Event<ContextT>) -> Builder<ContextT>
```

Copies and appends an event. Compilation preserves authored order for equal times.

<a id="builder-update"></a>
### Builder:update

```luau
Builder<ContextT>:update(update: Update<ContextT>) -> Builder<ContextT>
```

Copies and appends a continuous update interval.

<a id="builder-on-play"></a>
### Builder:onPlay

```luau
Builder<ContextT>:onPlay(callback: (PlaybackControl, ContextT) -> ()) -> Builder<ContextT>
```

Sets the callback that opens each initial or rebuilt generation.

<a id="builder-on-address"></a>
### Builder:onAddress

```luau
Builder<ContextT>:onAddress(
	callback: (PlaybackControl, AddressInfo, ContextT) -> ()
) -> Builder<ContextT>
```

Sets the callback that materializes host-owned state after an initial placement, seek, or clock
discontinuity is established.

<a id="builder-on-loop"></a>
### Builder:onLoop

```luau
Builder<ContextT>:onLoop(
	callback: (PlaybackControl, LoopChange, ContextT) -> ()
) -> Builder<ContextT>
```

Sets the authored loop callback. It runs before callbacks registered with `Playback:onLooped`.

<a id="builder-compile"></a>
### Builder:compile

```luau
Builder<ContextT>:compile() -> Sequence<ContextT>
```

Validates the accumulated definition and returns a frozen reusable Sequence. The Builder remains a
mutable authoring object; do not mutate it concurrently while compiling.
