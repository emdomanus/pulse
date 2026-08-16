# Managers / TemporalAdapter

<div class="api-path">src/pulse/managers/temporalAdapter/shared/temporalAdapter.luau</div>

<div class="api-meta">
  <span class="api-badge api-badge--public">Public composition object</span>
  <span class="api-badge">Borrowed clock</span>
  <span class="api-badge">Shared phase execution</span>
</div>

TemporalAdapter binds an exact provider clock, host-selected execution phase, and provider direction
tokens into the nongeneric capability used by Playback. It owns Pulse attachments and bindings, not
the clock.

<a id="clock-sample"></a>
## ClockSample

```luau
type ClockSample = {
	timePosition: number,
	rate: number,
	revision: number?,
}
```

`timePosition` and resolved `rate` must be finite. `revision` is optional finite monotonic metadata
used to ignore stale clock changes.

<a id="clock-change"></a>
## ClockChange

```luau
type ClockChange = {
	kind: string?,
	previousTimePosition: number?,
	currentTimePosition: number,
	discontinuous: boolean,
	revision: number?,
}
```

A continuous change preserves mapping continuity and is reconciled before Pulse re-anchors. A
discontinuous change applies the Sequence's AddressPolicy. Provider notifications may expose
revision under their current mapping; the adapter normalizes it into this record.

For a successful discontinuity, Playback reports the resulting target through the Sequence's
`onAddress` callback. The adapter remains unaware of authored materialization behavior.

<a id="direction-tokens"></a>
## DirectionTokens

```luau
type DirectionTokens<DirectionTokenT> = {
	forward: DirectionTokenT,
	backward: DirectionTokenT,
}
```

Opaque tokens passed back to the provider's reached scheduler. They must be distinct. Pulse does not
interpret their representation.

<a id="provider-clock"></a>
## ProviderClock

```luau
type ProviderClock<PhaseInputT, DirectionTokenT> = {
	read: (self) -> unknown,
	bindToChanged: (self, callback: (unknown) -> (), runInitially: boolean?) -> Release,
	isDestroyed: (self) -> boolean,
	bindToReached: (
		self,
		timePosition: number,
		direction: DirectionTokenT,
		callback: (now: number, direction: unknown) -> (),
		phase: PhaseInputT
	) -> number,
	cancel: (self, id: number) -> boolean,
	rescheduleAt: (self, id: number, runAt: number, phase: PhaseInputT) -> boolean,
	bindPhase: (
		self,
		phase: PhaseInputT,
		callback: (clockDt: number, now: number) -> ()
	) -> Release,
}
```

This is a structural input port. `read` must return a valid ClockSample-shaped table. Changed
notifications must include finite `currentTimePosition`, boolean `discontinuous`, optional finite
`previousTimePosition`, optional string `kind`, and optionally a finite current mapping revision.

Pulse uses `bindToReached` for one next authored boundary, `rescheduleAt` when task identity can be
preserved, and `cancel` on lifecycle or direction changes. A current Tempo `Clock` satisfies this
contract.

<a id="temporal-adapter"></a>
## TemporalAdapter

```luau
type TemporalAdapter = {
	destroy: (self: TemporalAdapter) -> (),
	isDestroyed: (self: TemporalAdapter) -> boolean,
}
```

## Summary

| Method | Description |
| --- | --- |
| [`destroy`](#temporal-adapter-destroy) | Releases Pulse ownership and fails attached Playbacks |
| [`isDestroyed`](#temporal-adapter-is-destroyed) | Reads adapter or provider retirement |

<a id="pulse-temporal-adapter"></a>
## Pulse.temporalAdapter

```luau
Pulse.temporalAdapter<PhaseInputT, DirectionTokenT>(
	clock: ProviderClock<PhaseInputT, DirectionTokenT>,
	phase: PhaseInputT,
	directions: DirectionTokens<DirectionTokenT>
) -> TemporalAdapter
```

Constructs an adapter around a live borrowed clock. Construction validates the initial sample but
does not bind to clock changes or the execution phase.

The first playing attachment creates one changed subscription. The final attachment leaving
releases it. Updating members independently acquire one shared phase binding on first entry and
release it when the final updating member leaves. Event-only Playbacks never acquire that binding.

Sharing occurs per adapter instance. Reuse one instance for an exact clock/phase pair instead of
constructing duplicate adapters.

<a id="temporal-adapter-destroy"></a>
### TemporalAdapter:destroy

```luau
TemporalAdapter:destroy() -> ()
```

Idempotently retires the adapter, releases changed and phase bindings, and fails each attached
Playback with reason `adapterDestroyed`. Scheduled tasks are cancelled as those Playbacks detach.
The borrowed provider clock is not destroyed.

<a id="temporal-adapter-is-destroyed"></a>
### TemporalAdapter:isDestroyed

```luau
TemporalAdapter:isDestroyed() -> boolean
```

Returns whether the adapter is retired. If the borrowed clock reports destruction, this call also
retires the adapter and fails attached Playbacks with reason `clockDestroyed`.

Malformed changes, failed reads, and notification work overflow retire adapter-side execution
deterministically rather than allowing a partially live group. Failure in one attached Playback's
internal notification sink fails that Playback without retiring the rest of the adapter group.
