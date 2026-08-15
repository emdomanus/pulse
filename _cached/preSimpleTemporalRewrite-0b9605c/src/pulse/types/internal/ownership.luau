--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)

export type PlaybackOwned = {
	_terminate: (self: PlaybackOwned, status: DefTypes.TerminalStatus, reason: string?, err: unknown?) -> (),
	_reconcileClockChange: (self: PlaybackOwned, change: DefTypes.ClockChange) -> (),
	_runContinuous: (self: PlaybackOwned, now: number) -> (),
	_dispose: (self: PlaybackOwned) -> (),
}

export type RuntimeOwner = {
	_registerPlayback: (self: RuntimeOwner, playback: PlaybackOwned) -> (),
	_activatePlayback: <PhaseT, DirectionT>(
		self: RuntimeOwner,
		playback: PlaybackOwned,
		clock: DefTypes.Clock<PhaseT, DirectionT>
	) -> boolean,
	_setPlaybackUpdating: <PhaseT, DirectionT>(
		self: RuntimeOwner,
		playback: PlaybackOwned,
		updating: boolean,
		clock: DefTypes.Clock<PhaseT, DirectionT>,
		phase: PhaseT
	) -> (),
	_detachPlayback: (self: RuntimeOwner, playback: PlaybackOwned) -> (),
	_isDestroyed: (self: RuntimeOwner) -> boolean,
}

return {}
