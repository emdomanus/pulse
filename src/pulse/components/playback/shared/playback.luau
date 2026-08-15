--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local ContextComponent = require(script.Parent.Parent.Parent.context.shared.context)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback)
local PlaybackInternalTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback.internal)
local OwnershipTypes = require(script.Parent.Parent.Parent.Parent.types.internal.ownership)
local RuntimeTypes = require(script.Parent.Parent.Parent.Parent.types.managers.runtimeManager)
local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence)
local SequenceComponent = require(script.Parent.Parent.Parent.sequence.shared.sequence)
local Reconciliation = require(script.Parent.reconciliation)
local Scheduling = require(script.Parent.scheduling)
local Timeline = require(script.Parent.timeline)

type ClockChange = DefTypes.ClockChange
type Status = DefTypes.Status
type TerminalStatus = DefTypes.TerminalStatus
type Completion = DefTypes.Completion
type Params = DefTypes.Params
type TraversalDirection = DefTypes.TraversalDirection
type SequenceAddress = DefTypes.SequenceAddress
type PlaybackPosition = DefTypes.PlaybackPosition
type LoopChange = DefTypes.LoopChange
type Context<StepT> = PlaybackTypes.Context<StepT>
type Playback<StepT> = PlaybackTypes.Playback<StepT>
type PlaybackOptions<StepT, PhaseT, DirectionT> = RuntimeTypes.PlaybackOptions<StepT, PhaseT, DirectionT>
type PlaybackOwned = OwnershipTypes.PlaybackOwned
type RuntimeOwner = OwnershipTypes.RuntimeOwner
type Sequence<StepT> = SequenceTypes.Sequence<StepT>
type SequenceImpl<StepT> = SequenceTypes.SequenceImpl<StepT>

type Listener<T...> = PlaybackInternalTypes.Listener<T...>
type PlaybackImpl<StepT, PhaseT, DirectionT> = PlaybackInternalTypes.PlaybackImpl<StepT, PhaseT, DirectionT>
type ReconciliationView<StepT, PhaseT, DirectionT> = PlaybackInternalTypes.ReconciliationView<StepT, PhaseT, DirectionT>

type PlaybackModule = {
	new: <StepT, PhaseT, DirectionT>(
		sequence: Sequence<StepT>,
		options: PlaybackOptions<StepT, PhaseT, DirectionT>,
		runtime: RuntimeOwner
	) -> Playback<StepT>,
}

local Playback = {}
Playback.__index = Playback

local terminate: <StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	status: TerminalStatus,
	reason: string?,
	err: unknown?
) -> ()
local requestReconcile: <StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	clockPosition: number,
	runUpdates: boolean,
	observedDirection: DirectionT?
) -> ()
local flushMutations: <StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>) -> ()
local drainReconciliation: <StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>) -> ()

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isAliveStatus(status: Status): boolean
	return status == "idle" or status == "playing" or status == "paused"
end

local function isPlayingStatus(status: Status): boolean
	return status == "playing"
end

local function copyParams(base: Params, overrides: Params?): Params
	local result: Params = table.clone(base)
	if overrides ~= nil then
		for name, value in overrides do
			result[name] = value
		end
	end
	return result
end

local function bindListener<T...>(listeners: { Listener<T...> }, callback: (T...) -> ()): () -> ()
	local listener: Listener<T...> = {
		callback = callback,
		active = true,
	}
	table.insert(listeners, listener)
	return function()
		listener.active = false
	end
end

local function snapshotListeners<T...>(listeners: { Listener<T...> }): { (T...) -> () }
	local snapshot: { (T...) -> () } = {}
	for _, listener in listeners do
		if listener.active then
			table.insert(snapshot, listener.callback)
		end
	end
	return snapshot
end

local function callObserver<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, callback: () -> ())
	self._callbackDepth += 1
	local ok, callbackError = pcall(function(): unknown
		callback()
		return nil
	end)
	self._callbackDepth -= 1
	if not ok then
		warn("[Pulse] observer listener failed:", callbackError)
	end
