# Pulse Temporal Scheduling Amendment

**Status:** Approved as the execution contract on 2026-08-15 and accelerated
before implementation. Intermediate migration commits may be broken;
compatibility and full verification are required only at the final milestone.
Continuous reverse playback and correctness-first timed-step history retention
remain accepted for v1.

**Reviewed 2026-08-12 against:** Pulse `1914abf0` (`0.3.0`), Tempo
`7452b56c` (`0.4.0`), and VoxelMMO TemporalService at the current ServiceDev
working tree. Tempo and VoxelMMO are read-only inputs to this amendment.

Pulse currently has an unrelated working-tree edit in
`dev/client/init.client.luau` (one added blank line after the Tempo require).
Preserve that edit. Do not revert, stage, or absorb it into an amendment
checkpoint.

## Why this is changing

Pulse currently advances every playback by accumulating a phase callback's
frame `dt` inside a package-wide loop. That model neither reads a timeline
clock nor uses Tempo's shared deadline scheduler. It makes an event-only hit
effect pay a frame callback, makes a runtime bind continuously even with no
live playback, and cannot distinguish a continuous clock-rate change from a
position discontinuity.

The amendment makes Pulse a clock consumer rather than a temporal-runtime
owner. A playback borrows one scheduling-capable clock and one explicitly
chosen phase. Pulse owns sequence cursors, anchors, next-event selection,
catch-up, local playback speed, and playback lifecycle. The borrowed clock
owns clock position, change notification, shared scheduling, and phase
evaluation. VoxelMMO owns composition and chooses the phase; authored content
does not receive a TemporalService, a TempoRuntime, or a VoxelMMO phase name.

## Approved v1 rulings

- Pulse contains no VoxelMMO service, character, presentation, networking,
  replication, prediction, or authority concept.
- Pulse does not accept TemporalService or TempoRuntime. It accepts a narrow
  structural `Clock<PhaseT, DirectionT>` capability that a Tempo
  `Clock<PhaseT>` can satisfy without a runtime wrapper.
- The borrowed clock is never deconstructed, cleared, controlled, or retained
  beyond the Pulse runtime/playback lifetime that borrowed it.
- Every play request supplies an explicit clock and explicit phase. Pulse
  never reads a clock's default phase.
- Pulse schedules the next sequence checkpoint because Pulse alone knows the
  event cursor, loop boundary, and completion boundary. Tempo continues to own
  the shared scheduler implementation and physical phase pump.
- Event-only playbacks have scheduled work but no continuous phase binding.
- Updating playbacks join a clock/phase group. A group owns at most one
  continuous binding, acquired by the first active updating playback and
  released by the last.
- Playback time is derived from a clock-position anchor. A phase callback's
  supplied `dt` is not used to advance sequence time.
- `playbackSpeed` is a finite signed sequence-local multiplier. Effective
  sequence direction is clock traversal direction multiplied by the sign of
  local speed. A speed or clock-rate sign change samples the old mapping,
  reanchors at the same sequence position, selects the checkpoint in the new
  direction, and reschedules.
- Continuous reverse traversal is not a seek and never substitutes forward
  callbacks for undo. Events and timed steps carry explicit reverse behavior;
  a missing reverse action cancels safely at the boundary by default.
- Pulse reverses traversal and its own recorded step state, not arbitrary
  authored side effects. An event/step reverse callback owns external undo.
- `ctx:addCleanup` remains playback/rebuild-generation cleanup and is not an
  automatic per-occurrence rollback mechanism. Occurrence-specific external
  state belongs to authored parameters, callback closures, or host-injected
  context rather than another Pulse ownership surface.
- Pause samples and stores the current sequence position, cancels deadline
  work, and leaves continuous execution. Resume anchors that stored position
  to the then-current clock position before scheduling or rejoining.
- A reported continuous clock mapping change preserves the anchor and
  position. A reported discontinuity follows the sequence's declared policy.
- No catch-up cap may silently fold away events. A safety limit may fail a
  playback explicitly; cooperative catch-up budgeting is deferred.
- `Ended` is logical timeline termination. Pulse commits and publishes one
  immutable completion immediately, then performs `cleanupDelay` as private
  real-time retention after the playback has left its clock group.
- User callbacks remain protected by Pulse. Tempo's callback-protection option
  is not part of Pulse's correctness contract.
- Removed names receive no aliases. The old runtime/options signatures and the
  old seek methods are deleted rather than shadowed by compatibility methods.

The decisions at the end of this document are closed by operator approval. This
file is the stable execution contract for accelerated milestones M0 through M3;
changes to these rulings require an explicit design amendment rather than
worker inference.

## Current contract and fact base

### Repository and tooling state

- Pulse has no `AGENTS.md`, no `docs/` tree before this file, no automated test
  suite, no `package.json`, and no documentation build command.
- `aftman.toml` pins only Rojo. There are no tracked verification scripts.
- The interactive Studio client in `dev/client/init.client.luau` is the only
  behavior harness. It exercises a looping atom, gated holds, cleanup linger,
  pause/resume, speed changes, parameter changes, seeking, cancellation, and
  destruction.
- Pulse `pesde.toml` declares `emdomanus/tempo ^0.2.0`, and `pesde.lock`
  resolves exactly Tempo `0.2.0`.
- Tempo is now `0.4.0` at `7452b56c`. Its consumer `Clock` combines reading,
  change notification, scheduling, cancellation, rescheduling, and phase
  binding while withholding data, control, bulk clear, and teardown.
- VoxelMMO pins that Tempo commit as `tempo`. TemporalService returns a narrow
  `Tempo.Clock<StepPhase>` and privately owns the corresponding
  `ClockOwned<StepPhase>`.
- TemporalService clocks default new unphased work to `writeReplication`.
  Pulse must therefore pass the VoxelMMO-selected phase on every
  `bindToReached`, `rescheduleAt`, and `bindPhase` call instead of inheriting
  that default.
- VoxelMMO has no authored Pulse import or dependency at review time.

### Existing public shape

The current root exports Tempo's `Clock`, `Phase`, `PhaseName`, and `Tempo`
types, `RuntimeOptions<PhaseT>`, `SeekMode`, `SeekRequest`, sequence/builder
types, `Playback`, and `Runtime<PhaseT>`. Construction is:

```luau
local runtime = Pulse.runtime.new({
	tempo = tempo,
	phase = tempo.phases.heartbeat,
})

local playback = runtime:play(sequence, request)
```

`RuntimeManager.new` immediately binds one callback to the requested phase,
or to `options.tempo.phases.heartbeat` when the phase is omitted. That callback
walks all playbacks every frame and calls `Playback:_update(dt)`. The binding
exists until `Runtime:destroy()` regardless of playback count or sequence
kind.

`Playback:_update` advances `_timePosition` by
`dt * _playbackSpeed`, drains events through that accumulated value, invokes
all update callbacks, checks duration, and subtracts the same phase `dt` from
cleanup linger. Neither the exported `Clock` type nor Tempo scheduling is used
by playback code.

### Verified defects and contract mismatches

These findings are established directly by the current implementation, not by
the target design:

| Finding | Evidence and consequence |
| --- | --- |
| No playback clock | `RuntimeOptions` stores a Tempo runtime and phase; `Playback` stores no clock or anchor. Clock position, rate, revision, and discontinuity are unobservable to Pulse. |
| Default phase leak | `runtimeManager.luau` falls back to Tempo heartbeat. Mechanical migration to a TemporalService clock would instead inherit VMMO's `writeReplication`, which is also wrong for presentation. |
| Permanent continuous work | Runtime construction binds immediately and runtime destruction releases it. Zero-playback and event-only runtimes still execute every phase. |
| Sharing has the wrong boundary | One current runtime shares one loop, but two runtimes on the same clock/phase bind independently. There is no clock identity or phase group. |
| Timeline is frame accumulation | `_update` adds frame `dt * playbackSpeed`. Clock rate changes, source position, frozen clocks, and discontinuities cannot be represented. |
| Update delta is inconsistent | Sequence position advances by scaled `dt`, while an update callback receives unscaled frame `dt`. The callback does not receive sequence timeline delta. |
| Cleanup's advertised clock is implicit | README calls `cleanupDelay` real-time, but the implementation subtracts whichever phase `dt` drives the runtime. The source is not named or independently cancellable. |
| Seek policy can be widened per call | `seekTo` selects `request.mode or sequence.seekMode`, so a request can replace a sequence's authored restriction. |
| Duplicate seek surface | `setTimePosition` forwards to the same internal operation as `seek`, while `SeekRequest` also mixes time addressing, step transition, payload, policy override, and replay. |
| Paused/idle replay is partial | `runEventsThrough` stops whenever status is not `playing`. `seek({ replay = true })` while paused or idle consumes at most the first replayed event. |
| Rebuild is not defined | Backward seek moves the cursor but does not clear or reconstruct sequence-owned effects. Replay runs callbacks without a reset contract, so it can duplicate side effects and cleanup registrations. |
| Loop overflow fold is incorrect | When `MAX_LOOP_CATCH_UP` is exceeded, `nextTime %= duration` then breaks without applying the folded value to `_timePosition` or the cursor. The README claim that overflow is folded into the current loop is false. |
| Silent event loss is policy | The loop cap deliberately stops replaying skipped cycles. A hit, step, or cleanup-significant event can disappear without a terminal error or observer signal. |
| Completion is mutable after notification | Natural completion with cleanup delay fires `Ended` while status is `stopping`. A later cleanup error mutates the same completion to `failed` without another notification. |
| Observer iteration is reentrant-unsafe | Callback maps are iterated directly. A listener that disconnects or adds listeners during dispatch can affect the same traversal. |
| Public data is mutable | Compiled sequences expose mutable event, update, step, transition, signal, default-param, and definition tables. Compilation normalizes but does not freeze the public contract. |
| Type boundaries are broad | Core implementations use `any` for playback links, sequence internals, callback invocation, completion errors, and construction casts. The package has no analyzer gate proving its public generics. |
| No race suite exists | There are no tests for deadline reentrancy, discontinuity-before-dispatch, cancellation during callbacks, group release, or teardown. |

### Tempo 0.4 behavior relevant to Pulse

- `Clock:read()` returns live local `timePosition` and effective `rate`.
- `Clock:bindToChanged()` publishes package-classified `discontinuous` plus the
  authoritative before/after local positions for one logical change boundary.
- Continuous rate changes publish equal before/after positions and
  `discontinuous = false`.
- `Clock:bindToReached()` schedules an absolute local-clock boundary with an
  explicit forward/backward direction token and reports the actual crossing
  direction to the callback.
- `Clock:rescheduleAt()` can reschedule a running reached record from inside its
  own callback; the Tempo record remains active when it has been reinserted and
  retains its originally bound reached direction.
- `Clock:cancel()` is safe for active and running records and reports whether
  active work was found.
- `Clock:bindPhase()` returns an idempotent release and supplies clock-domain
  delta and current position. Pulse will use the current position and derive
  its own sequence delta rather than multiplying the supplied delta by rate.
- Tempo's scheduler already recalculates root wake times on reader changes.
  Pulse does not duplicate that scheduler math.
