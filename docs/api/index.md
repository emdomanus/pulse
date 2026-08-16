# API

Pulse exposes one package root. Require only that root; every public value and type is re-exported
by `src/init.luau`.

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
| `sequence` | `(SequenceDefinition) -> Sequence` | [`Pulse.sequence`](./components/sequence.md#pulse-sequence) |
| `builder` | `() -> Builder` | [`Pulse.builder`](./components/builder.md#pulse-builder) |
| `temporalAdapter` | `<P, D>(ProviderClock<P, D>, P, DirectionTokens<D>) -> TemporalAdapter` | [`Pulse.temporalAdapter`](./managers/temporalAdapter.md#pulse-temporal-adapter) |
| `playback` | `(Sequence, TemporalAdapter, PlaybackOptions?) -> Playback` | [`Pulse.playback`](./components/playback.md#pulse-playback) |

## Returned objects

| Object | Responsibility |
| --- | --- |
| [`Sequence`](./components/sequence.md#sequence) | Immutable reusable compiled timeline |
| [`Builder`](./components/builder.md#builder) | Mutable fluent sequence authoring helper |
| [`TemporalAdapter`](./managers/temporalAdapter.md#temporal-adapter) | Borrowed clock/phase composition and shared execution |
| [`Playback`](./components/playback.md#playback) | One live traversal and lifecycle |

## Source-shaped reference

```text
api/
|-- components/
|   |-- builder
|   |-- playback
|   '-- sequence
|-- managers/
|   '-- temporalAdapter
'-- types/
    |-- definitions
    '-- type index
```

Every root-exported type appears in the [Type index](./types/index.md).
