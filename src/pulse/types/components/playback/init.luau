--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local ContextTypes = require(script.Parent.context)
local SequenceTypes = require(script.Parent.sequence)

export type StepId = DefTypes.StepId
export type Release = DefTypes.Release
export type Status = DefTypes.Status
export type Completion = DefTypes.Completion
export type Params = DefTypes.Params
export type SequenceAddress = DefTypes.SequenceAddress
export type PlaybackPosition = DefTypes.PlaybackPosition
export type LoopChange = DefTypes.LoopChange
export type Context<StepT = StepId> = ContextTypes.Context<StepT>
export type Sequence<StepT = StepId> = SequenceTypes.Sequence<StepT>
type SequenceImpl<StepT = StepId> = SequenceTypes.SequenceImpl<StepT>

export type EndedCallback = (completion: Completion) -> ()
export type LoopedCallback = (change: LoopChange) -> ()
export type ParamChangedCallback = (name: string, value: unknown, oldValue: unknown?) -> ()
export type SignaledCallback = (name: string, payload: unknown?) -> ()

export type Playback<StepT = StepId> = {
	play: (self: Playback<StepT>) -> Playback<StepT>,
	pause: (self: Playback<StepT>) -> (),
	resume: (self: Playback<StepT>) -> (),
	stop: (self: Playback<StepT>, reason: string?) -> (),
	cancel: (self: Playback<StepT>, reason: string?) -> (),
	destroy: (self: Playback<StepT>) -> (),

	onEnded: (self: Playback<StepT>, callback: EndedCallback) -> Release,
	onLooped: (self: Playback<StepT>, callback: LoopedCallback) -> Release,
	onParamChanged: (self: Playback<StepT>, callback: ParamChangedCallback) -> Release,
	onSignaled: (self: Playback<StepT>, callback: SignaledCallback) -> Release,

	isAlive: (self: Playback<StepT>) -> boolean,
	getStatus: (self: Playback<StepT>) -> Status,
	getCompletion: (self: Playback<StepT>) -> Completion?,

	setParam: (self: Playback<StepT>, name: string, value: unknown) -> (),
	getParam: (self: Playback<StepT>, name: string) -> unknown,
	setParams: (self: Playback<StepT>, params: Params) -> (),
	signal: (self: Playback<StepT>, name: string, payload: unknown?) -> (),

	getStep: (self: Playback<StepT>) -> StepT?,
	canStep: (self: Playback<StepT>, step: StepT?, payload: unknown?) -> (boolean, string?),
	step: (self: Playback<StepT>, step: StepT?, payload: unknown?) -> (boolean, string?),

	setPlaybackSpeed: (self: Playback<StepT>, speed: number) -> (),
	getPlaybackSpeed: (self: Playback<StepT>) -> number,
	seek: (self: Playback<StepT>, address: SequenceAddress) -> boolean,
	getPosition: (self: Playback<StepT>) -> PlaybackPosition,
}

export type PlaybackImpl<StepT = StepId> = Playback<StepT> & {
	_sequence: SequenceImpl<StepT>,
	_context: Context<StepT>,
	_status: Status,
	_completion: Completion?,
}

return {}
