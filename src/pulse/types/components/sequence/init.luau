--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local ContextTypes = require(script.Parent.context)

export type StepId = DefTypes.StepId
export type Params = DefTypes.Params
export type SeekMode = DefTypes.SeekMode
export type CompletionReason = DefTypes.CompletionReason
export type SeekRequest<StepT = StepId> = DefTypes.SeekRequest<StepT>
export type Context<StepT = StepId> = ContextTypes.Context<StepT>
export type CallbackContext = Context<any>

export type TransitionRule<StepT = StepId> = {
	from: StepT?,
	to: StepT?,
	after: number?,
	before: number?,
	canStep: ((ctx: CallbackContext, from: StepT?, to: StepT?, payload: any?) -> (boolean, string?))?,
}

export type Step<StepT = StepId> = {
	time: number,
	run: ((ctx: CallbackContext, payload: any?) -> ())?,
	canEnter: ((ctx: CallbackContext, payload: any?) -> (boolean, string?))?,
}

export type Steps<StepT = StepId> = { [StepT]: Step<StepT> }

export type Event<StepT = StepId> = {
	time: number,
	name: string?,
	step: StepT?,
	run: (ctx: CallbackContext) -> (),
}

export type Update<StepT = StepId> = {
	name: string?,
	run: (ctx: CallbackContext, dt: number, timePosition: number) -> (),
}

export type SignalHandler<StepT = StepId> = (ctx: CallbackContext, payload: any?) -> ()

export type Definition<StepT = StepId> = {
	duration: number?,
	cleanupDelay: number?,
	seekMode: SeekMode?,
	loop: boolean?,
	params: Params?,

	steps: Steps<StepT>?,
	transitions: { TransitionRule<StepT> }?,
	events: { Event<StepT> }?,
	updates: { Update<StepT> }?,
	signals: { [string]: SignalHandler<StepT> }?,

	onCreate: ((ctx: CallbackContext) -> ())?,
	onPlay: ((ctx: CallbackContext) -> ())?,
	onStop: ((ctx: CallbackContext, reason: CompletionReason?) -> ())?,
	onCancel: ((ctx: CallbackContext, reason: CompletionReason?) -> ())?,
	onDestroy: ((ctx: CallbackContext) -> ())?,
	onLoop: ((ctx: CallbackContext, loopCount: number) -> ())?,
	onStep: ((ctx: CallbackContext, from: StepT?, to: StepT?, payload: any?) -> ())?,
	onParamChanged: ((ctx: CallbackContext, name: string, value: any, oldValue: any?) -> ())?,
	onSeek: ((ctx: CallbackContext, request: SeekRequest<StepT>) -> ())?,
}

export type Sequence<StepT = StepId> = {
	duration: number?,
	cleanupDelay: number,
	seekMode: SeekMode,
	loop: boolean,
	defaultParams: Params,
	steps: Steps<StepT>,
	transitions: { TransitionRule<StepT> },
	events: { Event<StepT> },
	updates: { Update<StepT> },
	signals: { [string]: SignalHandler<StepT> },
	definition: Definition<StepT>,
}

export type SequenceImpl<StepT = StepId> = Sequence<StepT> & {
	_sortedEvents: { Event<StepT> },
}

return {}
