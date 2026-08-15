--!strict
--!optimize 2
--!native

local BuilderTypes = require(script.Parent.Parent.Parent.Parent.types.components.builder)
local Sequence = require(script.Parent.Parent.Parent.sequence.shared.sequence)

type Params = BuilderTypes.Params
type AddressPolicy = BuilderTypes.AddressPolicy
type Context<StepT> = BuilderTypes.Context<StepT>
type Definition<StepT> = BuilderTypes.Definition<StepT>
type Step<StepT> = BuilderTypes.Step<StepT>
type TransitionRule<StepT> = BuilderTypes.TransitionRule<StepT>
type Event<StepT> = BuilderTypes.Event<StepT>
type Update<StepT> = BuilderTypes.Update<StepT>
type SignalHandler<StepT> = BuilderTypes.SignalHandler<StepT>
type RebuildRequest = BuilderTypes.RebuildRequest
type RebuildState<StepT> = BuilderTypes.RebuildState<StepT>
type LoopChange = BuilderTypes.LoopChange
type StepChange<StepT> = BuilderTypes.StepChange<StepT>
type Sequence<StepT> = BuilderTypes.Sequence<StepT>
type Builder<StepT> = BuilderTypes.Builder<StepT>
type BuilderImpl<StepT> = BuilderTypes.BuilderImpl<StepT>

type BuilderModule = {
	new: <StepT>() -> Builder<StepT>,
}

local Builder = {}
Builder.__index = Builder

function Builder.new<StepT>(): Builder<StepT>
	local definition: Definition<StepT> = {}
	local steps: { [StepT]: Step<StepT> } = {}
	local events: { Event<StepT> } = {}
	local updates: { Update<StepT> } = {}
	local signals: { [string]: SignalHandler<StepT> } = {}
	local transitions: { TransitionRule<StepT> } = {}
	local params: Params = {}
	local self = (
		setmetatable({
			_definition = definition,
			_steps = steps,
			_events = events,
			_updates = updates,
			_signals = signals,
			_transitions = transitions,
			_params = params,
		}, Builder) :: unknown
	) :: BuilderImpl<StepT>

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

function Builder.addressPolicy<StepT>(self: BuilderImpl<StepT>, policy: AddressPolicy): Builder<StepT>
	self._definition.addressPolicy = policy
	return self
end

function Builder.loop<StepT>(self: BuilderImpl<StepT>, enabled: boolean?): Builder<StepT>
	self._definition.loop = if enabled == nil then true else enabled
	return self
end

function Builder.param<StepT>(self: BuilderImpl<StepT>, name: string, value: unknown): Builder<StepT>
	self._params[name] = value
	return self
end

function Builder.params<StepT>(self: BuilderImpl<StepT>, params: Params): Builder<StepT>
	for name, value in params do
		self._params[name] = value
	end
	return self
end

function Builder.step<StepT>(self: BuilderImpl<StepT>, stepId: StepT, definition: Step<StepT>): Builder<StepT>
	self._steps[stepId] = table.clone(definition)
	return self
end

function Builder.transition<StepT>(self: BuilderImpl<StepT>, rule: TransitionRule<StepT>): Builder<StepT>
	table.insert(self._transitions, table.clone(rule))
	return self
end

function Builder.event<StepT>(self: BuilderImpl<StepT>, event: Event<StepT>): Builder<StepT>
	table.insert(self._events, table.clone(event))
	return self
end

function Builder.update<StepT>(self: BuilderImpl<StepT>, update: Update<StepT>): Builder<StepT>
	table.insert(self._updates, table.clone(update))
	return self
end

function Builder.signal<StepT>(self: BuilderImpl<StepT>, name: string, handler: SignalHandler<StepT>): Builder<StepT>
	self._signals[name] = handler
	return self
end

function Builder.hold<StepT>(self: BuilderImpl<StepT>, time: number, stepId: StepT, signalName: string): Builder<StepT>
	self:event({
		time = time,
		step = stepId,
		run = function(ctx: Context<StepT>)
			ctx:pause()
		end,
		reverse = "ignore",
	})
	self:signal(signalName, function(ctx: Context<StepT>)
		ctx:resume()
	end)
	return self
end

function Builder.onPlay<StepT>(self: BuilderImpl<StepT>, callback: (ctx: Context<StepT>) -> ()): Builder<StepT>
	self._definition.onPlay = callback
	return self
end

function Builder.onStop<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: Context<StepT>, reason: string?) -> ()
): Builder<StepT>
	self._definition.onStop = callback
	return self
end

function Builder.onCancel<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: Context<StepT>, reason: string?) -> ()
): Builder<StepT>
	self._definition.onCancel = callback
	return self
end

function Builder.onDestroy<StepT>(self: BuilderImpl<StepT>, callback: (ctx: Context<StepT>) -> ()): Builder<StepT>
	self._definition.onDestroy = callback
	return self
end

function Builder.onRebuild<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: Context<StepT>, request: RebuildRequest) -> RebuildState<StepT>
): Builder<StepT>
	self._definition.onRebuild = callback
	return self
end

function Builder.onLoop<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: Context<StepT>, change: LoopChange) -> ()
): Builder<StepT>
	self._definition.onLoop = callback
	return self
end

function Builder.onStep<StepT>(
	self: BuilderImpl<StepT>,
	callback: (ctx: Context<StepT>, change: StepChange<StepT>) -> ()
): Builder<StepT>
	self._definition.onStep = callback
	return self
end

function Builder.onParamChanged<StepT>(
	self: BuilderImpl<StepT>,
	callback: (
		ctx: Context<StepT>,
		name: string,
		value: unknown,
		oldValue: unknown?
	) -> ()
): Builder<StepT>
	self._definition.onParamChanged = callback
	return self
end

function Builder.build<StepT>(self: BuilderImpl<StepT>): Definition<StepT>
	local definition: Definition<StepT> = table.clone(self._definition)
	definition.params = table.clone(self._params)

	local steps: { [StepT]: Step<StepT> } = {}
	for stepId, step in self._steps do
		steps[stepId] = table.clone(step)
	end
	definition.steps = steps

	local transitions: { TransitionRule<StepT> } = {}
	for _, rule in self._transitions do
		table.insert(transitions, table.clone(rule))
	end
	definition.transitions = transitions

	local events: { Event<StepT> } = {}
	for _, event in self._events do
		table.insert(events, table.clone(event))
	end
	definition.events = events

	local updates: { Update<StepT> } = {}
	for _, update in self._updates do
		table.insert(updates, table.clone(update))
	end
	definition.updates = updates
	definition.signals = table.clone(self._signals)
	return definition
end

function Builder.compile<StepT>(self: BuilderImpl<StepT>): Sequence<StepT>
	return Sequence.compile(self:build())
end

local module: BuilderModule = {
	new = Builder.new,
}

return module
