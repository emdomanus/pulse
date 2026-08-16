--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.def)
local Types = require(script.Parent.Parent.Parent.Parent.Parent.types.components.sequence)

type AddressPolicy = DefTypes.AddressPolicy
type Builder<ContextT> = Types.Builder<ContextT>
type BuilderImpl<ContextT> = Types.BuilderImpl<ContextT>
type Event<ContextT> = Types.Event<ContextT>
type EventCallback<ContextT> = Types.EventCallback<ContextT>
type LoopCallback<ContextT> = Types.LoopCallback<ContextT>
type Sequence<ContextT> = Types.Sequence<ContextT>
type SequenceConstructor<ContextT> = Types.SequenceConstructor<ContextT>
type Update<ContextT> = Types.Update<ContextT>

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
			_addressPolicy = "skip" :: AddressPolicy,
			_events = {},
			_updates = {},
			_onPlay = nil,
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

function Builder.addressPolicy<ContextT>(self: BuilderImpl<ContextT>, policy: AddressPolicy): Builder<ContextT>
	self._addressPolicy = policy
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

function Builder.update<ContextT>(self: BuilderImpl<ContextT>, update: Update<ContextT>): Builder<ContextT>
	table.insert(self._updates, {
		startTime = update.startTime,
		endTime = update.endTime,
		run = update.run,
	})
	return self
end

function Builder.onPlay<ContextT>(self: BuilderImpl<ContextT>, callback: EventCallback<ContextT>): Builder<ContextT>
	self._onPlay = callback
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
		addressPolicy = self._addressPolicy,
		events = self._events,
		updates = self._updates,
		onPlay = self._onPlay,
		onLoop = self._onLoop,
	})
end

local module: BuilderModule = {
	new = ConstructBuilder,
}

return module
