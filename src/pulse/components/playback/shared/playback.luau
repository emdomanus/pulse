--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local ContextComponent = require(script.Parent.Parent.Parent.context.shared.context)
local ContextTypes = require(script.Parent.Parent.Parent.Parent.types.components.context)
local PlaybackTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback)
local RuntimeTypes = require(script.Parent.Parent.Parent.Parent.types.managers.runtimeManager)
local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence)
local SequenceComponent = require(script.Parent.Parent.Parent.sequence.shared.sequence)

type StepId = PlaybackTypes.StepId
type ClockSample = DefTypes.ClockSample
type ClockChange = DefTypes.ClockChange
type Clock<PhaseT, DirectionT> = DefTypes.Clock<PhaseT, DirectionT>
type ClockDirections<DirectionT> = DefTypes.ClockDirections<DirectionT>
type ScheduledTaskId = DefTypes.ScheduledTaskId
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
type PlaybackOwned = RuntimeTypes.PlaybackOwned
type PlaybackRuntimeLink = RuntimeTypes.PlaybackRuntimeLink
type ClockStatePort = RuntimeTypes.ClockStatePort
type PhaseGroupPort = RuntimeTypes.PhaseGroupPort
type PlaybackContextPort<StepT> = ContextTypes.PlaybackContextPort<StepT>
type Sequence<StepT> = SequenceTypes.Sequence<StepT>
type SequenceImpl<StepT> = SequenceTypes.SequenceImpl<StepT>
type CompiledEvent<StepT> = SequenceTypes.CompiledEvent<StepT>
type CompiledStep<StepT> = SequenceTypes.CompiledStep<StepT>
type StepChange<StepT> = SequenceTypes.StepChange<StepT>

type Listener<T...> = {
	callback: (T...) -> (),
	active: boolean,
}

type CallbackCollections = {
	ended: { Listener<Completion> },
	looped: { Listener<LoopChange> },
	paramChanged: { Listener<string, unknown, unknown?> },
	signaled: { Listener<string, unknown?> },
}

type Occurrence<StepT> = {
	state: "blocked" | "applied",
	from: StepT?,
	to: StepT?,
	payload: unknown?,
}

type Action<StepT> = {
	kind: "event" | "loop",
	event: CompiledEvent<StepT>?,
	loopIndex: number,
	fromLoopIndex: number,
	toLoopIndex: number,
}

type WorkState = {
	count: number,
}

type PlaybackImpl<StepT, PhaseT, DirectionT> = Playback<StepT> & {
	_sequence: SequenceImpl<StepT>,
	_clock: Clock<PhaseT, DirectionT>,
	_directions: ClockDirections<DirectionT>,
	_phase: PhaseT,
	_runtimeLink: PlaybackRuntimeLink,
	_clockPort: ClockStatePort,
	_phasePort: PhaseGroupPort,
	_owned: PlaybackOwned,
	_context: Context<StepT>,

	_status: Status,
	_completion: Completion?,
	_started: boolean,
	_attached: boolean,
	_updating: boolean,
	_disposed: boolean,

	_callbacks: CallbackCollections,
	_params: Params,
	_cleanups: { () -> () },
	_step: StepT?,
	_journal: { [string]: Occurrence<StepT> },

	_playbackSpeed: number,
	_position: number,
	_boundaryStage: number,
	_anchorClock: number,
	_anchorSequence: number,
	_lastClockRate: number,
	_lastContinuousPosition: number,

	_taskId: ScheduledTaskId?,
	_taskClockDirection: DirectionT?,

	_reconciling: boolean,
	_pendingReconcile: boolean,
	_pendingClockPosition: number?,
	_pendingUpdate: boolean,
	_pendingObservedDirection: DirectionT?,
	_callbackDepth: number,
	_flushingMutations: boolean,
	_queuedMutations: { () -> () },
	_mutationGeneration: number,
}

type PlaybackModule = {
	new: <StepT, PhaseT, DirectionT>(
		sequence: Sequence<StepT>,
		options: PlaybackOptions<StepT, PhaseT, DirectionT>,
		runtimeLink: PlaybackRuntimeLink
	) -> Playback<StepT>,
}