end

local function callUser<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, callback: () -> ()): boolean
	self._callbackDepth += 1
	local ok, callbackError = pcall(function(): unknown
		callback()
		return nil
	end)
	self._callbackDepth -= 1
	if not ok then
		terminate(self, "failed", "callbackFailed", callbackError)
		return false
	end
	return isAliveStatus(self._status)
end

local function callGate<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	callback: () -> (boolean, string?)
): (boolean, string?)
	self._callbackDepth += 1
	local ok, allowed, reason = pcall(callback)
	self._callbackDepth -= 1
	if not ok then
		terminate(self, "failed", "callbackFailed", allowed)
		return false, "failed"
	end
	return allowed, reason
end

local function runCleanup(cleanup: () -> ())
	local ok, cleanupError = pcall(function(): unknown
		cleanup()
		return nil
	end)
	if not ok then
		warn("[Pulse] cleanup failed:", cleanupError)
	end
end

local function disposeCleanups<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	if self._disposed then
		return
	end
	self._disposed = true
	for index = #self._cleanups, 1, -1 do
		local cleanup = self._cleanups[index]
		self._cleanups[index] = nil
		runCleanup(cleanup)
	end
end

local cancelTask = Scheduling.cancelTask
local setUpdating = Scheduling.setUpdating
local readClock = Scheduling.readClock
local sequenceAtClock = Scheduling.sequenceAtClock
local refreshScheduling = Scheduling.refresh

local function queueMutation<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, mutation: () -> ()): boolean
	if self._callbackDepth == 0 then
		return false
	end
	table.insert(self._queuedMutations, mutation)
	return true
end

flushMutations = function<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	if self._flushingMutations or self._callbackDepth > 0 then
		return
	end
	self._flushingMutations = true
	while isAliveStatus(self._status) and #self._queuedMutations > 0 do
		local queuedClockChangeCount = #self._queuedClockChanges
		local mutation = table.remove(self._queuedMutations, 1)
		assert(mutation ~= nil, "Pulse queued mutation invariant failed")
		mutation()
		if #self._queuedClockChanges > queuedClockChangeCount then
			break
		end
	end
	if not isAliveStatus(self._status) then
		table.clear(self._queuedMutations)
	end
	self._flushingMutations = false
	if self._status == "playing" and not self._reconciling and #self._queuedClockChanges > 0 then
		drainReconciliation(self)
	end
end

local actionsAt = Timeline.actionsAt
local loopActionStage = Timeline.loopActionStage
local positionRecord = Timeline.positionRecord

local function reconciliationView<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>
): ReconciliationView<StepT, PhaseT, DirectionT>
	return (self :: unknown) :: ReconciliationView<StepT, PhaseT, DirectionT>
end

local function canStepInternal<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	step: StepT?,
	payload: unknown?
): (boolean, string?)
	return Reconciliation.canStep(reconciliationView(self), step, payload)
end

local function applyStep<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	step: StepT?,
	payload: unknown?,
	cause: DefTypes.StepChangeCause,
	direction: TraversalDirection?
): boolean
	return Reconciliation.applyStep(reconciliationView(self), step, payload, cause, direction)
end

drainReconciliation = function<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	Reconciliation.drain(reconciliationView(self))
end

requestReconcile = function<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	clockPosition: number,
	runUpdates: boolean,
	observedDirection: DirectionT?
)
	Reconciliation.request(reconciliationView(self), clockPosition, runUpdates, observedDirection)
end

local function fireEnded<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, completion: Completion)
	local snapshot = snapshotListeners(self._callbacks.ended)
	for _, callback in snapshot do
		callObserver(self, function()
			callback(completion)
		end)
	end
end

