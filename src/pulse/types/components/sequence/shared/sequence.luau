--!strict
--!optimize 2

local PlaybackControlTypes =
	require(script.Parent.Parent.Parent.Parent.ports.components.playback.shared.playbackControl)
local PlaybackDefinitions = require(script.Parent.Parent.Parent.Parent.def.playback.shared.playbackDefinitions)

local PlaybackVocabulary = require(script.Parent.Parent.Parent.Parent.Parent.common.playback.shared.playbackVocabulary)

type SequenceAddress = PlaybackDefinitions.SequenceAddress
type TraversalDirection = PlaybackVocabulary.TraversalDirection
type AddressInfo = PlaybackDefinitions.AddressInfo
type LoopChange = PlaybackDefinitions.LoopChange
type PlaybackControl = PlaybackControlTypes.PlaybackControl

export type EventCallback<ContextT> = (playback: PlaybackControl, context: ContextT) -> ()
export type AddressCallback<ContextT> = (playback: PlaybackControl, info: AddressInfo, context: ContextT) -> ()
export type SampleCallback<ContextT> = (
	playback: PlaybackControl,
	timePosition: number,
	unwrappedTimePosition: number,
	rate: number,
	context: ContextT
) -> ()
export type LoopCallback<ContextT> = (playback: PlaybackControl, change: LoopChange, context: ContextT) -> ()

export type Event<ContextT> = {
	time: number,
	run: EventCallback<ContextT>,
	reverse: EventCallback<ContextT>?,
}

export type CompiledEvent<ContextT> = {
	read time: number,
	read authorIndex: number,
	read run: EventCallback<ContextT>,
	read reverse: EventCallback<ContextT>?,
}

export type Sample<ContextT> = {
	startTime: number?,
	endTime: number?,
	run: SampleCallback<ContextT>,
}

export type CompiledSample<ContextT> = {
	read startTime: number,
	read endTime: number,
	read authorIndex: number,
	read run: SampleCallback<ContextT>,
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
	read _contextType: (ContextT) -> ContextT,
	read getDuration: (self: Sequence<ContextT>) -> number,
	read isLooping: (self: Sequence<ContextT>) -> boolean,
}

export type SequenceConstructor<ContextT> = (definition: SequenceDefinition<ContextT>) -> Sequence<ContextT>

export type SequenceState<ContextT> = {
	read _contextType: (ContextT) -> ContextT,
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
	read validateAddress: (self: SequenceStored<ContextT>, address: SequenceAddress) -> number,
	read positionAt: (self: SequenceStored<ContextT>, unwrappedTimePosition: number) -> number,
	read positionComponents: (self: SequenceStored<ContextT>, unwrappedTimePosition: number) -> (number, number),
	read nextBoundary: (
		self: SequenceStored<ContextT>,
		position: number,
		direction: TraversalDirection
	) -> (number?, number?),
	read boundaryAt: (self: SequenceStored<ContextT>, position: number) -> number?,

	read eventRangeAt: (self: SequenceStored<ContextT>, localTimePosition: number) -> (number, number),
	read getEvent: (self: SequenceStored<ContextT>, index: number) -> CompiledEvent<ContextT>,
	read getSamples: (self: SequenceStored<ContextT>) -> { CompiledSample<ContextT> },
	read getOnPlay: (self: SequenceStored<ContextT>) -> EventCallback<ContextT>?,
	read getOnAddress: (self: SequenceStored<ContextT>) -> AddressCallback<ContextT>?,
	read getOnLoop: (self: SequenceStored<ContextT>) -> LoopCallback<ContextT>?,
}

export type SequenceImpl<ContextT> = SequenceStored<ContextT> & SequenceState<ContextT>

export type StoredEvent = CompiledEvent<unknown>
export type StoredSample = CompiledSample<unknown>
export type StoredSequence = SequenceStored<unknown>
export type StoredSequenceImpl = SequenceImpl<unknown>

return {}
