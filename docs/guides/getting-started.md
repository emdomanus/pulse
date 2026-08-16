# Getting Started

## Compile a sequence

Use the builder for handwritten timelines:

```luau
local sequence = Pulse.builder()
	:duration(1.2)
	:event({
		time = 0.15,
		run = function(playback)
			spawnHitEffect()
		end,
		reverse = function(playback)
			removeHitEffect()
		end,
	})
	:update({
		startTime = 0.2,
		endTime = 0.8,
		run = function(playback, dt, timePosition)
			updateTrail(dt, timePosition)
		end,
	})
	:compile()
```

The resulting [`Sequence`](../api/components/sequence.md#sequence) is frozen and reusable. Raw
definitions passed to [`Pulse.sequence`](../api/components/sequence.md#pulse-sequence) compile to
the same representation.

## Adapt a clock

Pulse accepts a structural
[`ProviderClock`](../api/managers/temporalAdapter.md#provider-clock), not a runtime or service. Bind
the host-selected phase and provider direction tokens once:

```luau
local adapter = Pulse.temporalAdapter(providerClock, presentationPhase, {
	forward = providerDirections.forward,
	backward = providerDirections.backward,
})
```

The adapter borrows the clock. Keep one adapter for all playbacks using that exact clock and phase
so updating playbacks share continuous execution.

## Create and play

```luau
local playback = Pulse.playback(sequence, adapter, {
	playbackSpeed = 1,
	position = { timePosition = 0 },
})

local releaseEnded = playback:onEnded(function(completion)
	print(completion.status, completion.reason)
end)

playback:play()
```

Construction does not start playback. Register observers first, then call `play`; synchronous
completion or failure cannot be missed. A Playback instance has one lifecycle. Create another
Playback from the same Sequence to run it again independently.

## Control a live playback

```luau
playback:pause()
playback:setPlaybackSpeed(0.5)
playback:seek({ timePosition = 0.4 })
playback:resume()
```

Pause and speed changes preserve the current sequence position. A seek is handled by the
Sequence's address policy. For looping sequences, include `loopIndex` when the exact cycle matters.

## Release ownership

```luau
releaseEnded()
playback:cancel("superseded")
adapter:destroy()
```

Cancel or destroy live playbacks when their owning feature ends. Destroy the adapter when the host
composition no longer uses that clock/phase pair. Adapter destruction does not destroy the clock.
