--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.def)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.components.playback)
local TemporalAdapterTypes = require(script.Parent.Parent.Parent.Parent.Parent.types.managers.temporalAdapter)
local TemporalAdapter =
	require(script.Parent.Parent.Parent.Parent.Parent.managers.temporalAdapter.shared.temporalAdapter)

type Completion = DefTypes.Completion
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
}

local MAX_RECONCILIATION_WORK = 4_096

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

local module: LifecycleModule = {
	cancelScheduled = cancelScheduled,
	stopUpdating = stopUpdating,
	detach = detach,
	disposeGeneration = disposeGeneration,
	finish = finish,
	requestTerminal = requestTerminal,
}

return module
