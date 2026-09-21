--!strict
--!optimize 2

local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence.shared.sequence)
local SequenceBuilderTypes =
	require(script.Parent.Parent.Parent.Parent.types.components.sequence.shared.sequenceBuilder)

type AddressCallback<ContextT> = SequenceTypes.AddressCallback<ContextT>
type SequenceBuilder<ContextT> = SequenceBuilderTypes.SequenceBuilder<ContextT>
type SequenceBuilderImpl<ContextT> = SequenceBuilderTypes.SequenceBuilderImpl<ContextT>
type Event<ContextT> = SequenceTypes.Event<ContextT>
type EventCallback<ContextT> = SequenceTypes.EventCallback<ContextT>
type LoopCallback<ContextT> = SequenceTypes.LoopCallback<ContextT>
type Sequence<ContextT> = SequenceTypes.Sequence<ContextT>
type SequenceConstructor<ContextT> = SequenceTypes.SequenceConstructor<ContextT>
type Sample<ContextT> = SequenceTypes.Sample<ContextT>

type SequenceBuilderModule = {
	new: <ContextT>(constructSequence: SequenceConstructor<ContextT>) -> SequenceBuilder<ContextT>,
}

local SequenceBuilder = {}
SequenceBuilder.__index = SequenceBuilder

local function ConstructBuilder<ContextT>(constructSequence: SequenceConstructor<ContextT>): SequenceBuilder<ContextT>
	local self: SequenceBuilderImpl<ContextT> = (
		setmetatable({
			_constructSequence = constructSequence,
			_duration = nil,
			_loop = false,
			_events = {},
			_samples = {},
			_onPlay = nil,
			_onAddress = nil,
			_onLoop = nil,
		}, SequenceBuilder) :: unknown
	) :: SequenceBuilderImpl<ContextT>
	return self
end

function SequenceBuilder.duration<ContextT>(self: SequenceBuilderImpl<ContextT>, seconds: number): SequenceBuilder<ContextT>
	self._duration = seconds
	return self
end

function SequenceBuilder.loop<ContextT>(self: SequenceBuilderImpl<ContextT>, enabled: boolean?): SequenceBuilder<ContextT>
	self._loop = if enabled == nil then true else enabled
	return self
end

function SequenceBuilder.event<ContextT>(self: SequenceBuilderImpl<ContextT>, event: Event<ContextT>): SequenceBuilder<ContextT>
	table.insert(self._events, {
		time = event.time,
		run = event.run,
		reverse = event.reverse,
	})
	return self
end

function SequenceBuilder.sample<ContextT>(
	self: SequenceBuilderImpl<ContextT>,
	sample: Sample<ContextT>
): SequenceBuilder<ContextT>
	table.insert(self._samples, {
		startTime = sample.startTime,
		endTime = sample.endTime,
		run = sample.run,
	})
	return self
end

function SequenceBuilder.onPlay<ContextT>(
	self: SequenceBuilderImpl<ContextT>,
	callback: EventCallback<ContextT>
): SequenceBuilder<ContextT>
	self._onPlay = callback
	return self
end

function SequenceBuilder.onAddress<ContextT>(
	self: SequenceBuilderImpl<ContextT>,
	callback: AddressCallback<ContextT>
): SequenceBuilder<ContextT>
	self._onAddress = callback
	return self
end

function SequenceBuilder.onLoop<ContextT>(
	self: SequenceBuilderImpl<ContextT>,
	callback: LoopCallback<ContextT>
): SequenceBuilder<ContextT>
	self._onLoop = callback
	return self
end

function SequenceBuilder.compile<ContextT>(self: SequenceBuilderImpl<ContextT>): Sequence<ContextT>
	local duration = self._duration
	assert(duration ~= nil, "Pulse SequenceBuilder requires duration before compile")
	return self._constructSequence({
		duration = duration,
		loop = self._loop,
		events = self._events,
		samples = self._samples,
		onPlay = self._onPlay,
		onAddress = self._onAddress,
		onLoop = self._onLoop,
	})
end

local module: SequenceBuilderModule = {
	new = ConstructBuilder,
}

return module