terminate = function<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	status: TerminalStatus,
	reason: string?,
	err: unknown?
)
	if not isAliveStatus(self._status) then
		return
	end
	local previousStatus = self._status
	self._status = status
	cancelTask(self)
	setUpdating(self, false)
	self._runtime:_detachPlayback((self :: unknown) :: PlaybackOwned)
	self._attached = false
	self._pendingReconcile = false
	self._pendingUpdate = false
	self._activeClockChange = nil
	table.clear(self._queuedClockChanges)
	self._scheduleRefreshPending = false
	table.clear(self._queuedMutations)

	local callback: (() -> ())? = nil
	if previousStatus ~= "idle" then
		if status == "cancelled" and self._sequence.definition.onCancel ~= nil then
			callback = function()
				(self._sequence.definition.onCancel :: (Context<StepT>, string?) -> ())(self._context, reason)
			end
		elseif (status == "completed" or status == "stopped") and self._sequence.definition.onStop ~= nil then
			callback = function()
				(self._sequence.definition.onStop :: (Context<StepT>, string?) -> ())(self._context, reason)
			end
		elseif status == "destroyed" and self._sequence.definition.onDestroy ~= nil then
			callback = function()
				(self._sequence.definition.onDestroy :: (Context<StepT>) -> ())(self._context)
			end
		end
	end
	if callback ~= nil then
		local ok, callbackError = pcall(function(): unknown
			callback()
			return nil
		end)
		if not ok then
			status = "failed"
			reason = "callbackFailed"
			err = callbackError
			self._status = status
		end
	end

	local completion: Completion = {
		status = status,
		reason = reason,
		error = err,
	}
	table.freeze(completion)
	self._completion = completion
	disposeCleanups(self)
	fireEnded(self, completion)
	table.clear(self._callbacks.looped)
	table.clear(self._callbacks.paramChanged)
	table.clear(self._callbacks.signaled)
end

local function reconcileClockChange<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, change: ClockChange)
	Reconciliation.reconcileClockChange(reconciliationView(self), change)
end

local function runContinuous<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, now: number)
	Reconciliation.runContinuous(reconciliationView(self), now)
end

local function setParamImmediate<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, name: string, value: unknown)
	local oldValue = self._params[name]
	if oldValue == value then
		return
	end
	self._params[name] = value
	self._mutationGeneration += 1
	local callback = self._sequence.definition.onParamChanged
	if callback ~= nil and not callUser(self, function()
		callback(self._context, name, value, oldValue)
	end) then
		return
	end
	local snapshot = snapshotListeners(self._callbacks.paramChanged)
	for _, observer in snapshot do
		callObserver(self, function()
			observer(name, value, oldValue)
		end)
	end
	flushMutations(self)
end

local function signalImmediate<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, name: string, payload: unknown?)
	self._mutationGeneration += 1
	local handler = self._sequence.signals[name]
	if handler ~= nil and not callUser(self, function()
		handler(self._context, payload)
	end) then
		return
	end
	local snapshot = snapshotListeners(self._callbacks.signaled)
	for _, observer in snapshot do
		callObserver(self, function()
			observer(name, payload)
		end)
	end
	flushMutations(self)
end

local function pauseImmediate<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	if self._status ~= "playing" then
		return
	end
	local sample = readClock(self)
	if not self._reconciling then
		requestReconcile(self, sample.timePosition, false, nil)
	end
	if self._status ~= "playing" then
		return
	end
	self._anchorClock = sample.timePosition
	self._anchorSequence = self._position
	self._status = "paused"
	self._mutationGeneration += 1
	cancelTask(self)
	setUpdating(self, false)
end

