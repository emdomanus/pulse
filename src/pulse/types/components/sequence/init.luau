--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)

type AddressInfo = DefTypes.AddressInfo
type LoopChange = DefTypes.LoopChange
type PlaybackControl = DefTypes.PlaybackControl
type SampleInfo = DefTypes.SampleInfo

export type EventCallback<ContextT> = (playback: PlaybackControl, context: ContextT) -> ()
export type AddressCallback<ContextT> = (playback: PlaybackControl, info: AddressInfo, context: ContextT) -> ()
export type SampleCallback<ContextT> = (playback: PlaybackControl, sample: SampleInfo, context: ContextT) -> ()
export type LoopCallback<ContextT> = (playback: PlaybackControl, change: LoopChange, context: ContextT) -> ()

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

export type Sample<ContextT> = {
	startTime: number?,
	endTime: number?,
	run: SampleCallback<ContextT>,
}

export type CompiledSample<ContextT> = {
	startTime: number,
	endTime: number,
	authorIndex: number,
	run: SampleCallback<ContextT>,
}

export type SequenceBoundary = {
	timePosition: number,
	loopIndex: number,
	unwrappedTimePosition: number,
}

export type SequenceDefinition<ContextT> = {
	duration: number,
	loop: boolean?,
	events: { Event<ContextT> }?,
	samples: { Sample<ContextT> }?,
	onPlay: EventCallback<ContextT>?,
	onAddress: AddressCallback<ContextT>?,
	onLoop: LoopCallback<ContextT>?,
}

export type Sequence<ContextT> = {
	-- Invariant type brand. The compiler stores one shared identity function; callers do not invoke it.
	_contextType: (ContextT) -> ContextT,
	getDuration: (self: Sequence<ContextT>) -> number,
	isLooping: (self: Sequence<ContextT>) -> boolean,
}

export type SequenceConstructor<ContextT> = (definition: SequenceDefinition<ContextT>) -> Sequence<ContextT>

export type SequenceState<ContextT> = {
	_contextType: (ContextT) -> ContextT,
	_duration: number,
	_loop: boolean,
	_events: { CompiledEvent<ContextT> },
	_samples: { CompiledSample<ContextT> },
	_boundaries: { number },
	_onPlay: EventCallback<ContextT>?,
	_onAddress: AddressCallback<ContextT>?,
	_onLoop: LoopCallback<ContextT>?,
}

export type SequenceImpl<ContextT> = Sequence<ContextT> & SequenceState<ContextT>

export type Builder<ContextT> = {
	duration: (self: Builder<ContextT>, seconds: number) -> Builder<ContextT>,
	loop: (self: Builder<ContextT>, enabled: boolean?) -> Builder<ContextT>,
	event: (self: Builder<ContextT>, event: Event<ContextT>) -> Builder<ContextT>,
	sample: (self: Builder<ContextT>, sample: Sample<ContextT>) -> Builder<ContextT>,
	onPlay: (self: Builder<ContextT>, callback: EventCallback<ContextT>) -> Builder<ContextT>,
	onAddress: (self: Builder<ContextT>, callback: AddressCallback<ContextT>) -> Builder<ContextT>,
	onLoop: (self: Builder<ContextT>, callback: LoopCallback<ContextT>) -> Builder<ContextT>,
	compile: (self: Builder<ContextT>) -> Sequence<ContextT>,
}

export type BuilderImpl<ContextT> = Builder<ContextT> & {
	_constructSequence: SequenceConstructor<ContextT>,
	_duration: number?,
	_loop: boolean,
	_events: { Event<ContextT> },
	_samples: { Sample<ContextT> },
	_onPlay: EventCallback<ContextT>?,
	_onAddress: AddressCallback<ContextT>?,
	_onLoop: LoopCallback<ContextT>?,
}

export type StoredEvent = CompiledEvent<unknown>
export type StoredSample = CompiledSample<unknown>
export type StoredSequence = Sequence<unknown>
export type StoredSequenceImpl = SequenceImpl<unknown>

return {}
