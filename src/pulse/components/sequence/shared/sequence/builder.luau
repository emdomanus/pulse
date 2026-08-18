--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Parent.Parent.Parent.Parent.types.components.sequence)

type AddressCallback<ContextT> = Types.AddressCallback<ContextT>
type Builder<ContextT> = Types.Builder<ContextT>
type BuilderImpl<ContextT> = Types.BuilderImpl<ContextT>
type Event<ContextT> = Types.Event<ContextT>
type EventCallback<ContextT> = Types.EventCallback<ContextT>
type LoopCallback<ContextT> = Types.LoopCallback<ContextT>
type Sequence<ContextT> = Types.Sequence<ContextT>
type SequenceConstructor<ContextT> = Types.SequenceConstructor<ContextT>
type Sample<ContextT> = Types.Sample<ContextT>

type BuilderModule = {
	new: <ContextT>(constructSequence: SequenceConstructor<ContextT>) -> Builder<ContextT>,
}

local Builder = {}
Builder.__index = Builder

local function ConstructBuilder<ContextT>(constructSequence: SequenceConstructor<ContextT>): Builder<ContextT>
	local self: BuilderImpl<ContextT> = (
		setmetatable({
			_constructSequence = constructSequence,
			_duration = nil,
			_loop = false,
			_events = {},
			_samples = {},
			_onPlay = nil,
			_onAddress = nil,
			_onLoop = nil,
		}, Builder) :: unknown
	) :: BuilderImpl<ContextT>
	return self
end

function Builder.duration<ContextT>(self: BuilderImpl<ContextT>, seconds: number): Builder<ContextT>
	self._duration = seconds
	return self
end

function Builder.loop<ContextT>(self: BuilderImpl<ContextT>, enabled: boolean?): Builder<ContextT>
	self._loop = if enabled == nil then true else enabled
	return self
end

function Builder.event<ContextT>(self: BuilderImpl<ContextT>, event: Event<ContextT>): Builder<ContextT>
	table.insert(self._events, {
		time = event.time,
		run = event.run,
		reverse = event.reverse,
	})
	return self
end

function Builder.sample<ContextT>(self: BuilderImpl<ContextT>, sample: Sample<ContextT>): Builder<ContextT>
	table.insert(self._samples, {
		startTime = sample.startTime,
		endTime = sample.endTime,
		run = sample.run,
	})
	return self
end

function Builder.onPlay<ContextT>(self: BuilderImpl<ContextT>, callback: EventCallback<ContextT>): Builder<ContextT>
	self._onPlay = callback
	return self
end

function Builder.onAddress<ContextT>(self: BuilderImpl<ContextT>, callback: AddressCallback<ContextT>): Builder<ContextT>
	self._onAddress = callback
	return self
end

function Builder.onLoop<ContextT>(self: BuilderImpl<ContextT>, callback: LoopCallback<ContextT>): Builder<ContextT>
	self._onLoop = callback
	return self
end

function Builder.compile<ContextT>(self: BuilderImpl<ContextT>): Sequence<ContextT>
	local duration = self._duration
	assert(duration ~= nil, "Pulse Builder requires duration before compile")
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

local module: BuilderModule = {
	new = ConstructBuilder,
}

return module
