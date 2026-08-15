--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local ContextTypes = require(script.Parent.context)
local SequenceTypes = require(script.Parent.sequence)

export type StepId = DefTypes.StepId
export type Params = DefTypes.Params
export type AddressPolicy = DefTypes.AddressPolicy
export type LoopChange = DefTypes.LoopChange
export type Context<StepT = StepId> = ContextTypes.Context<StepT>
export type TransitionRule<StepT = StepId> = SequenceTypes.TransitionRule<StepT>
export type Step<StepT = StepId> = SequenceTypes.Step<StepT>
export type Event<StepT = StepId> = SequenceTypes.Event<StepT>
export type Update<StepT = StepId> = SequenceTypes.Update<StepT>
export type SignalHandler<StepT = StepId> = SequenceTypes.SignalHandler<StepT>
export type RebuildRequest = SequenceTypes.RebuildRequest
export type RebuildState<StepT = StepId> = SequenceTypes.RebuildState<StepT>
export type StepChange<StepT = StepId> = SequenceTypes.StepChange<StepT>
export type Definition<StepT = StepId> = SequenceTypes.Definition<StepT>
export type Sequence<StepT = StepId> = SequenceTypes.Sequence<StepT>

export type Builder<StepT = StepId> = {
	duration: (self: Builder<StepT>, seconds: number?) -> Builder<StepT>,
	cleanupDelay: (self: Builder<StepT>, seconds: number) -> Builder<StepT>,
	addressPolicy: (self: Builder<StepT>, policy: AddressPolicy) -> Builder<StepT>,
	loop: (self: Builder<StepT>, enabled: boolean?) -> Builder<StepT>,

	param: (self: Builder<StepT>, name: string, value: unknown) -> Builder<StepT>,
	params: (self: Builder<StepT>, params: Params) -> Builder<StepT>,
	step: (self: Builder<StepT>, stepId: StepT, definition: Step<StepT>) -> Builder<StepT>,
	transition: (self: Builder<StepT>, rule: TransitionRule<StepT>) -> Builder<StepT>,
	event: (self: Builder<StepT>, event: Event<StepT>) -> Builder<StepT>,
	update: (self: Builder<StepT>, update: Update<StepT>) -> Builder<StepT>,
	signal: (self: Builder<StepT>, name: string, handler: SignalHandler<StepT>) -> Builder<StepT>,
	hold: (self: Builder<StepT>, time: number, stepId: StepT, signalName: string) -> Builder<StepT>,

	onPlay: (self: Builder<StepT>, callback: (ctx: Context<StepT>) -> ()) -> Builder<StepT>,
	onStop: (self: Builder<StepT>, callback: (ctx: Context<StepT>, reason: string?) -> ()) -> Builder<StepT>,
	onCancel: (self: Builder<StepT>, callback: (ctx: Context<StepT>, reason: string?) -> ()) -> Builder<StepT>,
	onDestroy: (self: Builder<StepT>, callback: (ctx: Context<StepT>) -> ()) -> Builder<StepT>,
	onRebuild: (
		self: Builder<StepT>,
		callback: (ctx: Context<StepT>, request: RebuildRequest) -> RebuildState<StepT>
	) -> Builder<StepT>,
	onLoop: (self: Builder<StepT>, callback: (ctx: Context<StepT>, change: LoopChange) -> ()) -> Builder<StepT>,
	onStep: (
		self: Builder<StepT>,
		callback: (ctx: Context<StepT>, change: StepChange<StepT>) -> ()
	) -> Builder<StepT>,
	onParamChanged: (
		self: Builder<StepT>,
		callback: (ctx: Context<StepT>, name: string, value: unknown, oldValue: unknown?) -> ()
	) -> Builder<StepT>,

	build: (self: Builder<StepT>) -> Definition<StepT>,
	compile: (self: Builder<StepT>) -> Sequence<StepT>,
}

export type BuilderImpl<StepT = StepId> = Builder<StepT> & {
	_definition: Definition<StepT>,
	_steps: { [StepT]: Step<StepT> },
	_events: { Event<StepT> },
	_updates: { Update<StepT> },
	_signals: { [string]: SignalHandler<StepT> },
	_transitions: { TransitionRule<StepT> },
	_params: Params,
}

return {}
