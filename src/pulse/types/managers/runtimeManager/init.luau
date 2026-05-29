--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local PlaybackTypes = require(script.Parent.Parent.components.playback)
local SequenceTypes = require(script.Parent.Parent.components.sequence)

export type StepId = DefTypes.StepId
export type PlayRequest<StepT = StepId> = DefTypes.PlayRequest<StepT>
export type RuntimeOptions<PhaseT> = DefTypes.RuntimeOptions<PhaseT>
export type Sequence<StepT = StepId> = SequenceTypes.Sequence<StepT>
export type Playback<StepT = StepId> = PlaybackTypes.Playback<StepT>
type PlaybackImpl<StepT = StepId> = PlaybackTypes.PlaybackImpl<StepT>

export type Runtime<PhaseT> = {
	play: <StepT>(self: Runtime<PhaseT>, sequence: Sequence<StepT>, request: PlayRequest<StepT>?) -> Playback<StepT>,
	destroy: (self: Runtime<PhaseT>) -> (),
}

export type RuntimeImpl<PhaseT> = Runtime<PhaseT> & {
	_options: RuntimeOptions<PhaseT>,
	_playbacks: { PlaybackImpl<any> },
	_bindingId: number?,
}

return {}
