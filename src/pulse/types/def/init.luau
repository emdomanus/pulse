--!strict
--!optimize 2
--!native

export type Release = () -> ()
export type TraversalDirection = "forward" | "backward"
export type AddressPolicy = "skip" | "rebuild" | "cancel"

export type SequenceAddress = {
	timePosition: number,
	loopIndex: number?,
}

export type PlaybackPosition = {
	timePosition: number,
	loopIndex: number,
	unwrappedTimePosition: number,
}

export type LoopChange = {
	fromLoopIndex: number,
	toLoopIndex: number,
	direction: TraversalDirection,
}

export type ActiveStatus = "idle" | "playing" | "paused"
export type TerminalStatus = "completed" | "cancelled" | "destroyed" | "failed"
export type Status = ActiveStatus | TerminalStatus

export type Completion = {
	status: TerminalStatus,
	reason: string?,
}

export type PlaybackContext = {
	pause: (self: PlaybackContext) -> (),
	resume: (self: PlaybackContext) -> (),
	setPlaybackSpeed: (self: PlaybackContext, speed: number) -> (),
	getPlaybackSpeed: (self: PlaybackContext) -> number,
	seek: (self: PlaybackContext, address: SequenceAddress) -> boolean,
	getPosition: (self: PlaybackContext) -> PlaybackPosition,
	getStatus: (self: PlaybackContext) -> Status,
	addCleanup: (self: PlaybackContext, cleanup: () -> ()) -> (),
	cancel: (self: PlaybackContext, reason: string?) -> (),
	destroy: (self: PlaybackContext) -> (),
}

return {}
