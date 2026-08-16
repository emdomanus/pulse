# Type Index

Every type below is exported from the Pulse package root. Links point to the canonical API page that
owns its behavior or value contract.

```luau
type Sequence = Pulse.Sequence
type Playback = Pulse.Playback
type TemporalAdapter = Pulse.TemporalAdapter
```

## Shared values

- [Release](./definitions.md#release)
- [TraversalDirection](./definitions.md#traversal-direction)
- [AddressPolicy](./definitions.md#address-policy)
- [SequenceAddress](./definitions.md#sequence-address)
- [PlaybackPosition](./definitions.md#playback-position)
- [LoopChange](./definitions.md#loop-change)
- [ActiveStatus](./definitions.md#active-status)
- [TerminalStatus](./definitions.md#terminal-status)
- [Status](./definitions.md#status)
- [Completion](./definitions.md#completion)

## Sequence authoring

- [PlaybackContext](../components/playback.md#playback-context)
- [Event](../components/sequence.md#event)
- [Update](../components/sequence.md#update)
- [SequenceDefinition](../components/sequence.md#sequence-definition)
- [Sequence](../components/sequence.md#sequence)
- [Builder](../components/builder.md#builder)

## Playback

- [PlaybackOptions](../components/playback.md#playback-options)
- [EndedCallback](../components/playback.md#ended-callback)
- [LoopedCallback](../components/playback.md#looped-callback)
- [Playback](../components/playback.md#playback)

## Temporal composition

- [ClockSample](../managers/temporalAdapter.md#clock-sample)
- [ClockChange](../managers/temporalAdapter.md#clock-change)
- [ProviderClock&lt;PhaseInputT, DirectionTokenT&gt;](../managers/temporalAdapter.md#provider-clock)
- [DirectionTokens&lt;DirectionTokenT&gt;](../managers/temporalAdapter.md#direction-tokens)
- [TemporalAdapter](../managers/temporalAdapter.md#temporal-adapter)