- Tempo drains due tasks before continuous callbacks for the same clock and
  phase, then drains newly due work again. Pulse's event callback can therefore
  reconcile the cursor before the group's update pass in the same phase.
- Tempo creates scheduler state lazily. A scheduled event does not imply a
  per-frame callback; a continuous phase callback does.

### TemporalService behavior relevant to composition

- TemporalService owns all physical RunService connections and steps one Tempo
  runtime across its ordered `StepPhase` set.
- `getWorldClock()` and child factories return consumer-safe clocks; Pulse must
  not receive the service merely to reach one.
- Every TemporalService-created clock has default phase `writeReplication`.
- VoxelMMO composition must pass the desired canonical phase token/name to
  Pulse. Presentation is expected to choose a presentation phase internally;
  authored sequence content must not choose it.
- TemporalService destroys child clocks descendants-first. A destroyed clock
  removes its Tempo scheduler state and publishes a terminal clock change.
  Pulse must terminate affected borrowed playbacks without attempting to own
  clock teardown.
- TemporalService's sampled server-time source resamples every two seconds.
  Raw time-source movement does not itself create a Tempo mapping change; the
  consequence for discontinuity classification is a blocker below.

## Exact old Tempo dependency and removal inventory

The production package should no longer require Tempo at runtime or re-export
Tempo-owned types. The new Pulse clock type is structural.

Delete or change every tracked dependency point below in the same breaking
migration:

**KEEP TEMPO through M0, M1, and M2.** The currently exported Pulse runtime and
development laboratory still import the 0.2 adapter. M3 removes the production
dependency after replacement source no longer imports it, adds current Tempo to
the supported development-only conformance environment, and regenerates the
lock. No Pesde install is required before M0.

1. `pesde.toml`
   - remove `[dependencies].tempo = emdomanus/tempo ^0.2.0`;
   - keep Tempo out of production requirements and the published Pulse
     artifact;
   - add the current Tempo revision only through the supported development/test
     dependency mechanism for the permanent conformance fixture.
2. `pesde.lock`
   - regenerate through Pesde after the manifest change;
   - remove the old `emdomanus/tempo@0.2.0 roblox` production graph entry;
   - a current Tempo entry may remain when it is reachable only from the
     development conformance environment.
3. `src/externalPackages/tempo.luau`
   - delete the adapter completely.
4. `src/pulse/types/def/init.luau`
   - remove the Tempo require;
   - remove the forwarding `Clock`, `Phase`, `PhaseName`, and `Tempo` aliases;
   - replace them with Pulse-owned structural clock records and callbacks;
   - replace `RuntimeOptions` and the current seek contracts.
5. `src/pulse/types/init.luau`, `src/pulse/init.luau`, and `src/init.luau`
   - remove Tempo type forwarding;
   - re-export the Pulse-owned clock capability from the canonical type
     surface only.
6. `src/pulse/types/managers/runtimeManager/init.luau`
   - remove `Runtime<PhaseT>`, `_options`, and the single `_unbind` model;
   - replace them with a non-phase-generic runtime whose generic
     `createPlayback` accepts a clock, direction tokens, and phase per playback.
7. `src/pulse/managers/runtimeManager/shared/runtimeManager.luau`
   - delete the Tempo-runtime option, heartbeat fallback, eager `bindPhase`,
     and whole-runtime frame loop;
   - add clock ownership records and clock/phase groups described below.
8. `README.md`
   - remove Tempo as a required Pulse dependency;
   - replace the TempoRuntime construction example with borrowed-clock
     composition;
   - document the phase, anchor, discontinuity, and timer contracts.
9. `dev/client/init.client.luau`
   - later replace the old `Tempo.new`/`evaluatePhase` 0.2 laboratory setup
     with the chosen development clock harness;
   - preserve the pre-existing blank-line edit byte-for-byte in intent and do
     not stage it as part of this review;
   - because this file is already dirty, show its final diff separately before
     any implementation checkpoint that needs to touch it.

Ignored/generated local state also contains the old package graph and built
source (`roblox_packages/`, `dev-sourcemap.json`, `sourcemap.json`,
`pulse-dev.rbxlx`, `package.tar.gz`). Refresh it only through the owning tools
after the authored migration. Do not commit generated output.

## Ownership and lifecycle model

```text
host composition (for VMMO: a presentation/gameplay facade)
  |-- owns TemporalService access and selects a clock + execution phase
  |-- owns the Pulse Runtime lifetime
  '-- creates Playback with { clock, directions, phase, ... }, binds observers,
      then calls Playback:play()

Pulse Runtime
  |-- borrows clocks; never controls or destroys them
  |-- owns ClockState records selected by exact clock identity
  |     |-- one clock-change release
  |     '-- PhaseGroup records by explicit phase identity
  |            |-- all live playbacks for that clock/phase
  |            |-- active updating playbacks
  |            '-- zero or one continuous phase release
  |-- owns Playback objects
  '-- owns real-time disposal timers and retained terminal playbacks

Playback
  |-- owns its anchor, boundary-side cursors, signed loop index, reached task
  |   id, occurrence journal, params, listeners, cleanup generation, and
  |   callback-reentrancy state
  |-- schedules only through its borrowed clock
  '-- releases all runtime/group membership before terminal teardown

Tempo / another conforming clock provider
  |-- owns clock readings and change classification
  |-- owns shared scheduled-task records and phase evaluation
  '-- owns its clock lifecycle outside Pulse
```

Creation and teardown rules:

1. `Pulse.new()` creates an empty Runtime. It creates no clock state and binds
   no phase.
2. `Runtime:createPlayback` validates a live clock, finite initial values,
   sequence invariants, explicit clock-direction tokens, and an explicit
   phase. It returns an `idle` Playback without invoking user code, scheduling
   work, subscribing to the clock, or binding a phase.
3. Callers bind observers, then call `Playback:play()`. Only `play` joins clock
   and phase records and invokes initial addressing, `onPlay`, and time-zero
   work. A callback may pause, seek, stop, cancel, destroy, signal,
   change speed, reverse direction, or create another playback without
   corrupting the outer traversal.
4. A playing playback owns at most one scheduled task id. It is reused by
   rescheduling from inside the deadline callback when another checkpoint
   exists.
5. A paused playback owns no deadline task and no updating-group membership,
   but remains signalable and retains its borrowed clock identity.
6. A naturally completed playback leaves the clock state, commits terminal
   `completed`, and fires `Ended` immediately. Runtime may retain it privately
   while its active cleanup generation waits in real time; public status and
   completion do not change during that retention.
7. Stop, cancel, failure, clock destruction, playback destruction, and runtime
   destruction cancel timeline work and dispose immediately. Destroying a
   Runtime or Playback during post-completion retention flushes cleanup but
   does not replace the already-published `completed` result.
8. When the last active updating playback leaves a phase group, the group
   releases its phase binding synchronously.
9. When the last playback leaves a clock, Runtime releases the clock-change
   subscription and removes the clock record.
10. `Runtime:destroy()` first prevents new playbacks, then snapshots and
    destroys live playbacks, flushes retained terminal playbacks, releases
    remaining group/change bindings, cancels real-time timers, and clears
    records. It never destroys a clock.

## Proposed public types and API

The names and shapes in this section are the proposed breaking public
contract. Implementation types remain in their owning modules, use `XImpl`,
and are not root exports. Root modules re-export contracts from `types/`
without redeclaring them.

Root export delta is explicit:

- remove Tempo-owned `Phase`, `PhaseName`, and `Tempo`, plus old
  `RuntimeOptions`, `PlayRequest`, `SeekMode`, `SeekRequest`,
  `CompletionReason`, `CallbackMap`, `PlaybackCallbacks`, and the
  `Context<any>`-based `CallbackContext`;
- redefine `Clock`, `Status`, `Completion`, `Params`, callback aliases,
  `Context`, `TransitionRule`, `Step`, `Steps`, `Event`, `Update`,
  `SignalHandler`, `Definition`, `Sequence`, `Builder`, `Playback`, and
  nongeneric `Runtime` to the contracts below;
- add `Release`, `ScheduledTaskId`, `ClockSample`, `ClockChange`,
  `ClockChangedCallback`, `PhaseCallback`, `ReachedCallback`,
  `ClockDirections`, `RealTimeScheduler`, `RuntimeConfig`, `SequenceAddress`,
  `PlaybackPosition`, `TraversalDirection`, `AddressDirection`, `LoopChange`,
  `PlaybackOptions`, `ActiveStatus`, `TerminalStatus`, `AddressPolicy`,
  `AddressCause`, both reverse-action types, `StepChangeCause`, `StepChange`,
  `RebuildRequest`, and `RebuildState`.

### Borrowed clock capability

```luau
export type Release = () -> ()
export type ScheduledTaskId = number

export type ClockSample = {
	timePosition: number,
	rate: number,
}

export type ClockChange = {
	previousTimePosition: number?,
	currentTimePosition: number,
	discontinuous: boolean,
}

export type ClockChangedCallback = (change: ClockChange) -> ()
export type PhaseCallback = (clockDt: number, now: number) -> ()
export type ReachedCallback<DirectionT> = (now: number, direction: DirectionT) -> ()

export type ClockDirections<DirectionT> = {
	forward: DirectionT,
	backward: DirectionT,
}

export type Clock<PhaseT, DirectionT> = {
	read: (self: Clock<PhaseT, DirectionT>) -> ClockSample,
	bindToChanged: (
		self: Clock<PhaseT, DirectionT>,
		callback: ClockChangedCallback,
		runInitially: boolean?
	) -> Release,
	isDestroyed: (self: Clock<PhaseT, DirectionT>) -> boolean,

	bindToReached: (
		self: Clock<PhaseT, DirectionT>,
		timePosition: number,
		direction: DirectionT,
		callback: ReachedCallback<DirectionT>,
		phase: PhaseT
	) -> ScheduledTaskId,
	cancel: (self: Clock<PhaseT, DirectionT>, id: ScheduledTaskId) -> boolean,
	rescheduleAt: (
		self: Clock<PhaseT, DirectionT>,
		id: ScheduledTaskId,
		runAt: number,
		phase: PhaseT
	) -> boolean,
	bindPhase: (
		self: Clock<PhaseT, DirectionT>,
		phase: PhaseT,
		callback: PhaseCallback
	) -> Release,
}
```

Pulse intentionally requires neither `now` in addition to `read`, nor
`at`/`delay` in addition to direction-aware reached scheduling, nor
`getMapping`, `reader`, `phases`, control, bulk clear, or deconstruction. The
implementation always supplies the phase argument to `bindToReached`,
`rescheduleAt`, and `bindPhase`.

Tempo uses opaque direction tokens rather than direction strings. Pulse does
not import or manufacture those tokens: composition passes the clock provider's
`ClockDirections<DirectionT>` beside the borrowed clock. For Tempo this is a
narrow record containing `Tempo.Enums.Direction.forward` and `.backward`.

An implementation checkpoint must include a type-only conformance fixture
that passes a current Tempo `Clock<StepPhase>` as this capability with
`PhaseT = Tempo.PhaseInput<StepPhase>` and `DirectionT = Tempo.Direction`. If
Luau's nested callback variance rejects the minimal records, fix the structural
declaration without importing Tempo into production or adding a runtime
wrapper.

