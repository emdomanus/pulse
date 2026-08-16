--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)

type AddressPolicy = DefTypes.AddressPolicy
type LoopChange = DefTypes.LoopChange
type PlaybackContext = DefTypes.PlaybackContext
type TraversalDirection = DefTypes.TraversalDirection

export type EventCallback<ContextT> = (playback: PlaybackContext, context: ContextT) -> ()
export type UpdateCallback<ContextT> = (
	playback: PlaybackContext,
	dt: number,
	timePosition: number,
	context: ContextT
) -> ()
export type LoopCallback<ContextT> = (playback: PlaybackContext, change: LoopChange, context: ContextT) -> ()

export type Event<ContextT> = {
	time: number,
	run: EventCallback<ContextT>,
	reverse: EventCallback<ContextT>?,
}

export type CompiledEvent<ContextT> = {
	time: number,
	authorIndex: number,
	run: EventCallback<ContextT>,
	reverse: EventCallback<ContextT>?,
}

export type Update<ContextT> = {
	startTime: number?,
	endTime: number?,
	run: UpdateCallback<ContextT>,
}

export type CompiledUpdate<ContextT> = {
	startTime: number,
	endTime: number,
	authorIndex: number,
	run: UpdateCallback<ContextT>,
}

export type SequenceBoundary = {
	timePosition: number,
	loopIndex: number,
	unwrappedTimePosition: number,
}

export type SequenceDefinition<ContextT> = {
	duration: number,
	loop: boolean?,
	addressPolicy: AddressPolicy?,
	events: { Event<ContextT> }?,
	updates: { Update<ContextT> }?,
	onPlay: EventCallback<ContextT>?,
	onLoop: LoopCallback<ContextT>?,
}

export type Sequence<ContextT> = {
	-- Invariant type brand. The compiler stores one shared identity function; callers do not invoke it.
	_contextType: (ContextT) -> ContextT,
	getDuration: (self: Sequence<ContextT>) -> number,
	isLooping: (self: Sequence<ContextT>) -> boolean,
	getAddressPolicy: (self: Sequence<ContextT>) -> AddressPolicy,
}

export type SequenceConstructor<ContextT> = (definition: SequenceDefinition<ContextT>) -> Sequence<ContextT>

export type SequenceState<ContextT> = {
	_contextType: (ContextT) -> ContextT,
	_duration: number,
	_loop: boolean,
	_addressPolicy: AddressPolicy,
	_events: { CompiledEvent<ContextT> },
	_updates: { CompiledUpdate<ContextT> },
	_boundaries: { number },
	_onPlay: EventCallback<ContextT>?,
	_onLoop: LoopCallback<ContextT>?,
}

export type SequenceImpl<ContextT> = Sequence<ContextT> & SequenceState<ContextT>

export type Builder<ContextT> = {
	duration: (self: Builder<ContextT>, seconds: number) -> Builder<ContextT>,
	loop: (self: Builder<ContextT>, enabled: boolean?) -> Builder<ContextT>,
	addressPolicy: (self: Builder<ContextT>, policy: AddressPolicy) -> Builder<ContextT>,
	event: (self: Builder<ContextT>, event: Event<ContextT>) -> Builder<ContextT>,
	update: (self: Builder<ContextT>, update: Update<ContextT>) -> Builder<ContextT>,
	onPlay: (self: Builder<ContextT>, callback: EventCallback<ContextT>) -> Builder<ContextT>,
	onLoop: (self: Builder<ContextT>, callback: LoopCallback<ContextT>) -> Builder<ContextT>,
	compile: (self: Builder<ContextT>) -> Sequence<ContextT>,
}

export type BuilderImpl<ContextT> = Builder<ContextT> & {
	_constructSequence: SequenceConstructor<ContextT>,
	_duration: number?,
	_loop: boolean,
	_addressPolicy: AddressPolicy,
	_events: { Event<ContextT> },
	_updates: { Update<ContextT> },
	_onPlay: EventCallback<ContextT>?,
	_onLoop: LoopCallback<ContextT>?,
}

export type StoredEvent = CompiledEvent<unknown>
export type StoredUpdate = CompiledUpdate<unknown>
export type StoredSequence = Sequence<unknown>
export type StoredSequenceImpl = SequenceImpl<unknown>

return {}
