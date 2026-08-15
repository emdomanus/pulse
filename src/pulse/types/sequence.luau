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

export type EventCallback = (playback: PlaybackContext) -> ()
export type UpdateCallback = (playback: PlaybackContext, dt: number, timePosition: number) -> ()

export type Event = {
	time: number,
	run: EventCallback,
	reverse: EventCallback?,
}

export type Update = {
	startTime: number?,
	endTime: number?,
	run: UpdateCallback,
}

export type SequenceDefinition = {
	duration: number,
	loop: boolean?,
	addressPolicy: AddressPolicy?,
	events: { Event }?,
	updates: { Update }?,
	onPlay: EventCallback?,
	onLoop: ((playback: PlaybackContext, change: LoopChange) -> ())?,
}

export type Sequence = {
	getDuration: (self: Sequence) -> number,
	isLooping: (self: Sequence) -> boolean,
	getAddressPolicy: (self: Sequence) -> AddressPolicy,
}

export type Builder = {
	duration: (self: Builder, seconds: number) -> Builder,
	loop: (self: Builder, enabled: boolean?) -> Builder,
	addressPolicy: (self: Builder, policy: AddressPolicy) -> Builder,
	event: (self: Builder, event: Event) -> Builder,
	update: (self: Builder, update: Update) -> Builder,
	onPlay: (self: Builder, callback: EventCallback) -> Builder,
	onLoop: (self: Builder, callback: (playback: PlaybackContext, change: LoopChange) -> ()) -> Builder,
	compile: (self: Builder) -> Sequence,
}

export type CompiledEvent = {
	time: number,
	authorIndex: number,
	run: EventCallback,
	reverse: EventCallback?,
}

export type CompiledUpdate = {
	startTime: number,
	endTime: number,
	authorIndex: number,
	run: UpdateCallback,
}

export type SequenceImpl = Sequence & {
	_duration: number,
	_loop: boolean,
	_addressPolicy: AddressPolicy,
	_events: { CompiledEvent },
	_updates: { CompiledUpdate },
	_boundaries: { number },
	_onPlay: EventCallback?,
	_onLoop: ((playback: PlaybackContext, change: LoopChange) -> ())?,
}

export type BuilderImpl = Builder & {
	_duration: number?,
	_loop: boolean,
	_addressPolicy: AddressPolicy,
	_events: { Event },
	_updates: { Update },
	_onPlay: EventCallback?,
	_onLoop: ((playback: PlaybackContext, change: LoopChange) -> ())?,
}

return {}