local function resumeImmediate<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	if self._status ~= "paused" or self._clock:isDestroyed() then
		return
	end
	local sample = readClock(self)
	if self._status ~= "paused" then
		return
	end
	self._anchorClock = sample.timePosition
	self._anchorSequence = self._position
	self._lastClockRate = sample.rate
	self._lastContinuousPosition = self._position
	self._status = "playing"
	self._mutationGeneration += 1
	requestReconcile(self, sample.timePosition, false, nil)
	if isPlayingStatus(self._status) then
		setUpdating(self, #self._sequence.updates > 0)
		refreshScheduling(self)
	end
end

local function setSpeedImmediate<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, speed: number)
	if not isAliveStatus(self._status) or self._playbackSpeed == speed then
		return
	end
	if self._status == "idle" then
		self._playbackSpeed = speed
		self._mutationGeneration += 1
		return
	end
	local sample = readClock(self)
	if self._status == "playing" and not self._reconciling then
		requestReconcile(self, sample.timePosition, false, nil)
	end
	if not isAliveStatus(self._status) then
		return
	end
	self._anchorClock = sample.timePosition
	self._anchorSequence = self._position
	self._playbackSpeed = speed
	self._lastClockRate = sample.rate
	self._mutationGeneration += 1
	cancelTask(self)
	if self._status == "playing" then
		requestReconcile(self, sample.timePosition, false, nil)
		if self._status == "playing" then
			refreshScheduling(self)
		end
	end
end

local function stepImmediate<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	step: StepT?,
	payload: unknown?
): (boolean, string?)
	local allowed, reason = canStepInternal(self, step, payload)
	if not allowed then
		flushMutations(self)
		return false, reason
	end
	if not isAliveStatus(self._status) then
		return false, "failed"
	end
	local applied = applyStep(self, step, payload, "manual", nil)
	self._mutationGeneration += 1
	flushMutations(self)
	return applied, if applied then nil else "failed"
end

function Playback.new<StepT, PhaseT, DirectionT>(
	sequence: Sequence<StepT>,
	options: PlaybackOptions<StepT, PhaseT, DirectionT>,
	runtime: RuntimeOwner
): Playback<StepT>
	local sequenceImpl = (sequence :: unknown) :: SequenceImpl<StepT>
	assert(table.isfrozen(sequenceImpl), "Pulse Runtime requires a compiled Sequence")
	local speed = if options.playbackSpeed == nil then 1 else options.playbackSpeed
	assert(isFinite(speed), "Pulse playbackSpeed must be finite")
	local initial = SequenceComponent.validateAddress(sequence, options.position or { timePosition = 0 })
	if options.step ~= nil then
		assert(sequenceImpl._compiledSteps[options.step] ~= nil, "Pulse initial step must exist in the Sequence")
	end

	local placeholderContext = (nil :: unknown) :: Context<StepT>
	local self = (
		setmetatable({
			_sequence = sequenceImpl,
			_clock = options.clock,
			_directions = options.directions,
			_phase = options.phase,
			_runtime = runtime,
			_context = placeholderContext,
			_status = "idle",
			_completion = nil,
			_started = false,
			_attached = false,
			_updating = false,
			_disposed = false,
			_callbacks = {
				ended = {},
				looped = {},
				paramChanged = {},
				signaled = {},
			},
			_params = copyParams(sequenceImpl.defaultParams, options.params),
			_cleanups = {},
			_step = options.step,
			_journal = {},
			_playbackSpeed = speed,
			_position = initial.unwrappedTimePosition,
			_boundaryStage = 0,
			_anchorClock = 0,
			_anchorSequence = initial.unwrappedTimePosition,
			_lastClockRate = 0,
			_lastContinuousPosition = initial.unwrappedTimePosition,
			_taskId = nil,
			_taskClockDirection = nil,
			_reconciling = false,
			_pendingReconcile = false,
			_pendingClockPosition = nil,
			_pendingUpdate = false,
			_pendingObservedDirection = nil,
			_activeClockChange = nil,
			_queuedClockChanges = {},
			_scheduleRefreshPending = false,
			_callbackDepth = 0,
			_flushingMutations = false,
			_queuedMutations = {},
			_mutationGeneration = 0,
		}, Playback) :: unknown
	) :: PlaybackImpl<StepT, PhaseT, DirectionT>

	local initialActions = actionsAt(sequenceImpl, self._position)
	if options.position ~= nil then
		self._boundaryStage = #initialActions
	elseif sequenceImpl.loop then
		self._boundaryStage = loopActionStage(initialActions) or 0
	end

	self._context = ContextComponent.new(self)
	runtime:_registerPlayback((self :: unknown) :: PlaybackOwned)
	return self