### Laws required of a conforming clock

The structural shape alone is insufficient. A clock passed to Pulse must obey
all of these behavioral laws:

- `read()` returns one live, finite clock position and its signed effective
  rate. Rate sign describes expected clock traversal direction; actual reached
  callback direction remains authoritative for a crossing.
- `bindToChanged()` synchronously reports mapping changes with before/after
  positions from one logical boundary. A continuous magnitude or sign change
  reports equal positions and `discontinuous = false`; an address jump reports
  `discontinuous = true`; destruction makes `isDestroyed()` true before or
  during its terminal notification. Pulse subscribes with
  `runInitially = false`; every later discontinuous notification must supply a
  finite
  `previousTimePosition`, or Pulse fails the affected playback with
  `invalidClockChange` because the sequence target cannot be derived safely.
- Pending local deadlines retime automatically when a continuous clock mapping
  changes. Pulse owns sequence checkpoint selection, not root-time conversion.
- `bindToReached(target, direction, callback, phase)` creates a one-crossing
  record and fires only when the clock crosses `target` in the supplied clock
  direction. The callback reports actual clock direction, not resulting
  sequence direction. The record finishes after that callback unless the
  callback successfully reschedules it.
- Forward crossing is `previous < target <= current`; backward crossing is
  `previous > target >= current`. Registration exactly on a target does not
  invent a crossing. Pulse's boundary-side cursor handles direction pivots at
  equality explicitly.
- `rescheduleAt()` can move an active reached record, including from inside its
  callback, without changing that record's direction. A clock-direction sign
  change therefore requires Pulse to cancel and bind a new record with the
  other direction token.
- `cancel()` is idempotent by result: it returns `true` exactly once for active
  work, prevents later callbacks, and is safe while the callback is running.
- `bindPhase()` returns an idempotent release and supplies signed clock-domain
  delta plus current clock position on every evaluation of the explicit phase.
- The injected forward/backward direction tokens are distinct and bind the
  corresponding reached semantics above. Pulse treats them as opaque identity
  values and never constructs or interprets provider tokens.

Tempo's current Clock and scheduler satisfy these laws. The permanent
conformance suite pins both structural compatibility and the relevant runtime
behavior rather than assuming a same-shaped fake is sufficient.

### Runtime and playback construction

```luau
export type RealTimeScheduler = {
	delay: (
		self: RealTimeScheduler,
		seconds: number,
		callback: () -> ()
	) -> Release,
}

export type RuntimeConfig = {
	realTimeScheduler: RealTimeScheduler?,
}

export type SequenceAddress = {
	timePosition: number,
	loopIndex: number?,
}

export type PlaybackPosition = {
	timePosition: number,
	loopIndex: number,
	unwrappedTimePosition: number,
}

export type TraversalDirection = "forward" | "backward"
export type AddressDirection = TraversalDirection | "stationary"

export type LoopChange = {
	fromLoopIndex: number,
	toLoopIndex: number,
	direction: TraversalDirection,
}

export type Params = { [string]: unknown }

export type PlaybackOptions<StepT, PhaseT, DirectionT> = {
	clock: Clock<PhaseT, DirectionT>,
	directions: ClockDirections<DirectionT>,
	phase: PhaseT,
	params: Params?,
	playbackSpeed: number?,
	position: SequenceAddress?,
	step: StepT?,
}

export type Runtime = {
	createPlayback: <StepT, PhaseT, DirectionT>(
		self: Runtime,
		sequence: Sequence<StepT>,
		options: PlaybackOptions<StepT, PhaseT, DirectionT>
	) -> Playback<StepT>,
	destroy: (self: Runtime) -> (),
}
```

Root value construction becomes `Pulse.new(config?) -> Runtime`.
`Pulse.runtime.new`, `RuntimeOptions`, `Runtime<PhaseT>`, and `autoPlay` are
removed. `Runtime:createPlayback` is the only factory and never begins user
work. The caller binds observers, then calls `Playback:play()`. This restores a
deliberate observation boundary without restoring `autoPlay` or adding a
second convenience `Runtime:play` path. A late `onEnded` subscriber is still
invoked immediately with stored completion.

The optional real-time scheduler defaults to a small adapter over
`task.delay`/`task.cancel`. Injection exists for deterministic tests and hosts
with a stronger timer owner; it does not affect timeline progression.

### Playback lifecycle and addressing

```luau
export type ActiveStatus = "idle" | "playing" | "paused"
export type TerminalStatus =
	"completed" | "stopped" | "cancelled" | "destroyed" | "failed"
export type Status = ActiveStatus | TerminalStatus

export type Completion = {
	status: TerminalStatus,
	reason: string?,
	error: unknown?,
}

export type EndedCallback = (completion: Completion) -> ()
export type LoopedCallback = (change: LoopChange) -> ()
export type ParamChangedCallback =
	(name: string, value: unknown, oldValue: unknown?) -> ()
export type SignaledCallback = (name: string, payload: unknown?) -> ()

export type Playback<StepT = StepId> = {
	play: (self: Playback<StepT>) -> Playback<StepT>,
	pause: (self: Playback<StepT>) -> (),
	resume: (self: Playback<StepT>) -> (),
	stop: (self: Playback<StepT>, reason: string?) -> (),
	cancel: (self: Playback<StepT>, reason: string?) -> (),
	destroy: (self: Playback<StepT>) -> (),

	onEnded: (self: Playback<StepT>, callback: EndedCallback) -> Release,
	onLooped: (self: Playback<StepT>, callback: LoopedCallback) -> Release,
	onParamChanged: (self: Playback<StepT>, callback: ParamChangedCallback) -> Release,
	onSignaled: (self: Playback<StepT>, callback: SignaledCallback) -> Release,

	isAlive: (self: Playback<StepT>) -> boolean,
	getStatus: (self: Playback<StepT>) -> Status,
	getCompletion: (self: Playback<StepT>) -> Completion?,

	setParam: (self: Playback<StepT>, name: string, value: unknown) -> (),
	getParam: (self: Playback<StepT>, name: string) -> unknown,
	setParams: (self: Playback<StepT>, params: Params) -> (),
	signal: (self: Playback<StepT>, name: string, payload: unknown?) -> (),

	getStep: (self: Playback<StepT>) -> StepT?,
	canStep: (self: Playback<StepT>, step: StepT?, payload: unknown?) -> (boolean, string?),
	step: (self: Playback<StepT>, step: StepT?, payload: unknown?) -> (boolean, string?),

	setPlaybackSpeed: (self: Playback<StepT>, speed: number) -> (),
	getPlaybackSpeed: (self: Playback<StepT>) -> number,
	seek: (self: Playback<StepT>, address: SequenceAddress) -> boolean,
	getPosition: (self: Playback<StepT>) -> PlaybackPosition,
}

export type Context<StepT = StepId> = {
	getPosition: (self: Context<StepT>) -> PlaybackPosition,
	seek: (self: Context<StepT>, address: SequenceAddress) -> boolean,

	getPlaybackSpeed: (self: Context<StepT>) -> number,
	setPlaybackSpeed: (self: Context<StepT>, speed: number) -> (),

	getStep: (self: Context<StepT>) -> StepT?,
	canStep: (self: Context<StepT>, step: StepT?, payload: unknown?) -> (boolean, string?),
	step: (self: Context<StepT>, step: StepT?, payload: unknown?) -> (boolean, string?),

	getParam: (self: Context<StepT>, name: string) -> unknown,
	setParam: (self: Context<StepT>, name: string, value: unknown) -> (),
	signal: (self: Context<StepT>, name: string, payload: unknown?) -> (),
	addCleanup: (self: Context<StepT>, cleanup: () -> ()) -> (),

	pause: (self: Context<StepT>) -> (),
	resume: (self: Context<StepT>) -> (),
	getStatus: (self: Context<StepT>) -> Status,
	stop: (self: Context<StepT>, reason: string?) -> (),
	cancel: (self: Context<StepT>, reason: string?) -> (),
	destroy: (self: Context<StepT>) -> (),
}
```

There is no `Runtime:play`, `autoPlay`, `setTimePosition`, request-level address
policy, request-level replay flag, or seek-time step/payload field. Step
transitions remain a separate semantic operation. `Context` exposes only the
safe playback operations above, never Runtime, clock, observer, or ownership
capabilities. Duplicate `isPlaying`/`isPaused` queries are removed in favor of
`getStatus`; `isAlive` remains because it names the ownership/lifecycle question
rather than one status equality.

`SequenceAddress.loopIndex` defaults to zero and is forbidden on non-looping
sequences except as zero. It must be an exactly representable finite integer,
and local time must be finite and within `[0, duration]` for a finite sequence.
At a loop boundary `{ timePosition = duration, loopIndex = i }` deliberately
names the pre-loop side while `{ timePosition = 0, loopIndex = i + 1 }` names the
post-loop side. Any unwrapped calculation that loses finite/exact loop identity
fails explicitly rather than aliasing two cycles. `PlaybackPosition` exposes
local and unwrapped coordinates together so looped rebuilds, diagnostics, and
callers never have to guess which cycle a modulo-local value names.

`Params`, payloads, and errors should move from `any` to `unknown` at public
boundaries. Callback implementations narrow their own domain data. String
unions and authored string-keyed maps are cast at their use boundary rather
than widened or routed through `any`.

The public `Runtime` is deliberately nongeneric. Its private collections do not
store generic `PlaybackImpl<StepT, PhaseT, DirectionT>` values. The generic
factory constructs each typed implementation, then registers that same object
through a narrow nongeneric `PlaybackOwned` method view: `_terminate`,
`_reconcileClockChange`, `_runContinuous`, and `_dispose`. `PlaybackImpl` also
satisfies `PlaybackContextPort`, so `Context` borrows the Playback directly.
There is no per-playback owned table, context forwarding table, clock/phase
port, or Runtime link. Runtime never reads a Playback's sequence, step, phase,
direction token, or callbacks and never casts an erased value back to a generic
type.

For the same reason, Runtime, ClockState, and PhaseGroup are method-bearing
metatable owners, not closure packs or `{ [any]: ... }` maps. Runtime scans
small stable object arrays by `_sameClock(candidate: unknown)` and
`_samePhase(candidate: unknown)`. A ClockState is created from the exact typed
clock and owns the sole changed subscription for that clock state. A PhaseGroup
is created lazily only when the first updating Playback joins an exact
clock/phase pair, and owns that pair's sole continuous subscription. These
provider callbacks retain their ClockState or PhaseGroup object, never the
first Playback as a representative. Playback-owned methods perform typed
deadline scheduling. This is the concrete existential erasure boundary. The
strict mixed-generic fixture proves there is no broad `any` in Runtime,
ClockState, PhaseGroup, or ownership types.

### M1 structural ownership and allocation map