local MAX_EXACT_INTEGER = 9_007_199_254_740_991
local MAX_RECONCILE_WORK = 4_096

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
local refreshScheduling: <StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>) -> ()
local flushMutations: <StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>) -> ()

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isAliveStatus(status: Status): boolean
	return status == "idle" or status == "playing" or status == "paused"
end

local function isPlayingStatus(status: Status): boolean
	return status == "playing"
end

local function sign(value: number): number
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	end
	return 0
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

local function cancelTask<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	local taskId = self._taskId
	self._taskId = nil
	self._taskClockDirection = nil
	if taskId ~= nil then
		self._clock:cancel(taskId)
	end
end

local function setUpdating<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, updating: boolean)
	if self._updating == updating then
		return
	end
	self._updating = updating
	if self._attached then
		self._runtimeLink.setUpdating(self._owned, updating)
	end
end

local function readClock<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>): ClockSample
	local ok, result = pcall(function(): unknown
		return DefTypes.assertClockSample(self._clock:read())
	end)
	if not ok then
		terminate(self, "failed", "invalidClockSample", result)
		return {
			timePosition = self._anchorClock,
			rate = 0,
		}
	end
	return (result :: unknown) :: ClockSample
end

local function sequenceAtClock<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, clockPosition: number): number
	local result = self._anchorSequence + (clockPosition - self._anchorClock) * self._playbackSpeed
	assert(isFinite(result), "Pulse playback anchor produced a non-finite sequence position")
	return result
end

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
		local mutation = table.remove(self._queuedMutations, 1)
		assert(mutation ~= nil, "Pulse queued mutation invariant failed")
		mutation()
	end
	if not isAliveStatus(self._status) then
		table.clear(self._queuedMutations)
	end
	self._flushingMutations = false
end

local function firstAtOrAfter<StepT>(events: { CompiledEvent<StepT> }, target: number): number
	local low = 1
	local high = #events + 1
	while low < high do
		local middle = math.floor((low + high) / 2)
		if middle <= #events and events[middle].definition.time < target then
			low = middle + 1
		else
			high = middle
		end
	end
	return low
end

local function firstAfter<StepT>(events: { CompiledEvent<StepT> }, target: number): number
	local low = 1
	local high = #events + 1
	while low < high do
		local middle = math.floor((low + high) / 2)
		if middle <= #events and events[middle].definition.time <= target then
			low = middle + 1
		else
			high = middle
		end
	end
	return low
end

local function lastBefore<StepT>(events: { CompiledEvent<StepT> }, target: number): number
	return firstAtOrAfter(events, target) - 1
end

local function appendEventsAt<StepT>(
	actions: { Action<StepT> },
	events: { CompiledEvent<StepT> },
	timePosition: number,
	loopIndex: number
)
	local index = firstAtOrAfter(events, timePosition)
	while index <= #events and events[index].definition.time == timePosition do
		table.insert(actions, {
			kind = "event",
			event = events[index],
			loopIndex = loopIndex,
			fromLoopIndex = loopIndex,
			toLoopIndex = loopIndex,
		})
		index += 1
	end
end

local function boundaryIndexAt(position: number, duration: number): number?
	local below = math.floor(position / duration)
	if position == below * duration then
		return below
	end
	local above = below + 1
	if position == above * duration then
		return above
	end
	return nil
end

local function actionsAt<StepT>(sequence: SequenceImpl<StepT>, position: number): { Action<StepT> }
	local actions: { Action<StepT> } = {}
	local duration = sequence.duration
	if not sequence.loop then
		appendEventsAt(actions, sequence._forwardEvents, position, 0)
		return actions
	end

	assert(duration ~= nil and duration > 0, "Pulse loop duration invariant failed")
	local boundaryIndex = boundaryIndexAt(position, duration)
	if boundaryIndex ~= nil then
		appendEventsAt(actions, sequence._forwardEvents, duration, boundaryIndex - 1)
		table.insert(actions, {
			kind = "loop",
			event = nil,
			loopIndex = boundaryIndex,
			fromLoopIndex = boundaryIndex - 1,
			toLoopIndex = boundaryIndex,
		})
		appendEventsAt(actions, sequence._forwardEvents, 0, boundaryIndex)
		return actions
	end

	local loopIndex = math.floor(position / duration)
	local localPosition = position - loopIndex * duration
	appendEventsAt(actions, sequence._forwardEvents, localPosition, loopIndex)
	return actions
