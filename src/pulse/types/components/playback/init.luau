--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local ContextTypes = require(script.Parent.context)
local SequenceTypes = require(script.Parent.sequence)

export type StepId = DefTypes.StepId
export type Status = DefTypes.Status
export type CompletionReason = DefTypes.CompletionReason
export type Completion = DefTypes.Completion
export type Params = DefTypes.Params
export type Hook<T...> = DefTypes.Hook<T...>
export type PlayRequest<StepT = StepId> = DefTypes.PlayRequest<StepT>
export type SeekRequest<StepT = StepId> = DefTypes.SeekRequest<StepT>
export type Context<StepT = StepId> = ContextTypes.Context<StepT>
export type Sequence<StepT = StepId> = SequenceTypes.Sequence<StepT>
type SequenceImpl<StepT = StepId> = SequenceTypes.SequenceImpl<StepT>

export type Playback<StepT = StepId> = {
	Ended: Hook<Completion>,
	Looped: Hook<number>,
	ParamChanged: Hook<string, any, any?>,
	Signaled: Hook<string, any?>,

	play: (self: Playback<StepT>) -> Playback<StepT>,
	pause: (self: Playback<StepT>) -> (),
	resume: (self: Playback<StepT>) -> (),
	stop: (self: Playback<StepT>, reason: CompletionReason?) -> (),
	cancel: (self: Playback<StepT>, reason: CompletionReason?) -> (),
	destroy: (self: Playback<StepT>) -> (),

	isPlaying: (self: Playback<StepT>) -> boolean,
	isPaused: (self: Playback<StepT>) -> boolean,
	isAlive: (self: Playback<StepT>) -> boolean,
	getStatus: (self: Playback<StepT>) -> Status,

	setParam: (self: Playback<StepT>, name: string, value: any) -> (),
	getParam: (self: Playback<StepT>, name: string) -> any,
	setParams: (self: Playback<StepT>, params: Params) -> (),

	signal: (self: Playback<StepT>, name: string, payload: any?) -> (),

	getStep: (self: Playback<StepT>) -> StepT?,
	canStep: (self: Playback<StepT>, step: StepT?, payload: any?) -> (boolean, string?),
	step: (self: Playback<StepT>, step: StepT?, payload: any?) -> (boolean, string?),

	setPlaybackSpeed: (self: Playback<StepT>, speed: number) -> (),
	getPlaybackSpeed: (self: Playback<StepT>) -> number,

	setTimePosition: (self: Playback<StepT>, timePosition: number) -> (),
	getTimePosition: (self: Playback<StepT>) -> number,
	seek: (self: Playback<StepT>, request: SeekRequest<StepT>) -> (),
}

export type PlaybackImpl<StepT = StepId> = Playback<StepT> & {
	_sequence: SequenceImpl<StepT>,
	_status: Status,
	_step: StepT?,
	_timePosition: number,
	_playbackSpeed: number,
	_nextEventIndex: number,
	_loopCount: number,
	_completion: Completion?,
	_cleanupRemaining: number,
	_cleanupHasRun: boolean,
	_params: Params,
	_cleanups: { () -> () },
	_context: Context<StepT>,
}

return {}
