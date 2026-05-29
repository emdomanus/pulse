--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)

export type StepId = DefTypes.StepId
export type SeekRequest<StepT = StepId> = DefTypes.SeekRequest<StepT>
export type CompletionReason = DefTypes.CompletionReason

export type Context<StepT = StepId> = {
	getTimePosition: (self: Context<StepT>) -> number,
	setTimePosition: (self: Context<StepT>, timePosition: number) -> (),
	seek: (self: Context<StepT>, request: SeekRequest<StepT>) -> (),

	getPlaybackSpeed: (self: Context<StepT>) -> number,
	setPlaybackSpeed: (self: Context<StepT>, speed: number) -> (),

	getStep: (self: Context<StepT>) -> StepT?,
	canStep: (self: Context<StepT>, step: StepT?, payload: any?) -> (boolean, string?),
	step: (self: Context<StepT>, step: StepT?, payload: any?) -> (boolean, string?),

	getParam: (self: Context<StepT>, name: string) -> any,
	setParam: (self: Context<StepT>, name: string, value: any) -> (),
	signal: (self: Context<StepT>, name: string, payload: any?) -> (),

	addCleanup: (self: Context<StepT>, cleanup: () -> ()) -> (),
	pause: (self: Context<StepT>) -> (),
	resume: (self: Context<StepT>) -> (),
	isPaused: (self: Context<StepT>) -> boolean,
	stop: (self: Context<StepT>, reason: CompletionReason?) -> (),
	cancel: (self: Context<StepT>, reason: CompletionReason?) -> (),
	destroy: (self: Context<StepT>) -> (),
}

export type ContextImpl<StepT = StepId> = Context<StepT> & {
	_playback: any,
}

return {}
