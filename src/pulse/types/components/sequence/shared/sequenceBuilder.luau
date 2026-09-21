--!strict
--!optimize 2

local SequenceTypes = require(script.Parent.sequence)

type Sequence<ContextT> = SequenceTypes.Sequence<ContextT>
type SequenceConstructor<ContextT> = SequenceTypes.SequenceConstructor<ContextT>
type Event<ContextT> = SequenceTypes.Event<ContextT>
type Sample<ContextT> = SequenceTypes.Sample<ContextT>
type EventCallback<ContextT> = SequenceTypes.EventCallback<ContextT>
type AddressCallback<ContextT> = SequenceTypes.AddressCallback<ContextT>
type LoopCallback<ContextT> = SequenceTypes.LoopCallback<ContextT>

export type SequenceBuilder<ContextT> = {
	duration: (self: SequenceBuilder<ContextT>, seconds: number) -> SequenceBuilder<ContextT>,
	loop: (self: SequenceBuilder<ContextT>, enabled: boolean?) -> SequenceBuilder<ContextT>,
	event: (self: SequenceBuilder<ContextT>, event: Event<ContextT>) -> SequenceBuilder<ContextT>,
	sample: (self: SequenceBuilder<ContextT>, sample: Sample<ContextT>) -> SequenceBuilder<ContextT>,
	onPlay: (self: SequenceBuilder<ContextT>, callback: EventCallback<ContextT>) -> SequenceBuilder<ContextT>,
	onAddress: (self: SequenceBuilder<ContextT>, callback: AddressCallback<ContextT>) -> SequenceBuilder<ContextT>,
	onLoop: (self: SequenceBuilder<ContextT>, callback: LoopCallback<ContextT>) -> SequenceBuilder<ContextT>,
	compile: (self: SequenceBuilder<ContextT>) -> Sequence<ContextT>,
}

export type SequenceBuilderImpl<ContextT> = SequenceBuilder<ContextT> & {
	_constructSequence: SequenceConstructor<ContextT>,
	_duration: number?,
	_loop: boolean,
	_events: { Event<ContextT> },
	_samples: { Sample<ContextT> },
	_onPlay: EventCallback<ContextT>?,
	_onAddress: AddressCallback<ContextT>?,
	_onLoop: LoopCallback<ContextT>?,
}

return {}