| Lifetime | Owner and allocation | Release condition |
| --- | --- | --- |
| Runtime | One method-bearing Runtime object; Playbacks store a narrowed borrow of this same object | `Runtime:destroy()` |
| Playback | One Playback object plus its semantic state records and one Context borrowing the Playback directly; **zero adapter/forwarding closures** | terminal detach and private disposal |
| Exact borrowed clock in one Runtime | One ClockState object and one provider changed callback | last Playback on that clock detaches |
| Active exact clock/phase pair | One lazily created PhaseGroup object and one provider phase callback | last updating Playback leaves; event-only Playback creates no group |
| Scheduled reached task | One provider callback capturing the task identity required to reject stale delivery | task cancel, replacement, or delivery |
| Observer registration / queued authored mutation | One semantic callback or release closure where caller identity or authored work must be retained | observer release, dispatch, or terminal clear |

Before structural normalization, each Playback constructor allocated about 31
adapter closures: 17 context, 4 owned, 3 clock, 2 phase, and 5 Runtime-link
forwarders. After normalization it allocates none. The remaining callbacks are
provider- or authored-work allocations with real identity/lifetime semantics,
not interface forwarding. Existing fake-clock tests prove zero phase bindings
for event-only Playback, one changed binding per exact clock, and one phase
binding per active exact clock/phase group.

`playbackSpeed` must be finite and may be positive, zero, or negative. Zero
keeps status `playing` and update-group membership while producing zero
sequence delta and no reached task. Pause is different: it removes deadline
and update work until resume.

`isAlive()` is true exactly for `idle`, `playing`, and `paused`. Logical
termination commits a terminal status and immutable completion, makes
`isAlive()` false, and fires `Ended` synchronously even when cleanup retention
continues privately. There is no public `stopping`, `disposing`, `Disposed`,
`onDisposed`, or `isDisposed` surface in v1. Disposal is ownership machinery,
not a second semantic sequence event.

During post-completion retention:

- status remains `completed` and late `onEnded` runs immediately;
- a late `onEnded` callback receives the stored Completion synchronously once
  and gets an idempotent no-op Release; other late observer registrations are
  inert and never reopen dispatch;
- `stop`, `cancel`, `pause`, `resume`, `play`, speed changes, seeks, steps, and
  signals are no-ops (boolean operations return `false` where applicable);
- `destroy()` or `Runtime:destroy()` cancels the real-time timer and flushes
  cleanup, but completion remains `completed`;
- `ctx:addCleanup` joins the retained active cleanup generation if disposal has
  not started, and runs immediately under protection if that generation has
  already been disposed;
- cleanup failure is warned and recorded only in private diagnostics. It never
  mutates, replaces, or re-emits the published completion.

Lifecycle methods have one terminal owner:

- `play()` transitions only `idle`; a second call is a no-op returning the same
  Playback. `pause()` acts only on `playing`, and `resume()` only on `paused`.
- `stop`, `cancel`, and `destroy` terminate any idle/playing/paused playback as
  `stopped`, `cancelled`, or `destroyed` respectively and publish Ended once.
  Terminalizing an idle playback invokes no authored lifecycle hook because
  `onPlay` and its cleanup generation never began.
- borrowed-clock destruction or Runtime destruction terminates a still-live
  playback as `destroyed` with the corresponding reason. Runtime destruction
  prevents later creation/play and never destroys the borrowed clock.
- after any terminal status, all lifecycle methods are no-ops except that
  Playback/Runtime destruction may flush still-retained private disposal.

### Sequence addressing and bidirectional callback contract

```luau
export type AddressPolicy = "cancel" | "skip" | "rebuild"
export type AddressCause = "initial" | "manualSeek" | "clockDiscontinuity"

export type ReverseEventAction<StepT = StepId> =
	((ctx: Context<StepT>) -> ()) | "ignore" | "cancel"
export type ReverseStepAction<StepT = StepId> =
	((ctx: Context<StepT>, payload: unknown?) -> ()) | "ignore" | "cancel"

export type Event<StepT = StepId> = {
	time: number,
	name: string?,
	step: StepT?,
	run: ((ctx: Context<StepT>) -> ())?,
	reverse: ReverseEventAction<StepT>?,
}

export type Step<StepT = StepId> = {
	time: number,
	run: ((ctx: Context<StepT>, payload: unknown?) -> ())?,
	reverse: ReverseStepAction<StepT>?,
	canEnter: ((ctx: Context<StepT>, payload: unknown?) -> (boolean, string?))?,
}

export type Steps<StepT = StepId> = { [StepT]: Step<StepT> }

export type StepChangeCause = "manual" | "event" | "rebuild"
export type StepChange<StepT = StepId> = {
	from: StepT?,
	to: StepT?,
	payload: unknown?,
	cause: StepChangeCause,
	direction: TraversalDirection?,
}

export type TransitionRule<StepT = StepId> = {
	from: StepT?,
	to: StepT?,
	after: number?,
	before: number?,
	canStep: ((
		ctx: Context<StepT>,
		from: StepT?,
		to: StepT?,
		payload: unknown?
	) -> (boolean, string?))?,
}

export type Update<StepT = StepId> = {
	name: string?,
	run: (ctx: Context<StepT>, dt: number, timePosition: number) -> (),
}

export type SignalHandler<StepT = StepId> =
	(ctx: Context<StepT>, payload: unknown?) -> ()

export type RebuildRequest = {
	from: PlaybackPosition,
	to: PlaybackPosition,
	cause: AddressCause,
	direction: AddressDirection,
}

export type RebuildState<StepT = StepId> = {
	step: StepT?,
}

export type Definition<StepT = StepId> = {
	duration: number?,
	cleanupDelay: number?,
	addressPolicy: AddressPolicy?,
	loop: boolean?,
	params: Params?,

	steps: Steps<StepT>?,
	transitions: { TransitionRule<StepT> }?,
	events: { Event<StepT> }?,
	updates: { Update<StepT> }?,
	signals: { [string]: SignalHandler<StepT> }?,

	onPlay: ((ctx: Context<StepT>) -> ())?,
	onStop: ((ctx: Context<StepT>, reason: string?) -> ())?,
	onCancel: ((ctx: Context<StepT>, reason: string?) -> ())?,
	onDestroy: ((ctx: Context<StepT>) -> ())?,
	onRebuild: ((
		ctx: Context<StepT>,
		request: RebuildRequest
	) -> RebuildState<StepT>)?,
	onLoop: ((ctx: Context<StepT>, change: LoopChange) -> ())?,
	onStep: ((ctx: Context<StepT>, change: StepChange<StepT>) -> ())?,
	onParamChanged: ((
		ctx: Context<StepT>,
		name: string,
		value: unknown,
		oldValue: unknown?
	) -> ())?,
}

export type Sequence<StepT = StepId> = {
	duration: number?,
	cleanupDelay: number,
	addressPolicy: AddressPolicy,
	loop: boolean,
	defaultParams: Params,
	steps: Steps<StepT>,
	transitions: { TransitionRule<StepT> },
	events: { Event<StepT> },
	updates: { Update<StepT> },
	signals: { [string]: SignalHandler<StepT> },
	definition: Definition<StepT>,
}

export type Builder<StepT = StepId> = {
	duration: (self: Builder<StepT>, seconds: number?) -> Builder<StepT>,
	cleanupDelay: (self: Builder<StepT>, seconds: number) -> Builder<StepT>,
	addressPolicy: (
		self: Builder<StepT>,
		policy: AddressPolicy
	) -> Builder<StepT>,
	loop: (self: Builder<StepT>, enabled: boolean?) -> Builder<StepT>,

	param: (self: Builder<StepT>, name: string, value: unknown) -> Builder<StepT>,
	params: (self: Builder<StepT>, params: Params) -> Builder<StepT>,
	step: (
		self: Builder<StepT>,
		stepId: StepT,
		definition: Step<StepT>
	) -> Builder<StepT>,
	transition: (
		self: Builder<StepT>,
		rule: TransitionRule<StepT>
	) -> Builder<StepT>,
	event: (self: Builder<StepT>, event: Event<StepT>) -> Builder<StepT>,
	update: (self: Builder<StepT>, update: Update<StepT>) -> Builder<StepT>,
	signal: (
		self: Builder<StepT>,
		name: string,
		handler: SignalHandler<StepT>
	) -> Builder<StepT>,
	hold: (
		self: Builder<StepT>,
		time: number,
		stepId: StepT,
		signalName: string
	) -> Builder<StepT>,

	onPlay: (
		self: Builder<StepT>,
		callback: (ctx: Context<StepT>) -> ()
	) -> Builder<StepT>,
	onStop: (
		self: Builder<StepT>,
		callback: (ctx: Context<StepT>, reason: string?) -> ()
	) -> Builder<StepT>,
	onCancel: (
		self: Builder<StepT>,
		callback: (ctx: Context<StepT>, reason: string?) -> ()
	) -> Builder<StepT>,
	onDestroy: (
		self: Builder<StepT>,
		callback: (ctx: Context<StepT>) -> ()
	) -> Builder<StepT>,
	onRebuild: (
		self: Builder<StepT>,
		callback: (
			ctx: Context<StepT>,
			request: RebuildRequest
		) -> RebuildState<StepT>
	) -> Builder<StepT>,
	onLoop: (
		self: Builder<StepT>,
		callback: (ctx: Context<StepT>, change: LoopChange) -> ()
	) -> Builder<StepT>,
	onStep: (
		self: Builder<StepT>,
		callback: (ctx: Context<StepT>, change: StepChange<StepT>) -> ()
	) -> Builder<StepT>,
	onParamChanged: (
		self: Builder<StepT>,
		callback: (
			ctx: Context<StepT>,
			name: string,
			value: unknown,
			oldValue: unknown?
		) -> ()
	) -> Builder<StepT>,

	build: (self: Builder<StepT>) -> Definition<StepT>,
	compile: (self: Builder<StepT>) -> Sequence<StepT>,
}
```

`seekMode`, `SeekMode`, `SeekRequest`, builder `seekMode`, `onSeek`, and the
redundant pre-play `onCreate` hook are removed. `onPlay` is the single authored
start hook. Builder replacements are `addressPolicy(policy)` and
`onRebuild(callback)`. To avoid adding more optional positional arguments,
`Builder:step(stepId, definition)`, `Builder:event(definition)`, and
`Builder:update(definition)` accept the canonical records above. The duplicate
`eventOnly` alias is removed; an event with `step = nil` is already event-only.
The distinct `hold` helper remains and authors its pause callback with explicit
reverse `"ignore"`. All builder lifecycle callbacks use `Context<StepT>` and
`unknown` payloads, and loop/step observers receive change records rather than
an ambiguous count or positional argument pack.

The compiled `Sequence` exposes normalized values but not private sorted
indexes, boundary cursors, event identities, or occurrence history. Compilation
freezes or privately copies every authored record so caller mutation cannot
change a live playback contract.

Address policy semantics:

| Policy | Initial address | Manual seek | Reported clock discontinuity |
| --- | --- | --- | --- |
| `cancel` (default) | Establishes the requested cursor without historical callbacks. | Returns `false`; position and cursor do not change. | Cancels with reason `clockDiscontinuity`; no crossed callbacks run. |
| `skip` | Establishes the requested cursor and treats prior state as externally established. | Reanchors at the target and updates cursor/loop index without crossed callbacks. | Derives the sequence target from the delivered clock delta, then applies the same no-replay rule. |
| `rebuild` | Flushes the current cleanup generation, creates a new generation, calls `onRebuild`, and replays the target loop forward from local zero through target. | Performs the same generation reset and target-loop replay. | Derives the signed sequence target first, then performs the same rebuild. |