end

local function loopActionStage<StepT>(actions: { Action<StepT> }): number?
	for index, action in actions do
		if action.kind == "loop" then
			return index
		end
	end
	return nil
end

local function positionRecord<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>): PlaybackPosition
	local sequence = self._sequence
	local duration = sequence.duration
	if not sequence.loop then
		return {
			timePosition = self._position,
			loopIndex = 0,
			unwrappedTimePosition = self._position,
		}
	end

	assert(duration ~= nil and duration > 0, "Pulse loop duration invariant failed")
	local boundaryIndex = boundaryIndexAt(self._position, duration)
	if boundaryIndex ~= nil then
		local actions = actionsAt(sequence, self._position)
		local loopStage = loopActionStage(actions)
		assert(loopStage ~= nil, "Pulse loop boundary action invariant failed")
		if self._boundaryStage < loopStage then
			return {
				timePosition = duration,
				loopIndex = boundaryIndex - 1,
				unwrappedTimePosition = self._position,
			}
		end
		return {
			timePosition = 0,
			loopIndex = boundaryIndex,
			unwrappedTimePosition = self._position,
		}
	end

	local loopIndex = math.floor(self._position / duration)
	return {
		timePosition = self._position - loopIndex * duration,
		loopIndex = loopIndex,
		unwrappedTimePosition = self._position,
	}
end

local function journalKey<StepT>(event: CompiledEvent<StepT>, loopIndex: number): string
	return `{event._identity}:{loopIndex}`
end

local function localTimePosition<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>): number
	return positionRecord(self).timePosition
end

local function canStepInternal<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	step: StepT?,
	payload: unknown?
): (boolean, string?)
	if step == nil then
		return true, nil
	end
	local compiledStep: CompiledStep<StepT>? = self._sequence._compiledSteps[step]
	if compiledStep == nil then
		return false, "missingStep"
	end

	local canEnter = compiledStep.definition.canEnter
	if canEnter ~= nil then
		local allowed, reason = callGate(self, function()
			return canEnter(self._context, payload)
		end)
		if not allowed then
			return false, reason
		end
	end

	local transitions = self._sequence.transitions
	if #transitions == 0 then
		return true, nil
	end
	local timePosition = localTimePosition(self)
	for _, transition in transitions do
		local matches = (transition.from == nil or transition.from == self._step)
			and (transition.to == nil or transition.to == step)
			and (transition.after == nil or timePosition >= transition.after)
			and (transition.before == nil or timePosition <= transition.before)
		if matches then
			local canTransition = transition.canStep
			if canTransition ~= nil then
				return callGate(self, function()
					return canTransition(self._context, self._step, step, payload)
				end)
			end
			return true, nil
		end
	end
	return false, "blockedTransition"
end

local function emitStep<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, change: StepChange<StepT>): boolean
	local callback = self._sequence.definition.onStep
	if callback == nil then
		return true
	end
	return callUser(self, function()
		callback(self._context, change)
	end)
end

local function applyStep<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	step: StepT?,
	payload: unknown?,
	cause: DefTypes.StepChangeCause,
	direction: TraversalDirection?
): boolean
	local from = self._step
	self._step = step
	if step ~= nil then
		local compiledStep = self._sequence._compiledSteps[step]
		assert(compiledStep ~= nil, "Pulse step disappeared from a compiled sequence")
		local run = compiledStep.definition.run
		if run ~= nil and not callUser(self, function()
			run(self._context, payload)
		end) then
			return false
		end
	end
	if not isAliveStatus(self._status) then
		return false
	end
	return emitStep(self, {
		from = from,
		to = step,
		payload = payload,
		cause = cause,
		direction = direction,
	})
end