end

function Playback._terminate<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	status: TerminalStatus,
	reason: string?,
	err: unknown?
)
	terminate(self, status, reason, err)
end

function Playback._reconcileClockChange<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, change: ClockChange)
	reconcileClockChange(self, change)
end

function Playback._runContinuous<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, now: number)
	runContinuous(self, now)
end

function Playback._requestReconcile<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	clockPosition: number,
	runUpdates: boolean,
	observedDirection: DirectionT?
)
	requestReconcile(self, clockPosition, runUpdates, observedDirection)
end

function Playback._callObserver<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, callback: () -> ())
	callObserver(self, callback)
end

function Playback._callUser<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, callback: () -> ()): boolean
	return callUser(self, callback)
end

function Playback._callGate<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	callback: () -> (boolean, string?)
): (boolean, string?)
	return callGate(self, callback)
end

function Playback._flushMutations<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	flushMutations(self)
end

function Playback._refreshScheduling<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	refreshScheduling(self)
end

function Playback._dispose<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	disposeCleanups(self)
end

function Playback.play<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>): Playback<StepT>
	if self._status ~= "idle" then
		return self
	end
	if self._runtime:_isDestroyed() or self._clock:isDestroyed() then
		terminate(self, "destroyed", "clockDestroyed", nil)
		return self
	end
	local sample = readClock(self)
	if self._status ~= "idle" then
		return self
	end
	self._anchorClock = sample.timePosition
	self._anchorSequence = self._position
	self._lastClockRate = sample.rate
	self._lastContinuousPosition = self._position
	self._status = "playing"
	self._started = true
	if not self._runtime:_activatePlayback((self :: unknown) :: PlaybackOwned, self._clock) then
		terminate(self, "destroyed", "runtimeDestroyed", nil)
		return self
	end
	self._attached = true

	local callback = self._sequence.definition.onPlay
	if callback ~= nil and not callUser(self, function()
		callback(self._context)
	end) then
		return self
	end
	flushMutations(self)
	if isPlayingStatus(self._status) then
		requestReconcile(self, sample.timePosition, false, nil)
	end
	if isPlayingStatus(self._status) then
		setUpdating(self, #self._sequence.updates > 0)
		refreshScheduling(self)
	end
	return self
end

function Playback.pause<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	if self._status ~= "playing" then
		return
	end
	if queueMutation(self, function()
		pauseImmediate(self)
	end) then
		return
	end
	pauseImmediate(self)
end

function Playback.resume<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	if self._status ~= "paused" then
		return
	end
	if queueMutation(self, function()
		resumeImmediate(self)
	end) then
		return
	end
	resumeImmediate(self)
end

function Playback.stop<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, reason: string?)
	terminate(self, "stopped", reason or "stopped", nil)
end

function Playback.cancel<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, reason: string?)
	terminate(self, "cancelled", reason or "cancelled", nil)
end

function Playback.destroy<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	if isAliveStatus(self._status) then
		terminate(self, "destroyed", "destroyed", nil)
	else
		disposeCleanups(self)
	end
end

function Playback.onEnded<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	callback: PlaybackTypes.EndedCallback
): () -> ()
	local completion = self._completion
	if completion ~= nil then
		callObserver(self, function()
			callback(completion)
		end)
		return function() end
	end
	return bindListener(self._callbacks.ended, callback)
end

function Playback.onLooped<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	callback: PlaybackTypes.LoopedCallback
): () -> ()
	if not isAliveStatus(self._status) then
		return function() end
	end
	return bindListener(self._callbacks.looped, callback)
end

