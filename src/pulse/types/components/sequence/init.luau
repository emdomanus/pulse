--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)

type AddressPolicy = DefTypes.AddressPolicy
type LoopChange = DefTypes.LoopChange
type PlaybackContext = DefTypes.PlaybackContext
type TraversalDirection = DefTypes.TraversalDirection

export type EventCallback = (playback: PlaybackContext) -> ()
export type UpdateCallback = (playback: PlaybackContext, dt: number, timePosition: number) -> ()

export type Event = {
	time: number,
	run: EventCallback,
	reverse: EventCallback?,
}

export type CompiledEvent = {
	time: number,
	authorIndex: number,
	run: EventCallback,
	reverse: EventCallback?,
}

export type Update = {
	startTime: number?,
	endTime: number?,
	run: UpdateCallback,
}

export type CompiledUpdate = {
	startTime: number,
	endTime: number,
	authorIndex: number,
	run: UpdateCallback,
}

export type SequenceBoundary = {
	timePosition: number,
	loopIndex: number,
	unwrappedTimePosition: number,
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
