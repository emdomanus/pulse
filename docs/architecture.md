# Architecture

Pulse has three runtime roles and one authoring helper.

```text
SequenceDefinition<ContextT> -> Builder/compiler -> immutable Sequence<ContextT>
                                              |
ProviderClock -> TemporalAdapter ----------> Playback -> authored callbacks
```

## Ownership

| Role | Owns | Does not own |
| --- | --- | --- |
| `Sequence<ContextT>` | Validated immutable callbacks, update, loop, and discontinuity policy | Invocation context, clock state, or live playback lifecycle |
| `Playback` | Per-play context, anchors, traversal cursor, local speed, scheduling intent, cleanup generation, completion | Clock or phase binding lifetime outside its adapter attachment |
| `TemporalAdapter` | Borrowed-clock validation, attachments, one changed subscription, one lazy shared phase binding | The provider clock or authored side effects |
| Host | Provider clock, execution phase, direction tokens, domain context and side effects | Sequence traversal internals |

Destroying an adapter detaches and fails its active playbacks; it never destroys the borrowed clock.
Destroying a playback releases only that playback's task, adapter membership, observers, and cleanup.

## Scheduling model

An event-only playback asks the provider clock for its next reached boundary. After a boundary runs,
Pulse reschedules that task for the next authored boundary. No continuous phase callback is needed.

An update interval makes a playback a continuous member only while the current traversal direction
can intersect active update work. All updating playbacks on one adapter share its one `bindPhase`
subscription. The adapter releases that binding when its last updating playback leaves.

Use one adapter for playbacks that share an exact clock and execution phase. Use separate adapters
when either identity differs.

## Time and anchors

Playback position is derived from an anchor:

```text
sequence = anchorSequence + (clockNow - anchorClock) * playbackSpeed
```

The provider's resolved clock rate selects whether scheduled work is traversing forward, backward,
or dormant. The local playback speed multiplies clock displacement and may also reverse traversal.
Pause, resume, and speed changes re-anchor at the current sample so time cannot snap or catch up
through a paused interval.

Continuous clock mapping changes reconcile to the change boundary before re-anchoring. A
discontinuous change uses the sequence's
[`AddressPolicy`](./api/types/definitions.md#address-policy).

## Callback and cleanup ownership

Forward traversal calls `Event.run`; backward traversal calls `Event.reverse` when present. Pulse
reverses traversal and its own recorded cursor, not arbitrary authored side effects. The reverse
callback owns any domain-specific undo.

`Pulse.playback` receives one typed invocation context and retains it for that Playback. The same
value is passed to event, reverse, update, setup, and authored loop callbacks, allowing one compiled
Sequence to serve many characters or world invocations without capturing per-play closures. Pulse
releases the retained context after terminal cleanup and before publishing Completion.

`Playback:addCleanup` belongs to the current playback or rebuild generation. Cleanup executes in
reverse registration order on rebuild or terminal completion. It is not per-event rollback.

| Work | Time contract |
| --- | --- |
| Events, updates, loop crossings | Sequence timeline derived from the borrowed clock |
| Playback speed and pause/resume | Sequence-local anchor operations |
| Cleanup | Immediate lifecycle work; no delayed timer |
| Catch-up guard | Bounded operation count, not elapsed time |

## Reentrancy and failure

Clock notifications and nonterminal callback mutations are serialized through one playback
operation queue. A terminal request interrupts remaining equal-time work. Authored callback errors
become one immutable `Completion` with status `failed`; observer errors do not change playback
state. Numeric loss of ordered boundary identity fails deterministically instead of guessing.