local function processForwardEvent<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	event: CompiledEvent<StepT>,
	loopIndex: number
): boolean
	local definition = event.definition
	local targetStep = definition.step
	if targetStep ~= nil then
		local allowed = canStepInternal(self, targetStep, nil)
		if not isAliveStatus(self._status) then
			return false
		end
		local key = journalKey(event, loopIndex)
		if not allowed then
			self._journal[key] = {
				state = "blocked",
				from = self._step,
				to = targetStep,
				payload = nil,
			}
			return true
		end

		local from = self._step
		if not applyStep(self, targetStep, nil, "event", "forward") then
			return false
		end
		local run = definition.run
		if run ~= nil and not callUser(self, function()
			run(self._context)
		end) then
			return false
		end
		if not isAliveStatus(self._status) then
			return false
		end
		self._journal[key] = {
			state = "applied",
			from = from,
			to = targetStep,
			payload = nil,
		}
		return true
	end

	local run = definition.run
	if run ~= nil then
		return callUser(self, function()
			run(self._context)
		end)
	end
	return true
end

local function processReverseEvent<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	event: CompiledEvent<StepT>,
	loopIndex: number
): boolean
	local definition = event.definition
	local targetStep = definition.step
	if targetStep == nil then
		local reverse = event.reverse
		if reverse == "cancel" then
			terminate(self, "cancelled", "reverseEventUnavailable", nil)
			return false
		elseif reverse == "ignore" then
			return true
		end
		return callUser(self, function()
			(reverse :: (Context<StepT>) -> ())(self._context)
		end)
	end

	local key = journalKey(event, loopIndex)
	local occurrence = self._journal[key]
	if occurrence == nil then
		terminate(self, "cancelled", "missingReverseHistory", nil)
		return false
	end
	if occurrence.state == "blocked" then
		self._journal[key] = nil
		return true
	end
	if self._step ~= occurrence.to then
		terminate(self, "cancelled", "stepHistoryDiverged", nil)
		return false
	end

	local eventReverse = event.reverse
	local compiledStep = self._sequence._compiledSteps[targetStep]
	assert(compiledStep ~= nil, "Pulse step disappeared from a compiled sequence")
	local stepReverse = compiledStep.reverse
	if eventReverse == "cancel" then
		terminate(self, "cancelled", "reverseEventUnavailable", nil)
		return false
	end
	if stepReverse == "cancel" then
		terminate(self, "cancelled", "reverseStepUnavailable", nil)
		return false
	end

	if
		eventReverse ~= "ignore"
		and not callUser(self, function()
			(eventReverse :: (Context<StepT>) -> ())(self._context)
		end)
	then
		return false
	end
	if
		stepReverse ~= "ignore"
		and not callUser(self, function()
			(stepReverse :: (Context<StepT>, unknown?) -> ())(self._context, occurrence.payload)
		end)
	then
		return false
	end
	if not isAliveStatus(self._status) then
		return false
	end

	local previous = self._step
	self._step = occurrence.from
	if
		not emitStep(self, {
			from = previous,
			to = occurrence.from,
			payload = occurrence.payload,
			cause = "event",
			direction = "backward",
		})
	then
		return false
	end
	self._journal[key] = nil
	return true
end

local function fireLoopObservers<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, change: LoopChange)
	local snapshot = snapshotListeners(self._callbacks.looped)
	for _, callback in snapshot do
		callObserver(self, function()
			callback(change)
		end)
	end
end

local function processLoop<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	action: Action<StepT>,
	direction: TraversalDirection
): boolean
	local change: LoopChange
	if direction == "forward" then
		change = {
			fromLoopIndex = action.fromLoopIndex,
			toLoopIndex = action.toLoopIndex,
			direction = "forward",
		}
	else
		change = {
			fromLoopIndex = action.toLoopIndex,
			toLoopIndex = action.fromLoopIndex,
			direction = "backward",
		}
	end
	local callback = self._sequence.definition.onLoop
	if callback ~= nil and not callUser(self, function()
		callback(self._context, change)
	end) then
		return false
	end
	if not isAliveStatus(self._status) then
		return false
	end
	fireLoopObservers(self, change)
	return isAliveStatus(self._status)
end

local function processAction<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	action: Action<StepT>,
	direction: TraversalDirection
): boolean
	if action.kind == "loop" then
		return processLoop(self, action, direction)
	end
	local event = action.event
	assert(event ~= nil, "Pulse event action invariant failed")
	if direction == "forward" then
		return processForwardEvent(self, event, action.loopIndex)
	end
	return processReverseEvent(self, event, action.loopIndex)
