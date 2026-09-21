# Components / SequenceBuilder

<div class="api-path">src/pulse/components/sequence/shared/sequenceBuilder.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Public authoring helper</span>
  <span class="api-badge">Mutable until compile</span>
</div>

<a id="builder"></a>
## SequenceBuilder

```luau
type SequenceBuilder<ContextT> = {
	duration: (self: SequenceBuilder<ContextT>, seconds: number) -> SequenceBuilder<ContextT>,
	loop: (self: SequenceBuilder<ContextT>, enabled: boolean?) -> SequenceBuilder<ContextT>,
	event: (self: SequenceBuilder<ContextT>, event: Event<ContextT>) -> SequenceBuilder<ContextT>,
	sample: (self: SequenceBuilder<ContextT>, sample: Sample<ContextT>) -> SequenceBuilder<ContextT>,
	onPlay: (self: SequenceBuilder<ContextT>, callback: (PlaybackControl, ContextT) -> ()) -> SequenceBuilder<ContextT>,
	onAddress: (
		self: SequenceBuilder<ContextT>,
		callback: (PlaybackControl, AddressInfo, ContextT) -> ()
	) -> SequenceBuilder<ContextT>,
	onLoop: (
		self: SequenceBuilder<ContextT>,
		callback: (PlaybackControl, LoopChange, ContextT) -> ()
	) -> SequenceBuilder<ContextT>,
	compile: (self: SequenceBuilder<ContextT>) -> Sequence<ContextT>,
}
```

## Summary

| Method | Description |
| --- | --- |
| [`duration`](#builder-duration) | Sets the required nonnegative duration |
| [`loop`](#builder-loop) | Enables or disables looping |
| [`event`](#builder-event) | Appends one discrete event |
| [`sample`](#builder-sample) | Appends one absolute sampled interval |
| [`onPlay`](#builder-on-play) | Sets cleanup-generation setup |
| [`onAddress`](#builder-on-address) | Sets address materialization |
| [`onLoop`](#builder-on-loop) | Sets the authored loop observer |
| [`compile`](#builder-compile) | Validates and returns an immutable Sequence |

<a id="pulse-builder"></a>
## Pulse.builder

```luau
Pulse.builder<ContextT>() -> SequenceBuilder<ContextT>
```

Creates an empty builder with looping disabled. Address behavior is intentionally absent: callers
select it when creating or seeking a Playback. Luau infers the parameterless generic constructor
from its expected type:

```luau
local builder: Pulse.SequenceBuilder<PresentationContext> = Pulse.builder()
```

<a id="builder-duration"></a>
### SequenceBuilder:duration

```luau
SequenceBuilder<ContextT>:duration(seconds: number) -> SequenceBuilder<ContextT>
```

Sets the required finite sequence duration and returns the same SequenceBuilder. It must be nonnegative;
zero is valid only for a non-looping Sequence.

<a id="builder-loop"></a>
### SequenceBuilder:loop

```luau
SequenceBuilder<ContextT>:loop(enabled: boolean?) -> SequenceBuilder<ContextT>
```

Enables looping when omitted or `true`, and disables it when `false`.

<a id="builder-event"></a>
### SequenceBuilder:event

```luau
SequenceBuilder<ContextT>:event(event: Event<ContextT>) -> SequenceBuilder<ContextT>
```

Copies and appends an event. Compilation preserves authored order for equal times.

<a id="builder-sample"></a>
### SequenceBuilder:sample

```luau
SequenceBuilder<ContextT>:sample(sample: Sample<ContextT>) -> SequenceBuilder<ContextT>
```

Copies and appends an absolute sampled interval. Samples describe state at the final position; they
do not integrate a delta.

<a id="builder-on-play"></a>
### SequenceBuilder:onPlay

```luau
SequenceBuilder<ContextT>:onPlay(callback: (PlaybackControl, ContextT) -> ()) -> SequenceBuilder<ContextT>
```

Sets the callback that opens the initial generation and every reconstructed generation.

<a id="builder-on-address"></a>
### SequenceBuilder:onAddress

```luau
SequenceBuilder<ContextT>:onAddress(
	callback: (PlaybackControl, AddressInfo, ContextT) -> ()
) -> SequenceBuilder<ContextT>
```

Sets the callback that materializes host-owned state after an initial placement or explicit seek
has established its exact target.

<a id="builder-on-loop"></a>
### SequenceBuilder:onLoop

```luau
SequenceBuilder<ContextT>:onLoop(
	callback: (PlaybackControl, LoopChange, ContextT) -> ()
) -> SequenceBuilder<ContextT>
```

Sets the authored loop callback. It runs before callbacks registered with `Playback:onLooped`.

<a id="builder-compile"></a>
### SequenceBuilder:compile

```luau
SequenceBuilder<ContextT>:compile() -> Sequence<ContextT>
```

Validates the accumulated definition and returns a frozen reusable Sequence. The SequenceBuilder remains a
mutable authoring object; do not mutate it concurrently while compiling.
