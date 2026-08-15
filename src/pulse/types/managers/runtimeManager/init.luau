--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local PlaybackTypes = require(script.Parent.Parent.components.playback)
local SequenceTypes = require(script.Parent.Parent.components.sequence)

export type StepId = DefTypes.StepId
export type Clock<PhaseT, DirectionT> = DefTypes.Clock<PhaseT, DirectionT>
export type ClockDirections<DirectionT> = DefTypes.ClockDirections<DirectionT>
export type ClockChange = DefTypes.ClockChange
export type ClockChangedCallback = DefTypes.ClockChangedCallback
export type PhaseCallback = DefTypes.PhaseCallback
export type Release = DefTypes.Release
export type RuntimeConfig = DefTypes.RuntimeConfig
export type Params = DefTypes.Params
export type SequenceAddress = DefTypes.SequenceAddress
export type TerminalStatus = DefTypes.TerminalStatus
export type Sequence<StepT = StepId> = SequenceTypes.Sequence<StepT>
export type Playback<StepT = StepId> = PlaybackTypes.Playback<StepT>

export type PlaybackOptions<StepT, PhaseT, DirectionT> = {
	clock: Clock<PhaseT, DirectionT>,
	directions: ClockDirections<DirectionT>,
	phase: PhaseT,
	params: Params?,
	playbackSpeed: number?,
	position: SequenceAddress?,
	step: StepT?,
}

export type Runtime = {
	createPlayback: <StepT, PhaseT, DirectionT>(
		self: Runtime,
		sequence: Sequence<StepT>,
		options: PlaybackOptions<StepT, PhaseT, DirectionT>
	) -> Playback<StepT>,
	destroy: (self: Runtime) -> (),
}

export type PlaybackOwned = {
	terminate: (status: TerminalStatus, reason: string?) -> (),
	reconcileClockChange: (change: ClockChange) -> (),
	runContinuous: (now: number) -> (),
	dispose: () -> (),
}

export type ClockStatePort = {
	sameClock: (candidate: unknown) -> boolean,
	bindChanged: (callback: ClockChangedCallback) -> Release,
	isDestroyed: () -> boolean,
}

export type PhaseGroupPort = {
	samePhase: (candidate: unknown) -> boolean,
	bind: (callback: PhaseCallback) -> Release,
}

export type PhaseGroupOwned = {
	port: PhaseGroupPort,
	members: { PlaybackOwned },
	updatingMembers: { PlaybackOwned },
	releaseContinuous: Release?,
}

export type ClockStateOwned = {
	port: ClockStatePort,
	playbacks: { PlaybackOwned },
	groups: { PhaseGroupOwned },
	releaseChanged: Release?,
}

export type RuntimeImpl = Runtime & {
	_config: RuntimeConfig,
	_destroyed: boolean,
	_playbacks: { PlaybackOwned },
	_clockStates: { ClockStateOwned },
}

return {}
