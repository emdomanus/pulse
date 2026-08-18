# Type Index

Every type below is exported from the Pulse package root. Links point to the page that owns its
behavior or value contract.

```luau
type Sequence<ContextT> = Pulse.Sequence<ContextT>
type Playback = Pulse.Playback
type ClockDriver = Pulse.ClockDriver
```

## Shared values

- [Release](./definitions.md#release)
- [TraversalDirection](./definitions.md#traversal-direction)
- [AddressMode](./definitions.md#address-mode)
- [AddressCause](./definitions.md#address-cause)
- [TimeSample](./definitions.md#time-sample)
- [SequenceAddress](./definitions.md#sequence-address)
- [PlaybackPosition](./definitions.md#playback-position)
- [SampleInfo](./definitions.md#sample-info)
- [AddressInfo](./definitions.md#address-info)
- [LoopChange](./definitions.md#loop-change)
- [ActiveStatus](./definitions.md#active-status)
- [TerminalStatus](./definitions.md#terminal-status)
- [Status](./definitions.md#status)
- [Completion](./definitions.md#completion)

## Sequence authoring

- [PlaybackControl](../components/playback.md#playback-control)
- [Event&lt;ContextT&gt;](../components/sequence.md#event)
- [Sample&lt;ContextT&gt;](../components/sequence.md#sample)
- [SequenceDefinition&lt;ContextT&gt;](../components/sequence.md#sequence-definition)
- [Sequence&lt;ContextT&gt;](../components/sequence.md#sequence)
- [Builder&lt;ContextT&gt;](../components/builder.md#builder)

## Raw Playback

- [PlaybackOptions](../components/playback.md#playback-options)
- [EndedCallback](../components/playback.md#ended-callback)
- [LoopedCallback](../components/playback.md#looped-callback)
- [Playback](../components/playback.md#playback)

## Optional clock driver

- [ProviderClock&lt;PhaseInputT, DirectionTokenT&gt;](../managers/clockDriver.md#provider-clock)
- [DirectionTokens&lt;DirectionTokenT&gt;](../managers/clockDriver.md#direction-tokens)
- [DriverDiscontinuityMode](../managers/clockDriver.md#driver-discontinuity-mode)
- [ClockDriverAttachmentOptions](../managers/clockDriver.md#clock-driver-attachment-options)
- [DrivenPlayback](../managers/clockDriver.md#driven-playback)
- [ClockDriver](../managers/clockDriver.md#clock-driver)
