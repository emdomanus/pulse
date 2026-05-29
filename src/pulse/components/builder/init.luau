--!strict
--!optimize 2
--!native

local BuilderTypes = require(script.Parent.Parent.types.components.builder)
local Sequence = require(script.Parent.sequence)

export type StepId = BuilderTypes.StepId
export type Params = BuilderTypes.Params
export type SeekMode = BuilderTypes.SeekMode
export type CompletionReason = BuilderTypes.CompletionReason
export type SeekRequest<StepT = StepId> = BuilderTypes.SeekRequest<StepT>
export type CallbackContext = BuilderTypes.CallbackContext
export type Definition<StepT = StepId> = BuilderTypes.Definition<StepT>
export type Sequence<StepT = StepId> = BuilderTypes.Sequence<StepT>
export type Builder<StepT = StepId> = BuilderTypes.Builder<StepT>
type BuilderImpl<StepT = StepId> = BuilderTypes.BuilderImpl<StepT>

local Builder = {}
Builder.__index = Builder

local function syncDefinition<StepT>(self: BuilderImpl<StepT>): Definition<StepT>
	local definition = self._definition
	definition.params = self._params
	definition.steps = self._steps
	definition.transitions = self._transitions
	definition.events = self._events
	definition.updates = self._updates
	definition.signals = self._signals

	return definition
end

function Builder.new<StepT>(): Builder<StepT>
	local self: BuilderImpl<StepT> = setmetatable({
		_definition = {},
		_steps = {},
		_events = {},
		_updates = {},
		_signals = {},
		_transitions = {},
		_params = {},
	}, Builder) :: any

	return self
end

function Builder.duration<StepT>(self: BuilderImpl<StepT>, seconds: number?): Builder<StepT>
	self._definition.duration = seconds
	return self
end

function Builder.cleanupDelay<StepT>(self: BuilderImpl<StepT>, seconds: number): Builder<StepT>
	self._definition.cleanupDelay = seconds
	return self
end

function Builder.seekMode<StepT>(self: BuilderImpl<StepT>, mode: BuilderTypes.SeekMode): Builder<StepT>
	self._definition.seekMode = mode
	return self
end

function Builder.loop<StepT>(self: BuilderImpl<StepT>, enabled: boolean?): Builder<StepT>
	self._definition.loop = if enabled == nil then true else enabled
	return self
end

function Builder.param<StepT>(self: BuilderImpl<StepT>, name: string, value: any): Builder<StepT>
	self._params[name] = value
	return self
end

function Builder.params<StepT>(self: BuilderImpl<StepT>, params: BuilderTypes.Params): Builder<StepT>
	for name, value in params do
		self._params[name] = value
	end

	return self
end

function Builder.step<StepT>(
	self: BuilderImpl<StepT>,
	stepId: StepT,
	time: number,
	run: ((ctx: BuilderTypes.CallbackContext, payload: any?) -> ())?,
	canEnter: ((ctx: BuilderTypes.CallbackContext, payload: any?) -> (boolean, string?))?
): Builder<StepT>
	self._steps[stepId] = {
		time = time,
		run = run,
		canEnter = canEnter,
	}

	return self
end

function Builder.transition<StepT>(
	self: BuilderImpl<StepT>,
	transition: BuilderTypes.TransitionRule<StepT>
): Builder<StepT>
	table.insert(self._transitions, transition)
	return self
end

function Builder.event<StepT>(
	self: BuilderImpl<StepT>,
	time: number,
	stepId: StepT?,
	run: (ctx: BuilderTypes.CallbackContext) -> ()
): Builder<StepT>
	table.insert(self._events, {
		time = time,
		step = stepId,
		run = run,
	})

	return self
end

function Builder.eventOnly<StepT>(
	self: BuilderImpl<StepT>,
	time: number,
	run: (ctx: BuilderTypes.CallbackContext) -> ()
): Builder<StepT>
	return self:event(time, nil, run)
end

function Builder.update<StepT>(
	self: BuilderImpl<StepT>,
	name: string,
	run: (ctx: BuilderTypes.CallbackContext, dt: number, timePosition: number) -> ()
): Builder<StepT>
	table.insert(self._updates, {
		name = name,
		run = run,
	})

	return self
end

function Builder.signal<StepT>(
	self: BuilderImpl<StepT>,
	name: string,
	handler: BuilderTypes.SignalHandler<StepT>
): Builder<StepT>
	self._signals[name] = handler
	return self
end

function Builder.hold<StepT>(
	self: BuilderImpl<StepT>,
	time: number,
	stepId: StepT,
	signalName: string
): Builder<StepT>
	self:event(time, stepId, function(ctx: BuilderTypes.CallbackContext)
		ctx:pause()
	end)

	self:signal(signalName, function(ctx: BuilderTypes.CallbackContext)
		ctx:resume()
	end)

	return self
end

function Builder.onCreate<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: BuilderTypes.CallbackContext) -> ()
): Builder<StepT>
	self._definition.onCreate = callback
	return self
end

function Builder.onPlay<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: BuilderTypes.CallbackContext) -> ()
): Builder<StepT>
	self._definition.onPlay = callback
	return self
end

function Builder.onStop<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: BuilderTypes.CallbackContext, reason: BuilderTypes.CompletionReason?) -> ()
): Builder<StepT>
	self._definition.onStop = callback
	return self
end

function Builder.onCancel<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: BuilderTypes.CallbackContext, reason: BuilderTypes.CompletionReason?) -> ()
): Builder<StepT>
	self._definition.onCancel = callback
	return self
end

function Builder.onDestroy<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: BuilderTypes.CallbackContext) -> ()
): Builder<StepT>
	self._definition.onDestroy = callback
	return self
end

function Builder.onLoop<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: BuilderTypes.CallbackContext, loopCount: number) -> ()
): Builder<StepT>
	self._definition.onLoop = callback
	return self
end

function Builder.onStep<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: BuilderTypes.CallbackContext, from: StepT?, to: StepT?, payload: any?) -> ()
): Builder<StepT>
	self._definition.onStep = callback
	return self
end

function Builder.onParamChanged<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: BuilderTypes.CallbackContext, name: string, value: any, oldValue: any?) -> ()
): Builder<StepT>
	self._definition.onParamChanged = callback
	return self
end

function Builder.onSeek<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: BuilderTypes.CallbackContext, request: BuilderTypes.SeekRequest<StepT>) -> ()
): Builder<StepT>
	self._definition.onSeek = callback
	return self
end

function Builder.build<StepT>(self: BuilderImpl<StepT>): Definition<StepT>
	local definition = syncDefinition(self)
	local built: Definition<StepT> = table.clone(definition)
	built.params = table.clone(self._params)
	built.steps = table.clone(self._steps)
	built.transitions = table.clone(self._transitions)
	built.events = table.clone(self._events)
	built.updates = table.clone(self._updates)
	built.signals = table.clone(self._signals)

	return built
end

function Builder.compile<StepT>(self: BuilderImpl<StepT>): Sequence<StepT>
	return Sequence.compileOwned(self:build())
end

return {
	new = Builder.new,
}
