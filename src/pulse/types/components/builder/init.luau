--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local SequenceTypes = require(script.Parent.sequence)

export type StepId = DefTypes.StepId
export type Params = DefTypes.Params
export type SeekMode = DefTypes.SeekMode
export type CompletionReason = DefTypes.CompletionReason
export type SeekRequest<StepT = StepId> = DefTypes.SeekRequest<StepT>
export type CallbackContext = SequenceTypes.CallbackContext
export type TransitionRule<StepT = StepId> = SequenceTypes.TransitionRule<StepT>
export type Step<StepT = StepId> = SequenceTypes.Step<StepT>
export type Event<StepT = StepId> = SequenceTypes.Event<StepT>
export type Update<StepT = StepId> = SequenceTypes.Update<StepT>
export type SignalHandler<StepT = StepId> = SequenceTypes.SignalHandler<StepT>
export type Definition<StepT = StepId> = SequenceTypes.Definition<StepT>
export type Sequence<StepT = StepId> = SequenceTypes.Sequence<StepT>

export type Builder<StepT = StepId> = {
	duration: (self: Builder<StepT>, seconds: number?) -> Builder<StepT>,
	cleanupDelay: (self: Builder<StepT>, seconds: number) -> Builder<StepT>,
	seekMode: (self: Builder<StepT>, mode: SeekMode) -> Builder<StepT>,
	loop: (self: Builder<StepT>, enabled: boolean?) -> Builder<StepT>,

	param: (self: Builder<StepT>, name: string, value: any) -> Builder<StepT>,
	params: (self: Builder<StepT>, params: Params) -> Builder<StepT>,

	step: (
		self: Builder<StepT>,
		stepId: StepT,
		time: number,
		run: ((ctx: CallbackContext, payload: any?) -> ())?,
		canEnter: ((ctx: CallbackContext, payload: any?) -> (boolean, string?))?
	) -> Builder<StepT>,

	transition: (self: Builder<StepT>, transition: TransitionRule<StepT>) -> Builder<StepT>,
	event: (self: Builder<StepT>, time: number, stepId: StepT?, run: (ctx: CallbackContext) -> ()) -> Builder<StepT>,
	eventOnly: (self: Builder<StepT>, time: number, run: (ctx: CallbackContext) -> ()) -> Builder<StepT>,
	update: (self: Builder<StepT>, name: string, run: (ctx: CallbackContext, dt: number, timePosition: number) -> ()) -> Builder<StepT>,
	signal: (self: Builder<StepT>, name: string, handler: SignalHandler<StepT>) -> Builder<StepT>,
	hold: (self: Builder<StepT>, time: number, stepId: StepT, signalName: string) -> Builder<StepT>,

	onCreate: (self: Builder<StepT>, callback: (ctx: CallbackContext) -> ()) -> Builder<StepT>,
	onPlay: (self: Builder<StepT>, callback: (ctx: CallbackContext) -> ()) -> Builder<StepT>,
	onStop: (self: Builder<StepT>, callback: (ctx: CallbackContext, reason: CompletionReason?) -> ()) -> Builder<StepT>,
	onCancel: (self: Builder<StepT>, callback: (ctx: CallbackContext, reason: CompletionReason?) -> ()) -> Builder<StepT>,
	onDestroy: (self: Builder<StepT>, callback: (ctx: CallbackContext) -> ()) -> Builder<StepT>,
	onLoop: (self: Builder<StepT>, callback: (ctx: CallbackContext, loopCount: number) -> ()) -> Builder<StepT>,
	onStep: (self: Builder<StepT>, callback: (ctx: CallbackContext, from: StepT?, to: StepT?, payload: any?) -> ()) -> Builder<StepT>,
	onParamChanged: (self: Builder<StepT>, callback: (ctx: CallbackContext, name: string, value: any, oldValue: any?) -> ()) -> Builder<StepT>,
	onSeek: (self: Builder<StepT>, callback: (ctx: CallbackContext, request: SeekRequest<StepT>) -> ()) -> Builder<StepT>,

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
