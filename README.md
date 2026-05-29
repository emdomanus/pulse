# Pulse

Pulse is a generic sequence playback runtime for Roblox.

It is intended to be the small timing spine beneath higher-level systems such as
VFX playback, skill timelines, cutscene beats, and plugin previews. Pulse owns
sequence time, scheduled steps, continuous updates, params, signals, playback
speed, time position, and lifecycle handles. Domain systems own their own
meaning: VFX emits particles and sounds, skills spawn hitboxes and validate
combat, and UI/cutscene code decides what to show.

Pulse uses pesde for deterministic dependencies:

```sh
pesde install
```

The package depends on:

- `emdomanus/advanced_utils` for hook-style events and small utilities.
- `emdomanus/tempo` for clocks, phases, and scheduler integration.

Initial package shape:

```lua
local Pulse = require(ReplicatedStorage.packages.pulse)

local runtime = Pulse.Runtime.new({
	tempo = tempo,
	phase = tempo.phases.heartbeat,
})

type StepId = "start" | "release"

local builder: Pulse.Builder<StepId> = Pulse.define()
local sequence = builder
	:duration(0.5)
	:cleanupDelay(1)
	:step("start", 0, function(ctx: Pulse.CallbackContext) end)
	:event(0, "start", function(ctx: Pulse.CallbackContext) end)
	:step("release", 0.25, function(ctx: Pulse.CallbackContext) end)
	:event(0.25, "release", function(ctx: Pulse.CallbackContext) end)
	:compile()

local handle = runtime:play(sequence, {
	params = {
		scale = 1,
	},
})
```

`steps` are generic. VFX sequences can use names such as `"release"`, while
skill adapters can use numeric steps such as `1`, `2`, and `3`.

Builders are the preferred handwritten authoring surface. They compile into the
same flat `Sequence` runtime data as `Pulse.sequence(definition)`, but avoid most
of Luau's table-literal inference rough edges.

Raw definitions are still supported. Luau can widen string literals or infer an
events array from its first element before the surrounding `Definition<StepId>`
type is applied. For typed string steps in raw definitions, pin literals and type
heterogeneous event arrays explicitly:

```lua
type StepId = "start" | "release" | "finish"

local events: { Pulse.Event<StepId> } = {
	{
		time = 0,
		step = "start" :: "start",
		run = function(ctx: Pulse.CallbackContext) end,
	},
	{
		time = 0.25,
		step = "release" :: "release",
		run = function(ctx: Pulse.CallbackContext) end,
	},
}

local definition: Pulse.Definition<StepId> = {
	seekMode = "procedural" :: "procedural",
	loop = true,
	events = events,
	updates = {
		{
			name = "tick",
			run = function(ctx: Pulse.CallbackContext, dt: number, timePosition: number)
				if math.floor(timePosition * 10) % 5 == 0 then
					ctx:signal("marker", dt)
				end
			end,
		},
	},
	signals = {
		continue = function(ctx: Pulse.CallbackContext)
			ctx:resume()
		end,
	},
}
```

Pulse has generic compiled sequences already: `Pulse.sequence(definition)` and
`builder:compile()` both return reusable normalized `Sequence` objects with
sorted events and default tables. A later VFX compiler can sit above this and
compile asset packs, attributes, or plugin JSON into Pulse builders/definitions.

A sequence can hold until external input by pausing from an event or step and
resuming from a signal. This is not coroutine yielding; the playback remains
alive and signalable while time is paused:

```lua
type StepId = "start" | "hold" | "finish"

local builder: Pulse.Builder<StepId> = Pulse.define()
local sequence = builder
	:duration(2)
	:step("start", 0)
	:step("hold", 1)
	:step("finish", 1.5)
	:hold(1, "hold", "continue")
	:compile()

local handle = runtime:play(sequence)
handle:signal("continue")
```

`cleanupDelay` keeps completed playbacks alive in `stopping` status for a short
real-time linger window after `Ended` fires. Registered `ctx:addCleanup`
callbacks run after that delay. Manual `stop`, cancels, destroys, and failures
clean up immediately.

Seek policy is explicit:

- `procedural` allows normal time repositioning.
- `forward` only allows seeks to the current or a later time.
- `none` rejects `seek` and `setTimePosition` calls.

Pulse isolates user callback errors. If an event, update, step, signal, or
lifecycle hook throws, the playback transitions to `failed` and the error is
stored on the completion object instead of escaping through the runtime phase.
Observer hook listener errors are caught and warned without changing playback
state.

Transitions are whitelist-based. Once any transition rule is present, only
matching rules may enter the next step. Event-driven step changes use the same
gate; if the step is blocked, the event body is skipped.

Looped sequences must have a positive duration. On frame hitches, Pulse replays
events for skipped loop cycles up to an internal catch-up cap, then folds the
remaining overflow into the current loop time to avoid pathological spins.

Naming convention:

- `Sequence` is the public compiled/reusable definition.
- `Playback` is the public live playback object returned by `runtime:play`.
- `Runtime:destroy()` releases the runtime binding and destroys active playbacks.
- `SequenceImpl`, `PlaybackImpl`, and `RuntimeImpl` are internal shapes.

The runtime implementation should stay deliberately small: flat sorted events,
update callbacks, param mutation, stop/cancel/destroy, generic step transitions,
and explicit seek policies. Higher-level VFX, skill, and plugin compilers should
emit builders or definitions rather than adding domain rules to Pulse itself.