end

local function processCurrentCoordinate<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	direction: TraversalDirection,
	work: WorkState
): boolean
	local actions = actionsAt(self._sequence, self._position)
	while isAliveStatus(self._status) do
		local actionIndex = if direction == "forward" then self._boundaryStage + 1 else self._boundaryStage
		if actionIndex < 1 or actionIndex > #actions then
			return true
		end
		if work.count >= MAX_RECONCILE_WORK then
			terminate(self, "failed", "catchUpLimitExceeded", "Pulse reconciliation work limit exceeded")
			return false
		end
		work.count += 1
		local generation = self._mutationGeneration
		if not processAction(self, actions[actionIndex], direction) then
			return false
		end
		if direction == "forward" then
			self._boundaryStage += 1
		else
			self._boundaryStage -= 1
		end
		flushMutations(self)
		if self._mutationGeneration ~= generation and not self._pendingReconcile then
			self._pendingReconcile = true
			self._pendingClockPosition = readClock(self).timePosition
		end
		if self._mutationGeneration ~= generation or self._pendingReconcile then
			return false
		end
	end
	return false
end

local function nextEventCoordinate<StepT>(
	sequence: SequenceImpl<StepT>,
	position: number,
	direction: TraversalDirection
): number?
	local events = sequence._forwardEvents
	if #events == 0 then
		return nil
	end
	local duration = sequence.duration
	if not sequence.loop then
		if direction == "forward" then
			local index = firstAfter(events, position)
			return if index <= #events then events[index].definition.time else nil
		end
		local index = lastBefore(events, position)
		return if index >= 1 then events[index].definition.time else nil
	end

	assert(duration ~= nil and duration > 0, "Pulse loop duration invariant failed")
	local loopIndex = math.floor(position / duration)
	local localPosition = position - loopIndex * duration
	if direction == "forward" then
		local index = firstAfter(events, localPosition)
		if index <= #events then
			return loopIndex * duration + events[index].definition.time
		end
		local nextIndex = firstAfter(events, 0)
		if events[1].definition.time == 0 then
			nextIndex = 1
		end
		if nextIndex <= #events then
			return (loopIndex + 1) * duration + events[nextIndex].definition.time
		end
		return nil
	end

	local index = lastBefore(events, localPosition)
	if index >= 1 then
		return loopIndex * duration + events[index].definition.time
	end
	local previousIndex = lastBefore(events, duration)
	if previousIndex >= 1 then
		return (loopIndex - 1) * duration + events[previousIndex].definition.time
	end
	return nil
end

local function nextLoopBoundary<StepT>(sequence: SequenceImpl<StepT>, position: number, direction: TraversalDirection): number?
	if not sequence.loop then
		return nil
	end
	local duration = sequence.duration
	assert(duration ~= nil and duration > 0, "Pulse loop duration invariant failed")
	local boundaryIndex = math.floor(position / duration)
	if direction == "forward" then
		return (boundaryIndex + 1) * duration
	end
	if position == boundaryIndex * duration then
		return (boundaryIndex - 1) * duration
	end
	return boundaryIndex * duration
end

local function nextCheckpoint<StepT>(sequence: SequenceImpl<StepT>, position: number, direction: TraversalDirection): number?
	local eventCoordinate = nextEventCoordinate(sequence, position, direction)
	local boundaryCoordinate = nextLoopBoundary(sequence, position, direction)
	local selected = eventCoordinate
	if boundaryCoordinate ~= nil then
		if
			selected == nil
			or (direction == "forward" and boundaryCoordinate < selected)
			or (direction == "backward" and boundaryCoordinate > selected)
		then
			selected = boundaryCoordinate
		end
	end
	if not sequence.loop and sequence.duration ~= nil then
		local terminal = if direction == "forward" then sequence.duration else 0
		if (direction == "forward" and terminal > position) or (direction == "backward" and terminal < position) then
			if
				selected == nil
				or (direction == "forward" and terminal < selected)
				or (direction == "backward" and terminal > selected)
			then
				selected = terminal
			end
		end
	end
	return selected
end