`rebuild` requires `onRebuild` at compile time. The callback must synchronously
reset non-resource sequence state after Pulse has disposed the previous
generation and return the logical baseline step for the target loop. Pulse
validates and installs that step without forward gates or step `run`, emits one
`StepChange { cause = "rebuild", direction = nil }` when it changes, then
replays only the target loop and emits no historical loop callbacks. This makes
cross-loop step baselines authored rather than guessed from modulo-local time.
The request exposes local, loop-index, and unwrapped coordinates for both ends.

The omitted initial `position` is a cold start at loop zero/local zero, before
zero-time work; playing forward runs zero-time work and playing backward
outward completes without fabricating an undo. An explicit nonzero `cancel` or
`skip` address places the cursor after all equal-time occurrences at that
address but records no timed-step history. A step-less event can still use its
authored reverse action from externally established state; a timed-step event
at that exact boundary fails with `missingReverseHistory` before user code
unless the address was established by `rebuild`. A rebuilt address ends after
its canonical forward replay and has complete timed-step entries through the
target. This boundary provenance is internal and is not another public seek
flag.

`ctx:addCleanup` is cleanup-generation scoped. Every initial/rebuilt address
has one generation. Before rebuild, Pulse detaches and flushes the old
generation LIFO, creates the new generation, and only then calls `onRebuild` and
replay callbacks; their new cleanups cannot accumulate with or later target
already-reset resources. Cleanup added while its generation is flushing runs
immediately. A rebuild cleanup failure fails the still-live playback. A
post-completion cleanup failure only warns because completion is already
immutable and published.

Cleanup registration is deliberately not occurrence history. Reverse traversal
does not pop or invoke cleanups registered by the corresponding forward event.
The authored reverse callback must undo any occurrence-specific side effect and
may locate that state through playback parameters, captured authored state, or a
host-injected presentation context. Pulse adds no occurrence-resource owner in
v1; rebuild and terminal disposal remain the only automatic cleanup boundaries.

Forward callbacks and reverse callbacks are separate contracts:

- An event's `run` executes only on forward crossing. On backward crossing,
  its `reverse` callback executes; `"ignore"` crosses without undo and
  `"cancel"` stops before any part of that occurrence is undone with reason
  `reverseEventUnavailable`. When `run` exists, omitted event reverse action
  means `"cancel"`; when `run` is absent, it means `"ignore"` because there is
  no event side effect beyond an optional recorded step transition.
- A step with a forward `run` uses the same reverse-action rules. When forward
  `run` is absent, omitted reverse action means `"ignore"` because only Pulse's
  recorded step value needs restoration. Pulse preflights both event and step
  reverse availability before starting either callback, so a missing action
  cannot leave a half-undone occurrence.
- Damage, one-shot audio, and particle emission must choose deliberately:
  authored undo where possible, explicit `"ignore"` when the irreversible
  effect should remain, or default/explicit `"cancel"` when reverse traversal
  would be invalid. Pulse never invokes `run` while moving backward.

Every timed-step event occurrence has a journal entry keyed by compiled event
identity plus signed loop index, not just by modulo-local time. Forward order is
locked as transition gates -> set target step -> target step `run` -> `onStep`
with `{ cause = "event", direction = "forward" }` -> event `run`. A rejected
step gate records `blocked`, consumes that forward crossing, and invokes neither
the step nor event callback. A successful occurrence records `applied` plus the
exact `{ from, to, payload }` transition data. Reversing a `blocked` occurrence
deletes that record without callbacks, allowing a later forward recross to
reevaluate gates.

Backward crossing of a timed-step event requires that journal entry. Missing
history after a non-replayed initial address or `skip` cancels before user code
with `missingReverseHistory`; callers that need reversible step state at an
arbitrary address must use `rebuild`. A step-less event needs no dynamic step
history and follows its authored reverse action directly. For an `applied`
timed-step entry, inverse order is event `reverse` -> target step `reverse` ->
restore recorded `from` -> `onStep` with `{ cause = "event", direction =
"backward" }`. Reverse traversal never reruns `canEnter`, transition `canStep`,
or forward step/event callbacks. It first requires the current step to equal
recorded `to`; divergence cancels before undo with `stepHistoryDiverged`. A
successful undo deletes the entry, so the next forward recross applies the
occurrence afresh. Rebuild clears the journal and reconstructs it through
canonical forward replay. Manual `step()` continues to use normal gates and
emits `cause = "manual"` with no traversal direction.

One event occurrence is a reconciliation transaction. Nonterminal lifecycle,
speed, direction, or address mutations requested by its user callbacks are
validated and queued, then applied in call order after that occurrence reaches
its forward or reverse commit point; getters inside the callback still observe
the pre-mutation address. Stop, cancel, destroy, clock destruction, and callback
failure remain immediate terminal interrupts and no later user callback in the
occurrence runs. This prevents a sign flip inside `event.reverse` from invoking
the same undo twice or abandoning the associated step half-restored. Nested
signals are queued behind the current callback dispatch, and observer lists are
always snapshot-dispatched.

The timed-step journal is retained for the playback lifetime so an unbounded
loop can be walked backward exactly. That is correctness-first and can grow
with every crossed timed-step occurrence; safe prefix compaction is deferred
and must never replace history with an implicit rebuild.

## Clock-group and scheduling model

### Group identity

Runtime keeps a strong collection of clock records only while at least one
playback uses that clock and selects them by exact identity. Each clock record
keeps phase groups selected by the exact supplied phase value. VoxelMMO
composition should supply canonical Tempo phase tokens
(`clock.phases.preRender`, for example) so a string and token for the same Tempo
phase do not accidentally form two Pulse groups.

Sharing is proposed within one explicit Pulse Runtime. Different Runtime
objects are independent ownership domains and may bind independently even when
given the same clock and phase. A module-global weak registry is rejected by
default because it creates hidden cross-owner lifecycle and teardown coupling.

### Deadline selection

Every playing playback derives **expected** clock direction from signed
`clock:read().rate`, then derives expected sequence direction by multiplying
that sign by the sign of `playbackSpeed`. This expectation selects the reached
token and next checkpoint; a zero factor selects neither. During execution,
**observed** clock direction comes from the reached callback or the sign of the
sampled clock-position delta, and observed sequence direction comes from the
resulting signed sequence delta. Actual movement is authoritative. Expected
clock direction, observed clock direction, and resulting sequence direction are
stored as distinct concepts rather than one ambiguous direction flag.

In forward sequence traversal, the next checkpoint is the least unwrapped
coordinate after the cursor; in backward traversal it is the greatest
coordinate before the cursor. Candidates are:

1. next event occurrence in the selected sequence direction;
2. next loop boundary in that direction for a looping sequence;
3. `duration` while moving forward or zero while moving backward for a finite
   non-looping sequence.

For nonzero speed the sequence checkpoint is converted to a clock coordinate
through the inverse anchor and submitted with
`clock:bindToReached(clockCheckpoint, clockDirectionToken, callback, phase)`.
If the existing reached record has the same clock direction, Pulse normally
reuses it with `rescheduleAt`, including from inside its callback. If clock
direction changes, Pulse cancels the record and binds a new one because Tempo
rescheduling changes position/phase but not the record's reached direction.

No checkpoint means no scheduled task. An eventless, update-free, unbounded
sequence is inert but remains alive until signaled or stopped. Compilation must
reject looped sequences without a finite positive duration.

At dispatch, Pulse never trusts the scheduled coordinate or expected direction
as current truth. It verifies playback generation, task identity, status, live
clock, and the reached callback's actual clock direction; reads the clock
again; derives signed sequence traversal; drains all crossed work; and only
then chooses the next checkpoint. This covers sign changes and clock changes
immediately before execution.

Tempo reached callbacks for a clock/phase run before that clock/phase's
continuous callbacks. Therefore a playback with both events and updates sees
crossed events first and one update at the same sampled position afterward.

### Continuous execution

A compiled sequence has continuous work when its update array is nonempty.
The playback joins its phase group's updating set only while `playing`.

- First updating member: call `clock:bindPhase(explicitPhase, groupCallback)`.
- Additional updating members: add to the group's stable collection; do not
  bind again.
- Pause or any terminal transition: remove the member.
- Last updating member removed: call the idempotent release immediately.

The group callback snapshots members so callbacks may add, remove, pause,
cancel, destroy, or create playbacks safely. For each still-current member it
derives position from the callback's `now` and the playback anchor, drains any
due cursor work not already drained by the scheduled callback, then invokes
updates once. Update `dt` is the change in sequence position since that
playback's prior continuous sample and is signed: positive forward, negative
backward, zero while local speed or clock rate is zero. It is not raw frame
delta and is not multiplied by the clock rate again.

The basic one-step hit case therefore costs sequence construction plus one
reached record (or synchronous time-zero execution), with no phase callback.
A trail sequence with updates receives phase callbacks only while playing;
pause, completion, cancellation, failure, and teardown remove it immediately.

### Clock changes

One change subscription per clock record fans changes out to a snapshot of its
live playbacks.

- `clock:isDestroyed()` ends every affected playback with reason
  `clockDestroyed`, cancels any remaining task ids, releases phase groups, and
  drops the clock record.
- A continuous rate-magnitude change with the same sign preserves each anchor;
  the clock provider owns root-wake recalculation.
- A continuous clock-rate sign change first samples and reanchors the same
  sequence position, performs exact-boundary cursor reorientation if needed,
  cancels the old-direction reached record, and selects the checkpoint and
  reached token for the new clock/sequence directions.
- For `discontinuous == true`, a clock position is never mistaken for a
  sequence position. Pulse samples sequence position at the delivered previous
  clock position and derives the signed target as:

  ```text
  sequenceBefore = sequenceAtAnchor
                 + (previousClockPosition - clockAtAnchor) * playbackSpeed
  targetSequence = sequenceBefore
                 + (currentClockPosition - previousClockPosition) * playbackSpeed
  ```

  It converts that unwrapped target to a `PlaybackPosition`, applies the
  sequence's `AddressPolicy`, reanchors at `currentClockPosition`, and then
  reschedules or terminates.
- A change callback and a due callback can race in one synchronous phase
  stack. Playback generation and task-id checks make stale callbacks no-ops;
  the central reconcile loop is non-recursive and applies queued nonterminal
  callback mutations after the current occurrence commit point.
- A continuous change delivered inside authored, lifecycle, update, signal, or
  observer dispatch captures its validated clock sample in notification order
  and enters the mutation queue at that callback's commit point. The central
  loop catches up to that sample under the prior mapping before applying a sign
  transition; the notification stack never writes the cursor or anchors
  recursively. Terminal changes and terminal playback mutations remain
  immediate interrupts.

## Playback anchor and rescheduling rules

The playback stores an unwrapped sequence anchor:

