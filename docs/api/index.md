# API

Pulse exposes one package root. Require only that root; `src/init.luau` re-exports every public
value and type.

<div class="api-meta">
  <span class="api-badge api-badge--public">Public package</span>
  <span class="api-badge">Strict Luau</span>
  <span class="api-badge">Client + server</span>
</div>

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pulse = require(ReplicatedStorage.packages.pulse)
```

## Package exports

| Export | Signature | Canonical API |
| --- | --- | --- |
| `sequence` | `<C>(SequenceDefinition<C>) -> Sequence<C>` | [`Pulse.sequence`](./components/sequence.md#pulse-sequence) |
| `builder` | `<C>() -> Builder<C>` | [`Pulse.builder`](./components/builder.md#pulse-builder) |
| `playback` | `<C>(Sequence<C>, C, PlaybackOptions?) -> Playback` | [`Pulse.playback`](./components/playback.md#pulse-playback) |
| `clockDriver` | `<P, D>(ProviderClock<P, D>, P, DirectionTokens<D>) -> ClockDriver` | [`Pulse.clockDriver`](./managers/clockDriver.md#pulse-clock-driver) |

## Returned objects

| Object | Responsibility |
| --- | --- |
| [`Sequence<ContextT>`](./components/sequence.md#sequence) | Immutable reusable timeline tied to its callback context type |
| [`Builder<ContextT>`](./components/builder.md#builder) | Mutable fluent authoring helper |
| Raw [`Playback`](./components/playback.md#playback) | Externally sampled traversal and one lifecycle |
| [`ClockDriver`](./managers/clockDriver.md#clock-driver) | Optional borrowed-clock scheduling and fan-out |
| [`DrivenPlayback`](./managers/clockDriver.md#driven-playback) | Clock-driven facade for one attached raw Playback |

## Source-shaped reference

```text
api/
|-- components/
|   |-- builder
|   |-- playback
|   '-- sequence
|-- managers/
|   '-- clockDriver
'-- types/
    |-- definitions
    '-- type index
```

Every root-exported type appears in the [Type index](./types/index.md).
