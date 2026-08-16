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

export type PlaybackControl = {
	pause: (self: PlaybackControl) -> (),
	resume: (self: PlaybackControl) -> (),
	setPlaybackSpeed: (self: PlaybackControl, speed: number) -> (),
	getPlaybackSpeed: (self: PlaybackControl) -> number,
	seek: (self: PlaybackControl, address: SequenceAddress) -> boolean,
	getPosition: (self: PlaybackControl) -> PlaybackPosition,
	getStatus: (self: PlaybackControl) -> Status,
	addCleanup: (self: PlaybackControl, cleanup: () -> ()) -> (),
	cancel: (self: PlaybackControl, reason: string?) -> (),
	destroy: (self: PlaybackControl) -> (),
}

return {}