```text
sequenceNow = sequenceAtAnchor
            + (clockNow - clockAtAnchor) * playbackSpeed
```

The borrowed clock's effective rate is already represented by the change in
`clockNow`. It is never multiplied into the formula again.

For any nonzero signed `playbackSpeed`, a sequence checkpoint maps to:

```text
clockCheckpoint = clockAtAnchor
                + (sequenceCheckpoint - sequenceAtAnchor) / playbackSpeed
```

The mapping says where; signed clock rate says the expected clock crossing
direction; their product with signed local speed says resulting sequence
direction. Those are never collapsed into one ambiguous `direction` variable.

Rules by operation:

| Operation | Required ordering |
| --- | --- |
| Create | Validate and store only. No user callback, clock subscription, reached record, or phase binding runs before observers can subscribe. |
| Play | Read clock once; establish the initial address (including rebuild callbacks when selected); run the single authored `onPlay` hook; reconcile cold-start/equal-boundary/outward-terminal work; then schedule and/or join continuous execution. Observer subscriptions already exist because create was inert. |
| Same-sign clock-rate magnitude change | Keep anchor unchanged because the clock reports equal before/after position; let the provider retime its wake. |
| Clock-rate sign change | Sample/reanchor the same sequence position, reorient exact-boundary cursor state, cancel the old direction record, and choose a new reached direction/checkpoint. |
| Local speed change, including sign | Sample through the old signed speed; set both anchors to sampled positions; store finite new speed; reorient exact-boundary cursor state when sign changes; reschedule without treating the change as a seek. |
| Set speed to zero | Reanchor, cancel the reached record, retain `playing`, and keep updates active with zero sequence delta. |
| Restore nonzero speed | Read current clock, reanchor the frozen sequence position to it, choose direction, and schedule; zero-speed clock time is not caught up. |
| Pause | Sample under the current anchor, store that sequence position, cancel the deadline, leave the updating group, set `paused`. |
| Resume | Read then-current clock, anchor the stored position to it, set `playing`, reconcile due-at-current work once, schedule, and join updates if needed. |
| Manual seek | Validate finite target and authored policy; reanchor at one clock read; apply skip/rebuild semantics; reschedule. |
| Reported discontinuity | Derive signed sequence target from sequence-before plus delivered clock delta times local speed; apply AddressPolicy; anchor target to current clock position; never use a clock position directly as sequence position. |
| Callback mutation | Validate and queue nonterminal lifecycle/speed/address changes until the current event occurrence commits, then increment the mutation generation and apply them in call order. Terminal requests and callback failures interrupt immediately. Reconciliation never continues from stale cursor assumptions. |

The implementation stores unwrapped sequence position for scheduling and loop
catch-up. `getPosition()` exposes it with the local coordinate and signed loop
index. Loop indices increase forward and decrease backward until the explicit
numeric-precision guard, which fails rather than aliasing occurrences.

At an exact loop boundary the same unwrapped coordinate has two local
representations. Before the loop notification it is `{ loopIndex = i,
timePosition = duration }`; after the notification it is `{ loopIndex = i + 1,
timePosition = 0 }`. `getPosition()` returns the representation selected by the
committed boundary side, and both satisfy `unwrappedTimePosition = loopIndex *
duration + timePosition`. The backward transition uses the inverse pair.

Natural progression drains crossed checkpoints in traversal order. Forward
equal-time callbacks retain authoring order; backward equal-time callbacks use
reverse authoring order so undo is the deterministic inverse.

Loop boundary ordering is frozen:

- forward from loop `i` to `i + 1`: forward events at duration of `i` in
  authoring order, `LoopChange { i, i + 1, "forward" }`, then forward events at
  zero of `i + 1` in authoring order;
- backward from loop `i` to `i - 1`: reverse events at zero of `i` in reverse
  authoring order, `LoopChange { i, i - 1, "backward" }`, then reverse events
  at duration of `i - 1` in reverse authoring order.

For each `LoopChange`, the authored `Definition.onLoop` callback runs before the
snapshot-dispatched `Playback:onLooped` observers, and both receive the same
record. Cursor stage is committed around each duration event, loop notification,
and zero event, so a callback pause or direction change resumes from the exact
next inverse/forward stage rather than replaying the whole boundary.

Every checkpoint cursor records boundary side, not only numeric time. A
nonzero direction flip exactly on an event/loop boundary transfers that side
once and runs the corresponding forward or reverse boundary actions
synchronously before scheduling away. This is required because current Tempo
correctly does not invent a reached crossing when a binding is registered at
equality. Repeating the same direction is a no-op; alternating direction at
the boundary alternates apply/undo exactly once. A zero-speed change never
transfers boundary side.

For a finite non-loop, natural forward completion occurs at duration after
duration events; natural backward completion occurs at zero after reverse zero
events. Starting or resuming exactly at duration while already directed
outward-forward, or at zero while directed outward-backward, completes
immediately without fabricating a new boundary crossing. Starting at either
terminal with zero effective sequence direction remains playing until direction
becomes inward or outward; becoming outward completes immediately.

The M1 implementation uses a finite limit of **4,096 committed event
occurrences or loop boundaries per top-level reconcile**. Attempting the 4,097th
unit fails the playback deterministically with `catchUpLimitExceeded`; no event
or boundary is folded or silently discarded. On the 2026-08-15 Lune 0.8.9 M1
benchmark, the actual borrowed-clock reconciliation path processed 512, 1,024,
2,048, and 4,096 authored occurrences with five-run medians of approximately
0.84 ms, 1.71 ms, 3.91 ms, and 10.09 ms respectively. The 4,096 sample ranged
from 8.15 ms to 11.62 ms (about 406,000 occurrences/second at the median). The
limit keeps a pathological synchronous catch-up near the measured 10 ms range
on the profiling host while remaining far above normal authored bursts. Tests
lock success at 4,095 and 4,096 and explicit failure at 4,097. Cooperative
continuation remains deferred.

Finite clock, anchor, speed, and checkpoint inputs can still overflow floating
point arithmetic. A non-finite forward anchor derivation, inverse checkpoint
mapping, or continuous sequence delta fails the playback with the stable
internal reason `numericOverflow`; the arithmetic failure never escapes a
reached or phase callback.

## Addressing, seek, and replay semantics

The following cases are intentionally distinct:

| Case | Classification | Event behavior |
| --- | --- | --- |
| Late phase evaluation / frame hitch with no clock change | Normal continuous progression | Catch up every crossed event and loop boundary, subject only to explicit failure limit. |
| Same-sign continuous rate change | Normal continuous progression | Position remains continuous; provider retimes the reached work. |
| Clock-rate or playback-speed sign change | Direction reorientation | Position remains continuous; reanchor, reconcile exact-boundary side, and bind the checkpoint in the new direction. |
| Pause/resume | Lifecycle reanchor | No catch-up for paused clock time. |
| Local speed magnitude change | Local continuity reanchor | No callback fires solely because magnitude changed. |
| Manual forward/backward seek | Authored AddressPolicy | Cancel, skip, or rebuild at the requested sequence address. It is never continuous reverse traversal. |
| Tempo `ClockChange.discontinuous == true` | Authored AddressPolicy | Derive sequence target from the delivered clock delta and signed speed, then cancel, skip, or rebuild. |
| Unreported raw time-source jump | Indistinguishable from elapsed timeline | Treated as normal catch-up unless the clock provider strengthens its notification contract. |

Rebuild callback order is locked as:

1. mark reconciliation in progress and cancel stale reached work;
2. detach and flush the old cleanup generation LIFO;
3. if still alive, create the new cleanup generation and clear Pulse
   step/cursor/timed-step-journal state for the target loop;
4. call `onRebuild(ctx, request)` protectively and validate its returned
   target-loop baseline step;
5. if `onRebuild` requested a nonterminal mutation, apply it on callback return
   and abandon the superseded replay; otherwise install/notify the returned
   baseline step without gates or step `run`;
6. if still current, replay forward from target-loop local zero through target,
   including stable equal-time order, normal transition gates, and one atomic
   transaction per occurrence;
7. after each occurrence commit, apply queued mutations and abandon replay if
   lifecycle or addressing changed;
8. converge through the central reconcile loop;
9. select direction, schedule the next reached checkpoint, and rejoin
   continuous execution as needed.

Forward rebuild is canonical state construction even when the playback will
continue backward afterward. It is not a substitute for continuous reverse:
once rebuilt, backward crossings use reverse callbacks and the timed-step
journal normally.

## Real-time versus timeline-time contract

| Work | Clock domain | Rationale |
| --- | --- | --- |
| Forward/reverse events and timed steps | Borrowed-clock timeline after signed local speed mapping | Authored apply/undo follows effective sequence direction. |
| Loop boundaries and zero/duration completion | Borrowed-clock timeline after signed local speed mapping | They are directional sequence checkpoints. |
| Update callback `timePosition` | Sequence timeline | It addresses the compiled sequence. |
| Update callback `dt` | Signed difference between consecutive sequence positions | It already includes clock motion and local playback speed; never multiply by clock rate. |
| Event-miss catch-up | Sequence timeline in the observed direction | It drains continuous elapsed sequence time forward or backward. |
| Pause duration | No progression | Resume reanchors and intentionally ignores elapsed clock time. |
| `cleanupDelay` linger | Real time through `RealTimeScheduler` | Cleanup safety must finish even when the borrowed clock is frozen, reversed, destroyed, or discontinuously readdressed. |
| Callback-failure cleanup | Immediate | Failure must not remain clock-dependent. |
| Stop/cancel/destroy cleanup | Immediate | Owner teardown must be deterministic. |
| Future watchdog, timeout, retry, or cooperative-catch-up yield | Real time unless its API explicitly says timeline | Safety/failure policy must not stall behind gameplay dilation. |
| `Ended` observer callbacks | Synchronous at logical termination | Cleanup retention does not extend the sequence timeline. |
| Post-completion cleanup | Real time | It is private disposal; errors warn and cannot rewrite completion. |

Every terminal transition first marks a terminalization generation and leaves
timeline/clock groups. Stop/cancel/destroy invokes only its matching authored
lifecycle hook under protection; the first terminal request wins, and a hook
failure changes the not-yet-published result to `failed`. Pulse then commits one
Completion, makes `isAlive()` false, and fires `onEnded`; observer failures only
warn. Disposal is subsequent ownership work. Natural `completed` with positive
cleanup delay retains the terminal Playback privately and disposes its active generation later
in real time. Zero delay and stop/cancel/failure/pre-completion destruction
dispose after their terminal notification in the same stack. Runtime/host
destruction flushes retained generations early without changing completion.
Every cleanup error warns and remains private; no cleanup result can mutate or
replace the Completion after it has been published.

## Migration and deletion order

This is a breaking package migration; do not maintain a dual old/new runtime.

1. **Preflight and evidence**
   - record Pulse branch/commit and all three repository statuses;
   - save the exact diff of dirty `dev/client/init.client.luau`;
   - inventory all old names with `git grep`;
   - establish test/tool versions without modifying VMMO or Tempo.
