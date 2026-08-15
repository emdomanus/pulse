--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)

export type StepId = DefTypes.StepId
export type SequenceAddress = DefTypes.SequenceAddress
export type PlaybackPosition = DefTypes.PlaybackPosition
export type Status = DefTypes.Status

export type Context<StepT = StepId> = {
	getPosition: (self: Context<StepT>) -> PlaybackPosition,
	seek: (self: Context<StepT>, address: SequenceAddress) -> boolean,

	getPlaybackSpeed: (self: Context<StepT>) -> number,
	setPlaybackSpeed: (self: Context<StepT>, speed: number) -> (),

	getStep: (self: Context<StepT>) -> StepT?,
	canStep: (self: Context<StepT>, step: StepT?, payload: unknown?) -> (boolean, string?),
	step: (self: Context<StepT>, step: StepT?, payload: unknown?) -> (boolean, string?),

	getParam: (self: Context<StepT>, name: string) -> unknown,
	setParam: (self: Context<StepT>, name: string, value: unknown) -> (),
	signal: (self: Context<StepT>, name: string, payload: unknown?) -> (),
	addCleanup: (self: Context<StepT>, cleanup: () -> ()) -> (),

	pause: (self: Context<StepT>) -> (),
	resume: (self: Context<StepT>) -> (),
	getStatus: (self: Context<StepT>) -> Status,
	stop: (self: Context<StepT>, reason: string?) -> (),
	cancel: (self: Context<StepT>, reason: string?) -> (),
	destroy: (self: Context<StepT>) -> (),
}

export type PlaybackContextPort<StepT = StepId> = {
	getPosition: (self: PlaybackContextPort<StepT>) -> PlaybackPosition,
	seek: (self: PlaybackContextPort<StepT>, address: SequenceAddress) -> boolean,
	getPlaybackSpeed: (self: PlaybackContextPort<StepT>) -> number,
	setPlaybackSpeed: (self: PlaybackContextPort<StepT>, speed: number) -> (),
	getStep: (self: PlaybackContextPort<StepT>) -> StepT?,
	canStep: (self: PlaybackContextPort<StepT>, step: StepT?, payload: unknown?) -> (boolean, string?),
	step: (self: PlaybackContextPort<StepT>, step: StepT?, payload: unknown?) -> (boolean, string?),
	getParam: (self: PlaybackContextPort<StepT>, name: string) -> unknown,
	setParam: (self: PlaybackContextPort<StepT>, name: string, value: unknown) -> (),
	signal: (self: PlaybackContextPort<StepT>, name: string, payload: unknown?) -> (),
	addCleanup: (self: PlaybackContextPort<StepT>, cleanup: () -> ()) -> (),
	pause: (self: PlaybackContextPort<StepT>) -> (),
	resume: (self: PlaybackContextPort<StepT>) -> (),
	getStatus: (self: PlaybackContextPort<StepT>) -> Status,
	stop: (self: PlaybackContextPort<StepT>, reason: string?) -> (),
	cancel: (self: PlaybackContextPort<StepT>, reason: string?) -> (),
	destroy: (self: PlaybackContextPort<StepT>) -> (),
}

export type ContextImpl<StepT = StepId> = Context<StepT> & {
	_playback: PlaybackContextPort<StepT>,
}

return {}
