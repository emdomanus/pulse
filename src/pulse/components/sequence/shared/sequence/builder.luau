--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.def)
local Types = require(script.Parent.Parent.Parent.Parent.Parent.types.components.sequence)

type AddressPolicy = DefTypes.AddressPolicy
type Builder = Types.Builder
type BuilderImpl = Types.BuilderImpl
type Event = Types.Event
type EventCallback = Types.EventCallback
type LoopChange = DefTypes.LoopChange
type PlaybackContext = DefTypes.PlaybackContext
type Sequence = Types.Sequence
type SequenceConstructor = Types.SequenceConstructor
type Update = Types.Update

type BuilderModule = {
	new: (constructSequence: SequenceConstructor) -> Builder,
}

local Builder = {}
Builder.__index = Builder

local function ConstructBuilder(constructSequence: SequenceConstructor): Builder
	local self: BuilderImpl = (
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
	) :: BuilderImpl
	return self
end

function Builder.duration(self: BuilderImpl, seconds: number): Builder
	self._duration = seconds
	return self
end

function Builder.loop(self: BuilderImpl, enabled: boolean?): Builder
	self._loop = if enabled == nil then true else enabled
	return self
end

function Builder.addressPolicy(self: BuilderImpl, policy: AddressPolicy): Builder
	self._addressPolicy = policy
	return self
end

function Builder.event(self: BuilderImpl, event: Event): Builder
	table.insert(self._events, {
		time = event.time,
		run = event.run,
		reverse = event.reverse,
	})
	return self
end

function Builder.update(self: BuilderImpl, update: Update): Builder
	table.insert(self._updates, {
		startTime = update.startTime,
		endTime = update.endTime,
		run = update.run,
	})
	return self
end

function Builder.onPlay(self: BuilderImpl, callback: EventCallback): Builder
	self._onPlay = callback
	return self
end

function Builder.onLoop(self: BuilderImpl, callback: (PlaybackContext, LoopChange) -> ()): Builder
	self._onLoop = callback
	return self
end

function Builder.compile(self: BuilderImpl): Sequence
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
