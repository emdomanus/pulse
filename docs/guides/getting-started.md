# Getting Started

## Compile a sequence

Use the builder for handwritten timelines. Give it the per-play context type expected by authored
callbacks:

```luau
type PresentationContext = {
	character: Model,
	worldPosition: Vector3,
	camera: Camera,
}

local builder: Pulse.Builder<PresentationContext> = Pulse.builder()
local sequence = builder
	:duration(1.2)
	:event({
		time = 0.15,
		run = function(playback, context)
			spawnHitEffect(context.character, context.worldPosition)
		end,
		reverse = function(playback, context)
			removeHitEffect(context.character)
		end,
	})
	:update({
		startTime = 0.2,
		endTime = 0.8,
		run = function(playback, dt, timePosition, context)
			updateTrail(context.character, dt, timePosition)
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
local context: PresentationContext = {
	character = character,
	worldPosition = targetPosition,
	camera = workspace.CurrentCamera,
}

local playback = Pulse.playback(sequence, adapter, context, {
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

The context argument is required even when its intentional value is `nil`. Its type is tied to the
compiled Sequence, so one presentation definition remains reusable while each invocation receives
its own character, position, camera, audio commands, or other host-owned data.

## Materialize a late playback

Use `onAddress` to compile a state materializer beside the timeline and select `initialMode =
"skip"` when joining an already-running effect:

```luau
local sequence = builder
	:duration(1.2)
	:event({
		time = 0.15,
		run = function(_playback, context)
			spawnImpactBurst(context.worldPosition)
		end,
	})
	:onAddress(function(_playback, info, context)
		materializeActivePresentation(context, info.target.timePosition)
	end)
	:compile()

local playback = Pulse.playback(sequence, adapter, context, {
	position = { timePosition = replicatedAge },
	initialMode = "skip",
})
playback:play()
```

The impact event is historical and does not run. `onAddress` receives the exact target so the host
can create only state that should still be active, such as beams, trails, animations, or curve
values. Pulse does not interpret or own that presentation state.

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

## Instantaneous sequences

A non-looping Sequence may have `duration = 0`. Its callbacks run synchronously inside
`Playback:play`, then cleanup and Ended run without scheduling a task or phase binding. Initial
`reconstruct` runs time-zero events; initial `skip` suppresses them. Zero-duration Sequences cannot
loop or contain a valid update interval.