local function reconcileToward<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	target: number,
	direction: TraversalDirection,
	work: WorkState
): boolean
	if self._sequence.loop then
		local duration = self._sequence.duration
		assert(duration ~= nil and duration > 0, "Pulse loop duration invariant failed")
		local targetLoop = math.floor(target / duration)
		local adjacentLoop = if targetLoop >= 0 then targetLoop + 1 else targetLoop - 1
		if math.abs(targetLoop) > MAX_EXACT_INTEGER or targetLoop * duration == adjacentLoop * duration then
			terminate(self, "failed", "loopIdentityExceeded", "Pulse loop identity is no longer exactly representable")
			return false
		end
	end

	if not processCurrentCoordinate(self, direction, work) then
		return false
	end
	while isAliveStatus(self._status) do
		local coordinate = nextCheckpoint(self._sequence, self._position, direction)
		if
			coordinate == nil
			or (direction == "forward" and coordinate > target)
			or (direction == "backward" and coordinate < target)
		then
			if self._position ~= target then
				self._position = target
				self._boundaryStage = 0
			end
			break
		end
		self._position = coordinate
		local actions = actionsAt(self._sequence, coordinate)
		self._boundaryStage = if direction == "forward" then 0 else #actions
		if not processCurrentCoordinate(self, direction, work) then
			return false
		end
		if coordinate == target then
			break
		end
	end

	if not isAliveStatus(self._status) then
		return false
	end
	local duration = self._sequence.duration
	if not self._sequence.loop and duration ~= nil then
		if
			(direction == "forward" and self._position >= duration)
			or (direction == "backward" and self._position <= 0)
		then
			terminate(self, "completed", "completed", nil)
			return false
		end
	end
	return true
end

local function expectedTraversalDirection<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	clockRate: number,
	observedDirection: DirectionT?
): TraversalDirection?
	local clockSign = sign(clockRate)
	if observedDirection ~= nil then
		if observedDirection == self._directions.forward then
			clockSign = 1
		elseif observedDirection == self._directions.backward then
			clockSign = -1
		else
			terminate(self, "failed", "invalidClockDirection", nil)
			return nil
		end
	end
	local sequenceSign = clockSign * sign(self._playbackSpeed)
	if sequenceSign > 0 then
		return "forward"
	elseif sequenceSign < 0 then
		return "backward"
	end
	return nil
end

local function runUpdates<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	if self._status ~= "playing" then
		return
	end
	local delta = self._position - self._lastContinuousPosition
	self._lastContinuousPosition = self._position
	local current = localTimePosition(self)
	for _, update in self._sequence.updates do
		local generation = self._mutationGeneration
		if not callUser(self, function()
			update.run(self._context, delta, current)
		end) then
			return
		end
		flushMutations(self)
		if self._status ~= "playing" or self._mutationGeneration ~= generation then
			return
		end
	end
end

requestReconcile = function<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	clockPosition: number,
	shouldRunUpdates: boolean,
	observedDirection: DirectionT?
)
	assert(isFinite(clockPosition), "Pulse phase/reached clock position must be finite")
	self._pendingReconcile = true
	self._pendingClockPosition = clockPosition
	self._pendingUpdate = self._pendingUpdate or shouldRunUpdates
	if observedDirection ~= nil then
		self._pendingObservedDirection = observedDirection
	end
	if self._reconciling then
		return
	end

	self._reconciling = true
	local work: WorkState = { count = 0 }
	while self._pendingReconcile and self._status == "playing" do
		self._pendingReconcile = false
		local pendingPosition = self._pendingClockPosition
		self._pendingClockPosition = nil
		local pendingObserved = self._pendingObservedDirection
		self._pendingObservedDirection = nil
		if pendingPosition == nil then
			pendingPosition = readClock(self).timePosition
		end
		local target = sequenceAtClock(self, pendingPosition :: number)
		local traversal: TraversalDirection?
		if target > self._position then
			traversal = "forward"
		elseif target < self._position then
			traversal = "backward"
		else
			traversal = expectedTraversalDirection(self, self._lastClockRate, pendingObserved)
		end
		if traversal ~= nil then
			reconcileToward(self, target, traversal, work)
		else
			self._position = target
		end
	end
	local shouldUpdate = self._pendingUpdate
	self._pendingUpdate = false
	self._reconciling = false
	if shouldUpdate and self._status == "playing" then
		runUpdates(self)
	end
