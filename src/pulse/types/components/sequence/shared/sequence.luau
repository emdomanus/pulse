--!strict
--!optimize 2

local PlaybackControlTypes =
	require(script.Parent.Parent.Parent.Parent.ports.components.playback.shared.playbackControl)
local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.def.playback.shared.playbackDefinitions)

local PlaybackVocabulary = require(script.Parent.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)

type PlaybackPosition = PlaybackDefinitions.PlaybackPosition
type SequenceAddress = PlaybackDefinitions.SequenceAddress
type TraversalDirection = PlaybackVocabulary.TraversalDirection
type AddressInfo = PlaybackDefinitions.AddressInfo
type LoopChange = PlaybackDefinitions.LoopChange
type PlaybackControl = PlaybackControlTypes.PlaybackControl
type SampleInfo = PlaybackDefinitions.SampleInfo

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

-- Complete compiled view retained by Playback; the package facade exposes only Sequence.
export type SequenceStored<ContextT> = Sequence<ContextT> & {
	validateAddress: (self: SequenceStored<ContextT>, address: SequenceAddress) -> PlaybackPosition,
	positionAt: (self: SequenceStored<ContextT>, unwrappedTimePosition: number) -> PlaybackPosition,
	nextBoundary: (
		self: SequenceStored<ContextT>,
		position: PlaybackPosition,
		direction: TraversalDirection
	) -> SequenceBoundary?,
	nextBoundaryInto: (
		self: SequenceStored<ContextT>,
		position: PlaybackPosition,
		direction: TraversalDirection,
		output: SequenceBoundary
	) -> boolean,
	boundaryAt: (self: SequenceStored<ContextT>, position: PlaybackPosition) -> SequenceBoundary?,
	eventRangeAt: (self: SequenceStored<ContextT>, localTimePosition: number) -> (number, number),
	getEvent: (self: SequenceStored<ContextT>, index: number) -> CompiledEvent<ContextT>,
	getSamples: (self: SequenceStored<ContextT>) -> { CompiledSample<ContextT> },
	getOnPlay: (self: SequenceStored<ContextT>) -> EventCallback<ContextT>?,
	getOnAddress: (self: SequenceStored<ContextT>) -> AddressCallback<ContextT>?,
	getOnLoop: (self: SequenceStored<ContextT>) -> LoopCallback<ContextT>?,
}

export type SequenceImpl<ContextT> = SequenceStored<ContextT> & SequenceState<ContextT>

export type StoredEvent = CompiledEvent<unknown>
export type StoredSample = CompiledSample<unknown>
export type StoredSequence = SequenceStored<unknown>
export type StoredSequenceImpl = SequenceImpl<unknown>

return {}
