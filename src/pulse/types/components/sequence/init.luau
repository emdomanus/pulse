--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local ContextTypes = require(script.Parent.context)

export type StepId = DefTypes.StepId
export type Params = DefTypes.Params
export type AddressPolicy = DefTypes.AddressPolicy
export type AddressCause = DefTypes.AddressCause
export type AddressDirection = DefTypes.AddressDirection
export type TraversalDirection = DefTypes.TraversalDirection
export type LoopChange = DefTypes.LoopChange
export type SequenceAddress = DefTypes.SequenceAddress
export type PlaybackPosition = DefTypes.PlaybackPosition
export type StepChangeCause = DefTypes.StepChangeCause
export type Context<StepT = StepId> = ContextTypes.Context<StepT>

export type ReverseEventAction<StepT = StepId> = ((ctx: Context<StepT>) -> ()) | "ignore" | "cancel"
export type ReverseStepAction<StepT = StepId> = ((ctx: Context<StepT>, payload: unknown?) -> ()) | "ignore" | "cancel"

export type Event<StepT = StepId> = {
	time: number,
	name: string?,
	step: StepT?,
	run: ((ctx: Context<StepT>) -> ())?,
	reverse: ReverseEventAction<StepT>?,
}

export type Step<StepT = StepId> = {
	time: number,
	run: ((ctx: Context<StepT>, payload: unknown?) -> ())?,
	reverse: ReverseStepAction<StepT>?,
	canEnter: ((ctx: Context<StepT>, payload: unknown?) -> (boolean, string?))?,
}

export type Steps<StepT = StepId> = { [StepT]: Step<StepT> }

export type StepChange<StepT = StepId> = {
	from: StepT?,
	to: StepT?,
	payload: unknown?,
	cause: StepChangeCause,
	direction: TraversalDirection?,
}

export type TransitionRule<StepT = StepId> = {
	from: StepT?,
	to: StepT?,
	after: number?,
	before: number?,
	canStep: ((ctx: Context<StepT>, from: StepT?, to: StepT?, payload: unknown?) -> (boolean, string?))?,
}

export type Update<StepT = StepId> = {
	name: string?,
	run: (ctx: Context<StepT>, dt: number, timePosition: number) -> (),
}

export type SignalHandler<StepT = StepId> = (ctx: Context<StepT>, payload: unknown?) -> ()

export type RebuildRequest = {
	from: PlaybackPosition,
	to: PlaybackPosition,
	cause: AddressCause,
	direction: AddressDirection,
}

export type RebuildState<StepT = StepId> = {
	step: StepT?,
}

export type Definition<StepT = StepId> = {
	duration: number?,
	cleanupDelay: number?,
	addressPolicy: AddressPolicy?,
	loop: boolean?,
	params: Params?,

	steps: Steps<StepT>?,
	transitions: { TransitionRule<StepT> }?,
	events: { Event<StepT> }?,
	updates: { Update<StepT> }?,
	signals: { [string]: SignalHandler<StepT> }?,

	onPlay: ((ctx: Context<StepT>) -> ())?,
	onStop: ((ctx: Context<StepT>, reason: string?) -> ())?,
	onCancel: ((ctx: Context<StepT>, reason: string?) -> ())?,
	onDestroy: ((ctx: Context<StepT>) -> ())?,
	onRebuild: ((ctx: Context<StepT>, request: RebuildRequest) -> RebuildState<StepT>)?,
	onLoop: ((ctx: Context<StepT>, change: LoopChange) -> ())?,
	onStep: ((ctx: Context<StepT>, change: StepChange<StepT>) -> ())?,
	onParamChanged: ((ctx: Context<StepT>, name: string, value: unknown, oldValue: unknown?) -> ())?,
}

export type Sequence<StepT = StepId> = {
	duration: number?,
	cleanupDelay: number,
	addressPolicy: AddressPolicy,
	loop: boolean,
	defaultParams: Params,
	steps: Steps<StepT>,
	transitions: { TransitionRule<StepT> },
	events: { Event<StepT> },
	updates: { Update<StepT> },
	signals: { [string]: SignalHandler<StepT> },
	definition: Definition<StepT>,
}

export type CompiledEvent<StepT = StepId> = {
	_identity: number,
	_authorIndex: number,
	definition: Event<StepT>,
	reverse: ReverseEventAction<StepT>,
}

export type CompiledStep<StepT = StepId> = {
	definition: Step<StepT>,
	reverse: ReverseStepAction<StepT>,
}

export type SequenceImpl<StepT = StepId> = Sequence<StepT> & {
	_forwardEvents: { CompiledEvent<StepT> },
	_reverseEvents: { CompiledEvent<StepT> },
	_compiledSteps: { [StepT]: CompiledStep<StepT> },
}

return {}
