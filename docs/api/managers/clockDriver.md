# Managers / ClockDriver

<div class="api-path">src/pulse/managers/clockDriver/shared/clockDriver.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Optional infrastructure</span>
  <span class="api-badge">Borrowed provider</span>
  <span class="api-badge">Shared scheduling</span>
</div>

`ClockDriver` adapts a scheduling-capable provider to raw
[`Playback`](../components/playback.md#playback). It owns provider reads, subscriptions, deadline
scheduling, phase fan-out, and discontinuity translation. The raw core does not depend on this
module or any provider metadata.

<a id="provider-clock"></a>
## ProviderClock

```luau
type ProviderClock<PhaseInputT, DirectionTokenT> = {
	read: (self: ProviderClock<PhaseInputT, DirectionTokenT>) -> unknown,
	bindToChanged: (
		self: ProviderClock<PhaseInputT, DirectionTokenT>,
		callback: (change: unknown) -> (),
		runInitially: boolean?
	) -> Release,
	isDestroyed: (self: ProviderClock<PhaseInputT, DirectionTokenT>) -> boolean,
	bindToReached: (
		self: ProviderClock<PhaseInputT, DirectionTokenT>,
		position: number,
		direction: DirectionTokenT,
		callback: (now: number, direction: unknown) -> (),
		phase: PhaseInputT
	) -> number,
	cancel: (self: ProviderClock<PhaseInputT, DirectionTokenT>, id: number) -> boolean,
	rescheduleAt: (
		self: ProviderClock<PhaseInputT, DirectionTokenT>,
		id: number,
		position: number,
		phase: PhaseInputT
	) -> boolean,
	bindPhase: (
		self: ProviderClock<PhaseInputT, DirectionTokenT>,
		phase: PhaseInputT,
		callback: (clockDt: number, now: number) -> ()
	) -> Release,
}
```

The permissive `unknown` boundaries let the driver protectively validate provider data. `read()`
must return:

```luau
{
	timePosition: number, -- finite absolute source coordinate
	rate: number, -- finite current source rate
}
```

A changed callback must receive:

```luau
{
	kind: string?,
	previousTimePosition: number?,
	currentTimePosition: number,
	discontinuous: boolean,
}
```

`previousTimePosition` may be omitted, in which case the driver's preceding accepted provider
sample is used. Extra provider fields are ignored. In particular, ClockDriver does not require or
filter a provider revision; its own notification queue defines delivery order.

The provider is borrowed. Pulse never calls a provider destroy method.

<a id="direction-tokens"></a>
## DirectionTokens

```luau
type DirectionTokens<DirectionTokenT> = {
	forward: DirectionTokenT,
	backward: DirectionTokenT,
}
```

The distinct provider tokens used by `bindToReached` and checked when its callback fires.

<a id="driver-discontinuity-mode"></a>
## DriverDiscontinuityMode

```luau
type DriverDiscontinuityMode = "skip" | "reconstruct" | "cancel"
```

An attachment-local host decision. `skip` and `reconstruct` translate to the corresponding raw
`Playback:seek`; `cancel` calls `Playback:cancel("clockDiscontinuity")`. This choice is never read
from Sequence content.

<a id="clock-driver-attachment-options"></a>
## ClockDriverAttachmentOptions

```luau
type ClockDriverAttachmentOptions = {
	discontinuityMode: DriverDiscontinuityMode,
}
```

The mode is required; ClockDriver intentionally has no broad discontinuity default.

<a id="clock-driver"></a>
## ClockDriver

```luau
type ClockDriver = {
	attach: (
		self: ClockDriver,
		playback: Playback,
		options: ClockDriverAttachmentOptions
	) -> DrivenPlayback,
	destroy: (self: ClockDriver) -> (),
	isDestroyed: (self: ClockDriver) -> boolean,
}
```

<a id="pulse-clock-driver"></a>
## Pulse.clockDriver

```luau
Pulse.clockDriver<PhaseInputT, DirectionTokenT>(
	clock: ProviderClock<PhaseInputT, DirectionTokenT>,
	phase: PhaseInputT,
	directions: DirectionTokens<DirectionTokenT>
) -> ClockDriver
```

Validates an initial provider read and constructs an inert grouping for the exact borrowed clock,
phase, and direction tokens. The changed subscription is acquired lazily when the first attached
Playback starts.

Use one driver for playbacks sharing that exact grouping. Event-only attachments own one next
source-boundary task during ordinary traversal. An attachment joins phase fan-out when an exact
Sample is active, when backward movement is poised at a Sample's excluded `endTime`, or while an
outward zero-distance loop join awaits actual source movement. A synchronous callback-side
`PlaybackControl:resume()` also joins phase fan-out transiently until its first post-resume sample.
All phase-required attachments share one `bindPhase`; the last one leaving releases it. The
excluded endpoint still emits no Sample. After a pending resume is sampled, an event-only
attachment leaves phase fan-out and schedules its next deadline; a pending join does the same after
its first real movement. Completion boundaries remain schedulable when phase observation is not
required.

Each attachment tracks the absolute source coordinate and direction of its reached task. An
ordinary phase notification reads the provider once for the shared fan-out. Unchanged attachment
forecasts, including coordinates that differ only by bounded binary64 rounding, reuse that snapshot
and keep the existing task and its original cached coordinate without calling `rescheduleAt` or
performing attachment-local reads. Reached checks use the cached coordinate where the provider task
is actually bound. Only a newly created or materially changed deadline receives a post-schedule
provider read so movement during `bindToReached` or `rescheduleAt` is reconciled.

<a id="clock-driver-attach"></a>
### ClockDriver:attach

```luau
ClockDriver:attach(
	playback: Playback,
	options: ClockDriverAttachmentOptions
) -> DrivenPlayback
```

Attaches an idle raw Playback and returns its clock-driven facade. Attachment transfers exclusive
temporal-control ownership to that `DrivenPlayback` until `detach()`. The original raw reference
must not be mutated while attached: direct raw control bypasses current-provider reconciliation and
can stale the driver's scheduling state. A raw Playback may have at most one driver attachment at a
time, and attaching to a destroyed driver raises. Attachment itself does not start the lifecycle or
subscribe; register observers and call `DrivenPlayback:play()`.

<a id="clock-driver-destroy"></a>
### ClockDriver:destroy

```luau
ClockDriver:destroy() -> ()
```

Releases reached tasks, the shared phase binding, and the changed subscription. Each still-attached
live Playback fails with reason `driverDestroyed`. The borrowed provider remains alive.

<a id="clock-driver-is-destroyed"></a>
### ClockDriver:isDestroyed

```luau
ClockDriver:isDestroyed() -> boolean
```

Returns whether the driver has terminated. If the provider reports destruction, this call also
terminates the driver and attached live Playbacks with reason `clockDestroyed`.

<a id="driven-playback"></a>
## DrivenPlayback

```luau
type DrivenPlayback = {
	play: (self: DrivenPlayback) -> DrivenPlayback,
	pause: (self: DrivenPlayback) -> (),
	resume: (self: DrivenPlayback) -> (),
	setPlaybackSpeed: (self: DrivenPlayback, speed: number) -> (),
	getPlaybackSpeed: (self: DrivenPlayback) -> number,
	seek: (self: DrivenPlayback, address: SequenceAddress, mode: AddressMode) -> boolean,
	getPosition: (self: DrivenPlayback) -> PlaybackPosition,
	getStatus: (self: DrivenPlayback) -> Status,
	addCleanup: (self: DrivenPlayback, cleanup: () -> ()) -> (),
	cancel: (self: DrivenPlayback, reason: string?) -> (),
	destroy: (self: DrivenPlayback) -> (),
	onEnded: (self: DrivenPlayback, callback: EndedCallback) -> Release,
	onLooped: (self: DrivenPlayback, callback: LoopedCallback) -> Release,
	isAlive: (self: DrivenPlayback) -> boolean,
	getCompletion: (self: DrivenPlayback) -> Completion?,
	detach: (self: DrivenPlayback) -> Playback,
}
```

The facade deliberately omits raw `evaluate`: the driver is its source authority. `play` reads the
provider and supplies the first core sample. Phase, reached, and changed notifications subsequently
evaluate serialized snapshots. Until detach, retain the raw handle only as an ownership identity;
perform host-side lifecycle and timeline mutations through this facade.

### Mutation reconciliation

While playing, externally requested `pause`, `setPlaybackSpeed`, `seek`, `addCleanup`, `cancel`,
`destroy`, and `detach` first read/evaluate the current provider sample, then mutate the core at
that accepted coordinate. `resume` reads the current provider sample after setting the core's
no-catch-up resume state, so the stored paused position is re-anchored there. Read-only methods
return core state and do not introduce implicit evaluation.

Methods called on `DrivenPlayback` enter the driver notification queue. A `PlaybackControl` passed
to an authored Pulse callback is different: it remains valid for synchronous control inside that
callback, and its mutations enter the raw Playback operation queue. When the enclosing evaluation
returns, ClockDriver refreshes phase membership and scheduling before continuing queued provider
work. A callback-side resume that lacks a current driver snapshot requests one transient phase
sample; that sample re-anchors without catch-up, after which an event-only playback returns to
deadline scheduling. Do not retain that callback control and invoke it asynchronously while driven;
use the `DrivenPlayback` facade for later control. Provider mutations triggered by callbacks enter
the driver queue and are serialized rather than recursively interleaved.

### Provider changes

For a continuous change, ClockDriver reconciles the delivered previous mapping boundary before the
current boundary and latest provider sample, then refreshes scheduling with the new rate.

For `discontinuous = true`, it:

1. evaluates natural elapsed movement through `previousTimePosition` using the preceding sample;
2. projects the delivered current source coordinate to an explicit sequence target without
   naturally traversing the jump;
3. applies the attachment's required `skip`, `reconstruct`, or `cancel` response;
4. evaluates any natural tail between the delivered current boundary and the latest read.

Stale reached callbacks carry an internal task generation and are discarded after replacement or
retirement. A currently firing reached task is rescheduled in place when possible and replaced when
not. A reached callback and phase callback for the same provider sample do not duplicate final
sampling.

<a id="driven-playback-detach"></a>
### DrivenPlayback:detach

```luau
DrivenPlayback:detach() -> Playback
```

Reconciles the current provider sample while playing, releases this attachment's scheduling
membership, returns temporal-control ownership, and returns the still-live raw Playback. The caller
becomes responsible for future `evaluate` calls. Later methods on the retired facade do not
reattach it.