function Playback.onParamChanged<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	callback: PlaybackTypes.ParamChangedCallback
): () -> ()
	if not isAliveStatus(self._status) then
		return function() end
	end
	return bindListener(self._callbacks.paramChanged, callback)
end

function Playback.onSignaled<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	callback: PlaybackTypes.SignaledCallback
): () -> ()
	if not isAliveStatus(self._status) then
		return function() end
	end
	return bindListener(self._callbacks.signaled, callback)
end

function Playback.isAlive<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>): boolean
	return isAliveStatus(self._status)
end

function Playback.getStatus<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>): Status
	return self._status
end

function Playback.getCompletion<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>): Completion?
	return self._completion
end

function Playback.setParam<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, name: string, value: unknown)
	if not isAliveStatus(self._status) then
		return
	end
	if queueMutation(self, function()
		setParamImmediate(self, name, value)
	end) then
		return
	end
	setParamImmediate(self, name, value)
end

function Playback.getParam<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, name: string): unknown
	return self._params[name]
end

function Playback.setParams<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, params: Params)
	for name, value in params do
		Playback.setParam(self, name, value)
	end
end

function Playback.signal<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, name: string, payload: unknown?)
	if not isAliveStatus(self._status) then
		return
	end
	if queueMutation(self, function()
		signalImmediate(self, name, payload)
	end) then
		return
	end
	signalImmediate(self, name, payload)
end

function Playback.getStep<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>): StepT?
	return self._step
end

function Playback.canStep<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	step: StepT?,
	payload: unknown?
): (boolean, string?)
	if not isAliveStatus(self._status) then
		return false, "notAlive"
	end
	local allowed, reason = canStepInternal(self, step, payload)
	flushMutations(self)
	return allowed, reason
end

function Playback.step<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	step: StepT?,
	payload: unknown?
): (boolean, string?)
	if not isAliveStatus(self._status) then
		return false, "notAlive"
	end
	if self._callbackDepth > 0 then
		table.insert(self._queuedMutations, function()
			stepImmediate(self, step, payload)
		end)
		return true, nil
	end
	return stepImmediate(self, step, payload)
end

function Playback.setPlaybackSpeed<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, speed: number)
	assert(isFinite(speed), "Pulse playbackSpeed must be finite")
	if not isAliveStatus(self._status) then
		return
	end
	if queueMutation(self, function()
		setSpeedImmediate(self, speed)
	end) then
		return
	end
	setSpeedImmediate(self, speed)
end

function Playback.getPlaybackSpeed<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>): number
	return self._playbackSpeed
end

function Playback.seek<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, address: SequenceAddress): boolean
	if not isAliveStatus(self._status) then
		return false
	end
	SequenceComponent.validateAddress(self._sequence, address)
	return false
end

function Playback.getPosition<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>): PlaybackPosition
	if self._status == "playing" and not self._reconciling then
		local sample = readClock(self)
		if self._status ~= "playing" then
			return positionRecord(self)
		end
		local derived = sequenceAtClock(self, sample.timePosition)
		if derived == nil then
			return positionRecord(self)
		end
		if derived ~= self._position then
			local duration = self._sequence.duration
			if not self._sequence.loop then
				return {
					timePosition = derived,
					loopIndex = 0,
					unwrappedTimePosition = derived,
				}
			end
			assert(duration ~= nil and duration > 0, "Pulse loop duration invariant failed")
			local loopIndex = math.floor(derived / duration)
			return {
				timePosition = derived - loopIndex * duration,
				loopIndex = loopIndex,
				unwrappedTimePosition = derived,
			}
		end
	end
	return positionRecord(self)
end

function Playback.addCleanup<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, cleanup: () -> ())
	if self._disposed or not isAliveStatus(self._status) then
		runCleanup(cleanup)
		return
	end
	table.insert(self._cleanups, cleanup)
end

local module: PlaybackModule = {
	new = Playback.new,
}

return module