end

local function onReached<StepT, PhaseT, DirectionT>(
	self: PlaybackImpl<StepT, PhaseT, DirectionT>,
	taskId: ScheduledTaskId,
	_now: number,
	direction: DirectionT
)
	if self._status ~= "playing" or self._taskId ~= taskId or self._clock:isDestroyed() then
		return
	end
	local sample = readClock(self)
	if self._status ~= "playing" then
		cancelTask(self)
		return
	end
	self._lastClockRate = sample.rate
	requestReconcile(self, sample.timePosition, false, direction)
	if self._status == "playing" then
		refreshScheduling(self)
	end
end

refreshScheduling = function<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>)
	if self._status ~= "playing" then
		cancelTask(self)
		return
	end
	local sample = readClock(self)
	if self._status ~= "playing" then
		cancelTask(self)
		return
	end
	self._lastClockRate = sample.rate
	local clockSign = sign(sample.rate)
	local speedSign = sign(self._playbackSpeed)
	if clockSign == 0 or speedSign == 0 then
		cancelTask(self)
		return
	end
	local traversal: TraversalDirection = if clockSign * speedSign > 0 then "forward" else "backward"
	local checkpoint = nextCheckpoint(self._sequence, self._position, traversal)
	if checkpoint == nil then
		cancelTask(self)
		return
	end
	local clockCheckpoint = self._anchorClock + (checkpoint - self._anchorSequence) / self._playbackSpeed
	if not isFinite(clockCheckpoint) then
		terminate(self, "failed", "invalidSchedule", "Pulse checkpoint mapping is non-finite")
		return
	end
	local clockDirection: DirectionT = if clockSign > 0 then self._directions.forward else self._directions.backward
	local existingId = self._taskId
	if existingId ~= nil and self._taskClockDirection == clockDirection then
		if self._clock:rescheduleAt(existingId, clockCheckpoint, self._phase) then
			return
		end
		self._taskId = nil
		self._taskClockDirection = nil
	end
	if existingId ~= nil then
		self._clock:cancel(existingId)
		self._taskId = nil
		self._taskClockDirection = nil
	end

	local taskId: ScheduledTaskId = 0
	taskId = self._clock:bindToReached(clockCheckpoint, clockDirection, function(now, actualDirection)
		onReached(self, taskId, now, actualDirection)
	end, self._phase)
	self._taskId = taskId
	self._taskClockDirection = clockDirection
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
	self._runtimeLink.detach(self._owned)
	self._attached = false
	self._pendingReconcile = false
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
	if not isAliveStatus(self._status) then
		return
	end
	if self._clock:isDestroyed() then
		terminate(self, "destroyed", "clockDestroyed", nil)
		return
	end
	if self._status ~= "playing" then
		return
	end
	if change.discontinuous then
		terminate(self, "cancelled", "clockDiscontinuity", nil)
		return
	end
	local sample = readClock(self)
	if self._status ~= "playing" then
		return
	end
	local oldRateSign = sign(self._lastClockRate)
	local current = sequenceAtClock(self, sample.timePosition)
	requestReconcile(self, sample.timePosition, false, nil)
	if self._status ~= "playing" then
		return
	end
	self._anchorClock = sample.timePosition
	self._anchorSequence = current
	self._position = current
	self._lastClockRate = sample.rate
	if sign(sample.rate) ~= oldRateSign then
		cancelTask(self)
		requestReconcile(self, sample.timePosition, false, nil)
		if self._status == "playing" then
			refreshScheduling(self)
		end
	end
end