2. **Tool and test foundation**
   - replace Aftman with `rokit.toml` rather than adding a second manager;
   - add guarded verification scripts and a root `tests/lune/` harness;
   - add a deterministic fake scheduling clock and fake real-time scheduler;
   - add focused characterization coverage useful to the replacement; do not
     preserve obsolete behavior merely to keep an intermediate commit green.
3. **Canonical Pulse types**
   - add the structural clock, runtime, completion, address, and timer types in
     `types/`;
   - update builder/sequence/playback/context/runtime contracts;
   - remove old seek contracts and Tempo forwarding in the same checkpoint;
   - keep module return types local and constructor-only.
4. **Sequence compilation**
   - validate finite/non-negative authored times, loop duration, update/event
     arrays, reverse actions, rebuild callback requirement, and stable ordering;
   - produce immutable compiled tables or narrow read-only exposure;
   - assign stable event identities and remove `seekMode` normalization.
5. **Clock-backed runtime and playback**
   - replace `_update(dt)` advancement with anchors and central reconciliation;
   - implement clock records, phase groups, lazy binding, one next task,
     rescheduling, pause/resume, signed speed, bidirectional loops, occurrence
     history, catch-up, and address policy;
   - make callback collections snapshot-safe and use typed implementation
     views rather than `any` parent links.
6. **Lifecycle and real-time cleanup**
   - add real-time scheduler ownership, immediate immutable logical completion,
     private post-completion retention, immediate failure/cancel/destroy cleanup,
     late `onEnded`, and runtime teardown races.
7. **Delete old integration**
   - delete `src/externalPackages/tempo.luau`;
   - remove Tempo from production dependencies, retain current Tempo only in
     the development/test conformance environment, and regenerate the lock;
   - delete stale old names and eager binding code;
   - refresh ignored generated state through tools only.
8. **Docs and development laboratory**
   - update README and add package-owned architecture/API/guides;
   - migrate the Studio harness without losing its unrelated dirty edit;
   - add event-only versus updating counters, clock rate/seek controls, and
     group-binding visibility.
9. **Consumer proof, without consumer mutation**
   - compile/type-check a fixture showing VMMO's TemporalClock and explicit
     phase satisfy Pulse's structural contract;
   - document the intended VMMO composition only;
   - do not edit VMMO, install VMMO dependencies, or run VMMO Pesde.
10. **Final stale search and verification**
    - search all authored package code/docs/dev/tests for old type names,
      TempoRuntime ownership, heartbeat fallback, `_update(dt)`, and duplicate
      seek methods;
    - run all package gates and the Studio matrix;
    - do not publish Pulse.

## Accelerated milestones and commit boundaries

### Preflight design checkpoint — approved contract

The approved design TODO was committed alone at `9b59352`; the unrelated
`dev/client/init.client.luau` whitespace remains outside every amendment commit.

Intermediate milestone commits are recovery points, not compatibility or
release gates. They may fail builds, analysis, or tests while old code is being
replaced. Do not build a parallel legacy/new surface merely to keep a midpoint
green. Run focused checks when they accelerate debugging, but the complete
verification matrix is mandatory only in M3. Use one implementation worker
across milestones when possible and pause only for a genuine contract blocker.

### M0 — Foundation, contract, and compiler

Combined former scope: CP-P0 + CP-P1.

- establish one tool manager, guarded verification scripts, a Lune harness,
  deterministic direction-aware fake clock, fake real-time scheduler, and a
  synchronous catch-up benchmark;
- replace the public type contract directly; do not create an unexported
  next-contract duplicate solely for migration compatibility;
- implement builder/compiler changes, stable event identities, signed address
  records, reverse actions, validation, and immutable/narrow compiled data;
- add strict type fixtures and focused compiler/fake-clock tests sufficient to
  support M1 debugging; the repository need not be globally green;
- **KEEP TEMPO** in production dependencies and preserve the current adapter/dev
  laboratory until M3.

**Recovery commit 1:** `refactor(sequence): establish temporal contract foundation`.

### M1 — Bidirectional borrowed-clock runtime

Combined former scope: CP-P2 + CP-P3.

- replace accumulated-frame advancement with the central signed reconciliation
  engine, boundary-side cursors, signed loop indices, event transactions,
  timed-step history, catch-up, and queued callback mutation;
- implement nongeneric Runtime ownership views, two-stage create/play,
  ClockState/PhaseGroup records, signed anchors, direction-aware reached
  scheduling, pause/resume/speed changes, and lazy shared continuous execution;
- delete superseded playback/manager paths as their replacements land instead
  of maintaining compatibility adapters;
- use focused bidirectional traversal and fake-clock tests while debugging, but
  do not spend time restoring unrelated intermediate package behavior;
- **KEEP TEMPO** through this milestone.

**Recovery commit 2:** `feat(runtime): add bidirectional borrowed-clock playback`.

### M1 structural normalization checkpoint — execution ownership

This behavior-preserving checkpoint lands after M1 and before any M2 addressing,
rebuild, cleanup-retention, or lifecycle semantics:

- make Playback itself satisfy `PlaybackOwned` and `PlaybackContextPort`, and
  make Runtime, ClockState, and PhaseGroup method-bearing owners;
- remove the approximately 31 per-playback adapter closures and create
  PhaseGroup only for active continuous updates;
- move implementation records and ownership capabilities into internal type
  leaves without expanding the root exports;
- split temporal execution into one-way stateless modules: timeline coordinate
  math; reconciliation/traversal; scheduling/anchors; and the Playback
  facade/lifecycle owner;
- preserve public contracts, boundary ordering, the 4,096 work limit,
  reconciliation results, and completion reasons;
- **KEEP TEMPO** `^0.2.0`, its lock entry, and the production adapter through
  M2; dependency removal remains M3-only.

**Structural checkpoint commit:**
`refactor(playback): separate temporal execution internals`.

### M2 — Addressing, rebuild, and lifecycle completion

Combined former scope: CP-P4 + CP-P5.

- implement `AddressPolicy`, loop-aware addresses/positions, manual seek,
  delivered-delta discontinuity mapping, canonical forward rebuild, cleanup
  generations, and timed-step history provenance;
- implement the real-time cleanup scheduler, immediate immutable logical
  completion, private post-completion retention, late observers, and every
  terminal/teardown path;
- finish removal of superseded runtime behavior, accepting a broken midpoint
  rather than adding aliases or temporary semantic shims;
- run focused address/lifecycle tests only as needed to debug M2;
- **KEEP TEMPO** through this milestone.

**Recovery commit 3:** `feat(playback): complete addressing and lifecycle semantics`.

### M3 — Dependency cutover, hardening, documentation, and final proof

Combined former scope: CP-P6 + CP-P7.

- confirm replacement source has no production Tempo import, then remove Tempo
  0.2 from production dependencies, delete the adapter, add current Tempo only
  to the supported development conformance environment, and regenerate Pulse's
  lock through Pesde;
- complete public exports, strict analyzer proof, current Tempo structural and
  runtime conformance, stale-name deletion, and the full reentrancy/race matrix;
- run every behavioral test in both directions where applicable, all package
  format/lint/analyze gates, documentation verification/build when supported,
  and the complete Studio operator matrix;
- update README/package docs and the Studio laboratory, including reached/group
  counts and current/peak timed-step history visibility;
- finish with one green, reusable standalone Pulse package. Do not publish and
  do not perform VMMO Pesde operations or edit Tempo/VMMO source.

**Final commit 4:** `feat(pulse): complete temporal scheduling amendment`.

Issue one bounded worker prompt per accelerated milestone. Prefer the same
worker for M1 through M3 to retain implementation context. Do not pause between
milestones for ordinary review; pause only for a genuine contract blocker,
unrecoverable tool failure, unexpected user-owned overlap, or required external
Pesde action. The unrelated dev-client whitespace must remain preserved and
separately visible throughout.

## Behavioral and race-condition test matrix

All tests use a deterministic fake clock with explicit phase evaluation plus a
fake real-time scheduler. A small integration/type fixture uses the current
Tempo contract; Pulse does not vendor or wrap it.

### Construction and cheap paths

- zero-time one-step hit runs once and creates no continuous binding;
- future one-step hit owns one reached id and no continuous binding;
- event-only finite sequence reschedules one reached id through all events and
  completion;
- updates-only sequence owns one group binding and a duration deadline;
- unbounded eventless/update-free sequence owns neither task nor binding;
- empty runtime owns no clock subscription or phase binding;
- `createPlayback` is inert: observers bound before `play()` see synchronous
  rebuild, `onPlay`, time-zero work, and outward-start completion;
- `play()` is one-shot; repeat play, resume-idle, and use after Runtime destroy
  fail/no-op according to the public method contract without duplicate work;
- missing/destroyed clock, missing direction token, non-finite values, invalid
  duration/event time/cleanup delay, and non-finite speed fail deterministically;
- positive, zero, and negative finite speed all validate;
- equal-time forward events retain authoring order and reverse events use the
  exact inverse order;
- event at duration runs before forward non-loop completion; reverse event at
  zero runs before backward completion when application history exists;
- loop duration must be finite and positive.

### Group sharing and lifecycle

- two updating playbacks on same clock and exact phase share one binding;
- same clock on two distinct phases owns one binding per phase;
- distinct clocks on same phase do not share clock state;
- event-only and updating playback on same group use one binding total;
- pausing one of two updaters retains binding; pausing the last releases it;
- resume reacquires exactly once;
- completion, stop, cancel, failure, destroy, and runtime destroy remove group
  membership exactly once;
- final playback leaving a clock releases one change subscription;
- callback-created playback is not skipped or stepped twice in the creating
  phase;
- callback-destroyed sibling is not called from a stale group snapshot;
- idle create owns no subscription; first play acquires it exactly once;
- speed zero remains in the updating set but owns no reached id;
- two explicit Runtime owners are characterized as independent.

### Anchors, rate, speed, and pause

- sequence position equals the anchor formula for positive, zero, and negative
  local speed under positive, zero, and negative clock movement;
- all four nonzero clock-direction/local-speed-sign products select the expected
  resulting sequence direction;
- continuous clock-rate magnitude and sign changes do not snap;
- no code multiplies effective clock rate into derived timeline delta twice;
- speed magnitude/sign change at event and loop boundaries preserves exact
  position, transfers boundary side once when required, and reschedules;
- speed zero freezes deadline progression without snapping;
- restoring speed reanchors and does not catch up the zero-speed interval;
- pause immediately before a due phase cancels work;
- resume after a large clock advance does not catch up paused time;
- repeated pause/resume/speed calls are idempotent where applicable;
- update callback receives signed sequence delta and current local position;
- first update after play/resume has the documented delta rather than an
  inherited stale sample.

### Normal progression, looping, and catch-up

- one late evaluation catches all crossed non-loop events in traversal order in
  either direction;
- multiple missed loop cycles emit each event and loop boundary in increasing
  or decreasing signed loop-index order;
- forward duration event -> loop callback -> next-cycle zero event and exact
  inverse backward ordering are locked;
- loop-local public position and unwrapped internal scheduling agree;
- exact loop-boundary public representation follows committed boundary side;
- a hitch landing exactly on event, loop, and either completion boundary fires
  each crossing once;
- repeated direction pivots at exact event/loop boundaries alternate apply/undo
  once without equality-triggered scheduling spins;
