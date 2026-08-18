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
		run = function(_playback, context)
			spawnHitEffect(context.character, context.worldPosition)
		end,
		reverse = function(_playback, context)
			removeHitEffect(context.character)
		end,
	})
	:sample({
		startTime = 0.2,
		endTime = 0.8,
		run = function(_playback, sample, context)
			setTrailAt(context.character, sample.position.timePosition, sample.rate)
		end,
	})
	:compile()
```

The resulting [`Sequence`](../api/components/sequence.md#sequence) is frozen and reusable. A
[`Sample`](../api/components/sequence.md#sample) represents absolute state at the final position;
it receives no synthetic delta and does not integrate historical frames. Raw definitions passed to
[`Pulse.sequence`](../api/components/sequence.md#pulse-sequence) compile identically.

## Create a raw Playback

```luau
local context: PresentationContext = {
	character = character,
	worldPosition = targetPosition,
	camera = workspace.CurrentCamera,
}

local playback = Pulse.playback(sequence, context, {
	playbackSpeed = 1,
	position = { timePosition = 0 },
	initialMode = "reconstruct",
})

local releaseEnded = playback:onEnded(function(completion)
	print(completion.status, completion.reason)
end)

playback:play({ position = 50, rate = 1 })
playback:evaluate({ position = 50.25, rate = 1 })
playback:evaluate({ position = 50.75, rate = 1 })
```

Construction does not start playback. Register observers first, then pass a finite absolute source
sample to `play`. A Playback instance has one lifecycle; create another from the same Sequence to
run it independently.

`TimeSample.position` is source time, not sequence-local time. The first sample anchors the initial
Sequence address. Future displacement maps through local playback speed. `rate` is atomic metadata
for direction and Sample output and is not multiplied into that displacement.

The context argument is required even when its intentional value is `nil`. Its type is tied to the
compiled Sequence, while each invocation receives its own host-owned objects and capabilities.

## Apply mutations at an exact sample

Raw Playback controls act at the most recently accepted coordinate:

```luau
playback:evaluate(currentSourceSample)
playback:setPlaybackSpeed(0.5)

playback:evaluate(laterSourceSample)
playback:pause()
```

There is no hidden clock read between calls. If a mutation belongs at a newer exact coordinate,
evaluate that sample first. On resume, the first later evaluation re-anchors the stored position so
paused source movement is not caught up.

## Address explicitly

```luau
playback:seek({ timePosition = 0.4 }, "skip")
playback:seek({ timePosition = 0.7 }, "reconstruct")
playback:cancel("superseded")
```

`skip` suppresses historical Events and retains the cleanup generation. `reconstruct` flushes the
generation LIFO, opens a new one, and replays canonical forward history. Cancellation is an
independent lifecycle operation. For looping Sequences, include `loopIndex` when exact cycle
identity matters.

## Materialize a late Playback

Use `onAddress` beside the timeline and select invocation-specific `initialMode = "skip"` when
joining an effect already in progress:

```luau
local lateSequence = builder
	:duration(1.2)
	:event({
		time = 0.15,
		run = function(_playback, lateContext)
			spawnImpactBurst(lateContext.worldPosition)
		end,
	})
	:onAddress(function(_playback, info, lateContext)
		materializeActivePresentation(lateContext, info.target.timePosition)
	end)
	:compile()

local late = Pulse.playback(lateSequence, context, {
	position = { timePosition = replicatedAge },
	initialMode = "skip",
})
late:play(sourceSample)
```

The historical burst does not run. Pulse first places the exact target, then calls `onAddress`,
then calls active Samples once there. The host can create only resources still relevant at that
elapsed position.

## Add the optional ClockDriver

When a scheduling-capable provider should own evaluation cadence, attach an idle raw Playback:

```luau
local driver = Pulse.clockDriver(providerClock, presentationPhase, {
	forward = providerDirections.forward,
	backward = providerDirections.backward,
})

local raw = Pulse.playback(sequence, context)
local driven = driver:attach(raw, {
	discontinuityMode = "skip",
})

driven:play()
```

The explicit discontinuity mode belongs to this attachment, not the Sequence. The driven facade
reads/evaluates the current provider sample before externally requested mutations. Attachment
transfers exclusive temporal-control ownership: do not mutate `raw` again until `driven:detach()`
returns it. Event-only attachments ordinarily use only next-boundary deadlines. Attachments share
one driver phase binding while a Sample is active, reverse movement is poised at an excluded Sample
end, or an outward zero-distance loop join awaits actual movement.

## Release ownership

```luau
releaseEnded()
driven:cancel("superseded")
driver:destroy()
```

Driver destruction fails attached live Playbacks but never destroys the borrowed provider. Call
`driven:detach()` instead when future evaluation should return to a raw host. A
`PlaybackControl` received by authored callback code may be used synchronously, but must not be
retained for asynchronous invocation while the Playback is driven.

## Instantaneous sequences

A non-looping Sequence may have `duration = 0`. Its callbacks run synchronously inside raw
`Playback:play(sample)` or driven `play()`, followed by cleanup and Ended without scheduler
ownership. Initial `reconstruct` runs time-zero Events; initial `skip` suppresses them.
Zero-duration Sequences cannot loop or contain a valid Sample interval.