local function runContinuous<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>, now: number)
	if self._status ~= "playing" then
		return
	end
	requestReconcile(self, now, true, nil)
	if self._status == "playing" then
		refreshScheduling(self)
	end
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
	runtimeLink: PlaybackRuntimeLink
): Playback<StepT>
	local sequenceImpl = (sequence :: unknown) :: SequenceImpl<StepT>
	assert(table.isfrozen(sequenceImpl), "Pulse Runtime requires a compiled Sequence")
	local speed = if options.playbackSpeed == nil then 1 else options.playbackSpeed
	assert(isFinite(speed), "Pulse playbackSpeed must be finite")
	local initial = SequenceComponent.validateAddress(sequence, options.position or { timePosition = 0 })
	if options.step ~= nil then
		assert(sequenceImpl._compiledSteps[options.step] ~= nil, "Pulse initial step must exist in the Sequence")
	end

	local placeholderOwned = (nil :: unknown) :: PlaybackOwned
	local placeholderContext = (nil :: unknown) :: Context<StepT>
	local placeholderClockPort = (nil :: unknown) :: ClockStatePort
	local placeholderPhasePort = (nil :: unknown) :: PhaseGroupPort
	local self = (
		setmetatable({
			_sequence = sequenceImpl,
			_clock = options.clock,
			_directions = options.directions,
			_phase = options.phase,
			_runtimeLink = runtimeLink,
			_clockPort = placeholderClockPort,
			_phasePort = placeholderPhasePort,
			_owned = placeholderOwned,
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

	local contextPort: PlaybackContextPort<StepT> = {
		getPosition = function(_): PlaybackPosition
			return Playback.getPosition(self)
		end,
		seek = function(_, address)
			return Playback.seek(self, address)
		end,
		getPlaybackSpeed = function(_): number
			return Playback.getPlaybackSpeed(self)
		end,
		setPlaybackSpeed = function(_, value)
			Playback.setPlaybackSpeed(self, value)
		end,
		getStep = function(_): StepT?
			return Playback.getStep(self)
		end,
		canStep = function(_, target, payload)
			return Playback.canStep(self, target, payload)
		end,
		step = function(_, target, payload)
			return Playback.step(self, target, payload)
		end,
		getParam = function(_, name)
			return Playback.getParam(self, name)
		end,
		setParam = function(_, name, value)
			Playback.setParam(self, name, value)
		end,
		signal = function(_, name, payload)
			Playback.signal(self, name, payload)
		end,
		addCleanup = function(_, cleanup)
			Playback.addCleanup(self, cleanup)
		end,
		pause = function(_)
			Playback.pause(self)
		end,
		resume = function(_)
			Playback.resume(self)
		end,
		getStatus = function(_): Status
			return Playback.getStatus(self)
		end,
		stop = function(_, reason)
			Playback.stop(self, reason)
		end,
		cancel = function(_, reason)
			Playback.cancel(self, reason)
		end,
		destroy = function(_)
			Playback.destroy(self)
		end,
	}
	self._context = ContextComponent.new(contextPort)

	local owned: PlaybackOwned = {
		terminate = function(status, reason, err)
			terminate(self, status, reason, err)
		end,
		reconcileClockChange = function(change)
			reconcileClockChange(self, change)
		end,
		runContinuous = function(now)
			runContinuous(self, now)
		end,
		dispose = function()
			disposeCleanups(self)
		end,
	}
	self._owned = owned
	self._clockPort = {
		sameClock = function(candidate: unknown): boolean
			return candidate == options.clock
		end,
		bindChanged = function(callback, invalid)
			return options.clock:bindToChanged(function(rawChange: unknown)
				local ok, result = pcall(function(): unknown
					return DefTypes.assertClockChange(rawChange)
				end)
				if ok then
					callback((result :: unknown) :: ClockChange)
				else
					invalid(result)
				end
			end, false)
		end,
		isDestroyed = function(): boolean
			return options.clock:isDestroyed()
		end,
	}
	self._phasePort = {
		samePhase = function(candidate: unknown): boolean
			return candidate == options.phase
		end,
		bind = function(callback)
			return options.clock:bindPhase(options.phase, callback)
		end,
	}
	runtimeLink.register(owned)
	return self
end

function Playback.play<StepT, PhaseT, DirectionT>(self: PlaybackImpl<StepT, PhaseT, DirectionT>): Playback<StepT>
	if self._status ~= "idle" then
		return self
	end
	if self._runtimeLink.isDestroyed() or self._clock:isDestroyed() then
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
	if not self._runtimeLink.activate(self._owned, self._clockPort, self._phasePort, self._clock, self._phase) then
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