- natural forward completes at duration, natural backward completes at zero,
  outward terminal starts complete immediately, and zero direction waits;
- reverse action callback, `ignore`, explicit `cancel`, omitted-event cancel,
  and omitted-no-run-step ignore are each covered;
- reverse preflight finds a missing event or step action before either undo runs;
- a rejected timed step gate records `blocked`; backward consumes it without an
  undo; a later forward recross reevaluates the gate;
- an applied timed step restores recorded `from` without rerunning gates and
  reports forward/backward `StepChange` records;
- missing timed-step history and current-step divergence cancel before user undo
  code, while step-less reverse needs no journal;
- timed-step history count grows on committed forward entries, falls when those
  entries are successfully reversed, and reports a monotonic peak for the
  development laboratory;
- catch-up at one below, exactly at, and one above the safety limit either
  succeeds or fails explicitly; no event is silently folded away;
- callback pause/speed/sign/seek during either traversal direction commits the
  current occurrence, applies queued mutation once, and abandons stale state;
- callback stop/cancel/destroy/failure during either traversal direction
  interrupts immediately and invokes no later authored callback;
- no zero-duration or same-deadline reschedule spin is possible.

### Seek, jumps, and rebuild

- default/cancel policy rejects manual forward and backward seek without
  mutation;
- cancel policy terminates on clock discontinuity without crossed events;
- skip forward jump consumes cursor/loop index without running crossed events;
- skip backward jump readdresses without treating the movement as continuous
  reverse or invoking undo;
- natural reverse crossing of a timed-step occurrence in non-replayed
  initial/skip history cancels with `missingReverseHistory` before user code;
- rebuild calls `onRebuild` once before replay, installs its validated
  target-loop baseline step, and replays only target-loop events through target
  while constructing complete timed-step history;
- rebuild flushes the old cleanup generation LIFO before reset and all replay
  cleanups belong only to the new generation;
- rebuilt reverse traversal uses authored undo and journal history, not another
  rebuild;
- rebuild event callback may pause, cancel, destroy, seek again, or fail;
- initial nonzero position follows each policy's documented initialization;
- stationary discontinuity/epoch change still invokes authored policy;
- delivered clock delta times signed local speed determines the sequence target
  and direction for all clock/local sign combinations;
- update callback never integrates a reported jump as delta.

### Deadline and clock-change races

- same-direction rate change immediately before a reached deadline preserves
  one execution;
- clock or local-speed sign change immediately before execution cancels the old
  reached direction and binds the correct new checkpoint;
- the reached callback's actual clock direction, not the expected rate sign,
  determines reconciliation;
- forward or backward discontinuity immediately before a deadline invalidates
  the stale id before dispatch and applies AddressPolicy once;
- clock change from another scheduled callback in the same phase is safe;
- clock change from an event, update, signal, step, rebuild, or lifecycle
  callback is safe;
- due callback samples current clock rather than trusting scheduled `runAt`;
- stale callback with old generation/task id is a no-op;
- reschedule failure falls back only when playback is still alive and owns no
  active id;
- same clock direction reuses a running reached record; direction change never
  attempts to mutate the record's immutable reached token;
- clock destruction before play, while scheduled, while updating, while
  paused, during callback, and during cleanup linger is deterministic;
- Tempo scheduler invalidation and Pulse change fan-out may run in either
  callback-map order without changing result.

### Callback and observer reentrancy

- every authored sequence callback family can throw and produces one failed
  completion before Ended; observer and cleanup callbacks follow their separate
  warning-only contracts;
- cleanup callback errors use the typed `pcall` failure-result workaround, warn,
  and never replace the already committed terminal Completion;
- observer error warns but does not fail playback;
- listener disconnect/add during dispatch affects only later dispatches;
- late `onEnded` receives stored completion exactly once;
- onEnded may destroy Runtime or another playback safely;
- signal handler may recursively signal, seek, pause, reverse, or terminate
  without recursive cursor corruption;
- an event or reverse callback may change speed sign, pause, seek, create a
  sibling, or terminate; the occurrence transaction and queued mutation order
  remain deterministic;
- callback mutation at zero/duration and loop boundaries cannot duplicate the
  boundary or leave a half-restored step;
- runtime destroy called from a playback callback snapshots ownership and
  destroys every playback exactly once.

### Real-time cleanup

- natural completion with zero delay commits/fires one `completed` Ended, then
  disposes immediately;
- positive delay commits/fires `completed` immediately, makes `isAlive()` false,
  owns no timeline task/binding, and disposes only when fake real time advances;
- frozen, negative, destroyed, or discontinuously moved borrowed clock cannot
  stall cleanup;
- stop/cancel/pause/resume/seek/speed/signal during completed retention are
  no-ops and do not replace completion;
- Playback destroy or Runtime destroy during retention cancels the real timer
  and flushes cleanup without changing `completed`;
- cleanup error before or after delayed disposal remains private and completion
  never mutates or re-emits;
- cleanup registered before disposal joins the active generation; registration
  after disposal starts runs immediately under protection and cannot leak;
- rebuild-generation and terminal-disposal races clean every registration once.

## Documentation, development UI, and verification plan

Pulse currently has no documentation build. This TODO is the first file under
`docs/`; for this review, verify Markdown structure and repository diff only
and report that no docs build is supported.

Implementation documentation should become package-owned:

- `docs/index.md` — package boundary and minimal borrowed-clock example;
- `docs/architecture.md` — Runtime/ClockState/PhaseGroup/Playback ownership;
- `docs/api/` — filesystem-aligned public clock, sequence, playback, builder,
  and runtime contracts;
- `docs/guides/` — Tempo/VMMO composition without importing game concepts into
  Pulse;
- `docs/todo/index.md` — mark this amendment proposed, then implemented when
  complete;
- README — concise install, example, lifecycle, and links.

If VitePress is added, use a package-local `package.json`/lock and include
authored public docs in the Pesde artifact while excluding `docs/todo/` by
enumerating include patterns. Do not point a VMMO docs build at installed Pulse
files.

The Studio laboratory should display:

- borrowed clock position/rate and sequence position/speed;
- active playback count, scheduled task count, updating-member count, and
  continuous binding count;
- current and peak timed-step reverse-history count per playback, with an
  obvious growing-loop scenario so accidental indefinite retention is visible;
- event-only hit, finite event chain, looping updater/trail, gated hold, and
  cleanup linger scenarios;
- controls for continuous rate change, reported forward/backward seek,
  signed playback speed, pause/resume, cancellation, and destruction;
- log entries that distinguish timeline event, update, rebuild, loop,
  logical completion, retained cleanup, and final private disposal.

Package verification target after tooling exists:

```powershell
.\scripts\verify\tests.ps1
.\scripts\verify\stylua.ps1
.\scripts\verify\selene.ps1
.\scripts\verify\analyze.ps1
npm run docs:build
```

Use guarded scripts, capture full analyzer output, and report failures
honestly. Stop a gate after three attempts fail to produce a usable answer.
Studio behavior remains an explicit operator gate. No package publish is part
of this amendment.

## Explicitly deferred optimizations

- Cooperative catch-up continuation across frames instead of explicit failure
  at the synchronous safety limit.
- Heap or sorted-set storage inside a Pulse phase group; start with stable
  arrays/sets because Tempo already owns deadline heaps.
- Weak/global clock-group sharing across independent Runtime owners.
- Dynamic update windows within one sequence; v1 binds while a sequence with
  update work is playing.
- Pooling Playback, listener, group, or cleanup records.
- Multi-event deadline batching beyond the natural same-dispatch catch-up.
- Specialized zero-allocation callback snapshots proven necessary by profile.
- A public scoped-cleanup API beyond the internal rebuild generations required
  for correctness.
- Safe prefix compaction/checkpointing of the reverse timed-step journal. V1
  retains exact transition history and accepts growth for unbounded
  bidirectional loops. General compaction requires either a bounded reverse
  horizon or an authored snapshot/checkpoint restore contract; neither is added
  implicitly in v1.
- Cooperative yielding of a partially reconciled occurrence transaction;
  v1 commits one occurrence synchronously before applying queued mutation.
- Serialization, asset compilation, VFX schemas, plugin authoring formats, and
  VoxelMMO facades.
- Clock creation/ownership inside Pulse.
- Network replication, prediction, receipts, reconciliation, or authoritative
  hit semantics.

None of these deferrals permit an event-only playback to regain a per-frame
callback or permit multiple updating playbacks in one runtime clock/phase group
to bind independently.

## Accepted decisions, formerly blocking, ordered by importance

1. **Reverse timed-step history and authored undo.** Accepted:
   correctness-first transition journal, default cancellation for missing
   reverse actions or timed-step history, gate-blocked no-op entries, and
   occurrence-atomic queued mutation. Step-less events need no history. This is
   the accepted material tradeoff: an unbounded bidirectional loop with timed
   steps can grow history without bound. Safe compaction is deferred because it
   cannot discard dynamic `from`/`to` step history. If that cost is rejected,
   the honest alternatives are to require bounded playback, add an authored
   snapshot/checkpoint restore contract, or reduce reverse scope; repeated
   implicit rebuild is not an acceptable substitute.
2. **Address policy.** Accepted: `cancel | skip | rebuild`, safe default `cancel`,
   required `onRebuild`, target-loop-only canonical replay, cleanup-generation
   reset, and missing-history cancellation after non-replayed addresses.
3. **Clock-provider discontinuity guarantee.** Frozen: Pulse trusts
   only `ClockChange.discontinuous`; unreported raw source movement is elapsed
   timeline and receives normal bidirectional catch-up. TemporalService's
   sampled source can resample without a mapping notification. If VMMO requires
   those corrections to be seeks, that is a separate Tempo/TemporalService
   amendment because Pulse cannot infer it reliably.
4. **Sharing scope.** Accepted: one continuous binding per exact clock/phase within
   one explicit Pulse Runtime, with no module-global registry. Composition owns
   the intended sharing domain.
5. **Disposal surface.** Accepted as private in v1: `Ended` and terminal
   status happen at logical termination; cleanup retention exposes no
   `Disposed`/`onDisposed` state. A future observable disposal need would be a
   distinct API, never an extension of `Ended`.
6. **Real-time scheduler injection.** Accepted: optional Runtime injection with a
   `task.delay`/`task.cancel` default so tests are deterministic and cleanup
   never depends on gameplay clocks.
7. **Phase identity.** Accepted: group by exact supplied value and require
   composition to pass canonical phase tokens. Pulse does not own a phase
   registry.
8. **Catch-up safety value.** Accepted: failure instead of silent loss. M0's
   provider-callback benchmark established the measurement harness; M1's actual
   reconciliation profile selected 4,096 committed occurrences or loop
   boundaries per reconcile, as documented above. The 4,097th unit fails with
   `catchUpLimitExceeded`.

The contract is technically implementable as written; no unresolved algorithmic
or approval blocker remains. After the accelerated design commit, work may begin
at M0 and continue through M3 without operator pauses unless a real contract
blocker appears. Tempo and VoxelMMO source remain unmodified unless a separate
request explicitly broadens scope.
