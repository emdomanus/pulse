--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.def)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.components.playback)
local TemporalAdapterTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.managers.temporalAdapter)
local TemporalAdapter =
	require(script.Parent.Parent.Parent.Parent.Parent.managers.temporalAdapter.shared.temporalAdapter)

type Completion = DefTypes.Completion
type EndedBinding = PlaybackTypes.EndedBinding
type EndedCallback = PlaybackTypes.EndedCallback
type LoopedBinding = PlaybackTypes.LoopedBinding
type LoopedCallback = PlaybackTypes.LoopedCallback
type Playback = PlaybackTypes.Playback
type PlaybackImpl = PlaybackTypes.PlaybackImpl
type PlaybackSink = TemporalAdapterTypes.PlaybackSink
type TerminalStatus = DefTypes.TerminalStatus

type LifecycleModule = {
	cancelScheduled: (self: PlaybackImpl) -> (),
	stopUpdating: (self: PlaybackImpl) -> (),
	detach: (self: PlaybackImpl) -> (),
	disposeGeneration: (self: PlaybackImpl) -> boolean,
	finish: (self: PlaybackImpl, status: TerminalStatus, reason: string?) -> (),
	requestTerminal: (self: PlaybackImpl, status: TerminalStatus, reason: string?) -> (),
	addCleanup: (self: PlaybackImpl, cleanup: () -> ()) -> (),
	cancel: (self: PlaybackImpl, reason: string?) -> (),
	destroy: (self: PlaybackImpl) -> (),
	onEnded: (self: PlaybackImpl, callback: EndedCallback) -> () -> (),
	onLooped: (self: PlaybackImpl, callback: LoopedCallback) -> () -> (),
	isAlive: (self: PlaybackImpl) -> boolean,
	getCompletion: (self: PlaybackImpl) -> Completion?,
}

local MAX_RECONCILIATION_WORK = 4_096

local function noopRelease() end

local function asPlaybackSink(self: PlaybackImpl): PlaybackSink
	return self
end

local function cancelScheduled(self: PlaybackImpl)
	local id = self._scheduledId
	self._scheduledId = nil
	self._scheduledDirection = nil
	self._scheduledBoundary = nil
	if id ~= nil then
		TemporalAdapter._cancel(self._adapter, id)
	end
end

local function stopUpdating(self: PlaybackImpl)
	if self._updating then
		self._updating = false
		TemporalAdapter._setUpdating(self._adapter, asPlaybackSink(self), false)
	end
end

local function detach(self: PlaybackImpl)
	stopUpdating(self)
	if self._attached then
		self._attached = false
		TemporalAdapter._detach(self._adapter, asPlaybackSink(self))
	end
end

local function disposeGeneration(self: PlaybackImpl): boolean
	local pending = self._cleanup
	self._cleanup = {}
	local succeeded = true
	local workCount = 0
	while #pending > 0 do
		workCount += 1
		if workCount > MAX_RECONCILIATION_WORK then
			self._cleanup = {}
			return false
		end
		local cleanup = table.remove(pending)
		assert(cleanup ~= nil, "Pulse cleanup stack invariant failed")
		if not pcall(cleanup) then
			succeeded = false
		end
		for _, nested in self._cleanup do
			table.insert(pending, nested)
		end
		self._cleanup = {}
	end
	return succeeded
end

local function emitEnded(self: PlaybackImpl, completion: Completion)
	local bindings = table.clone(self._endedBindings)
	self._endedBindings = {}
	self._loopedBindings = {}
	self._deliveringEnded = true
	for _, binding in bindings do
		local callback = binding.callback
		if binding.active and callback ~= nil then
			pcall(callback, completion)
		end
	end
	self._deliveringEnded = false
end

local function finish(self: PlaybackImpl, status: TerminalStatus, reason: string?)
	if self._completion ~= nil or self._finishing then
		return
	end
	self._finishing = true
	cancelScheduled(self)
	detach(self)
	if not disposeGeneration(self) and status ~= "failed" then
		status = "failed"
		reason = "cleanupFailed"
	end
	self._context = nil
	local completion: Completion = table.freeze({
		status = status,
		reason = reason,
	})
	self._completion = completion
	self._status = status
	self._operations = {}
	self._finishing = false
	emitEnded(self, completion)
end

local function requestTerminal(self: PlaybackImpl, status: TerminalStatus, reason: string?)
	if self._completion ~= nil or self._terminalRequest ~= nil or self._finishing then
		return
	end
	if self._busy then
		self._terminalRequest = {
			status = status,
			reason = reason,
		}
		self._operations = {}
		return
	end
	finish(self, status, reason)
end

local function addCleanup(self: PlaybackImpl, cleanup: () -> ())
	assert(type(cleanup) == "function", "Pulse cleanup must be a callback")
	if self._completion ~= nil then
		if self._finishing then
			return
		end
		self._finishing = true
		pcall(cleanup)
		self._finishing = false
		return
	end
	table.insert(self._cleanup, cleanup)
end

local function cancel(self: PlaybackImpl, reason: string?)
	requestTerminal(self, "cancelled", reason)
end

local function destroy(self: PlaybackImpl)
	if self._completion ~= nil then
		self._endedBindings = {}
		self._loopedBindings = {}
		return
	end
	requestTerminal(self, "destroyed", nil)
end

local function onEnded(self: PlaybackImpl, callback: EndedCallback): () -> ()
	local completion = self._completion
	if completion ~= nil then
		if self._deliveringEnded then
			return noopRelease
		end
		self._deliveringEnded = true
		pcall(callback, completion)
		self._deliveringEnded = false
		return noopRelease
	end
	local binding: EndedBinding = {
		callback = callback,
		active = true,
	}
	table.insert(self._endedBindings, binding)
	return function()
		if not binding.active then
			return
		end
		binding.active = false
		binding.callback = nil
		for index, candidate in self._endedBindings do
			if candidate == binding then
				table.remove(self._endedBindings, index)
				break
			end
		end
	end
end

local function onLooped(self: PlaybackImpl, callback: LoopedCallback): () -> ()
	if self._completion ~= nil or self._finishing then
		return noopRelease
	end
	local binding: LoopedBinding = {
		callback = callback,
		active = true,
	}
	table.insert(self._loopedBindings, binding)
	return function()
		if not binding.active then
			return
		end
		binding.active = false
		binding.callback = nil
		for index, candidate in self._loopedBindings do
			if candidate == binding then
				table.remove(self._loopedBindings, index)
				break
			end
		end
	end
end

local function isAlive(self: PlaybackImpl): boolean
	return self._completion == nil
end

local function getCompletion(self: PlaybackImpl): Completion?
	return self._completion
end

local module: LifecycleModule = {
	cancelScheduled = cancelScheduled,
	stopUpdating = stopUpdating,
	detach = detach,
	disposeGeneration = disposeGeneration,
	finish = finish,
	requestTerminal = requestTerminal,
	addCleanup = addCleanup,
	cancel = cancel,
	destroy = destroy,
	onEnded = onEnded,
	onLooped = onLooped,
	isAlive = isAlive,
	getCompletion = getCompletion,
}

return module
