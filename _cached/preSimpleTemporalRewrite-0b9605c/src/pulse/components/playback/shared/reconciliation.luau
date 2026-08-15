--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local PlaybackInternalTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback.internal)
local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence)
local Scheduling = require(script.Parent.scheduling)
local Timeline = require(script.Parent.timeline)

type Context<StepT> = SequenceTypes.Context<StepT>
type CompiledEvent<StepT> = SequenceTypes.CompiledEvent<StepT>
type CompiledStep<StepT> = SequenceTypes.CompiledStep<StepT>
type StepChange<StepT> = SequenceTypes.StepChange<StepT>
type Action<StepT> = PlaybackInternalTypes.Action<StepT>
type Listener<T...> = PlaybackInternalTypes.Listener<T...>
type PendingClockChange = PlaybackInternalTypes.PendingClockChange
type WorkState = PlaybackInternalTypes.WorkState
type ReconciliationView<StepT, PhaseT, DirectionT> = PlaybackInternalTypes.ReconciliationView<StepT, PhaseT, DirectionT>

type ReconciliationModule = {
	canStep: <StepT, PhaseT, DirectionT>(
		view: ReconciliationView<StepT, PhaseT, DirectionT>,
		step: StepT?,
		payload: unknown?
	) -> (boolean, string?),
	applyStep: <StepT, PhaseT, DirectionT>(
		view: ReconciliationView<StepT, PhaseT, DirectionT>,
		step: StepT?,
		payload: unknown?,
		cause: DefTypes.StepChangeCause,
		direction: DefTypes.TraversalDirection?
	) -> boolean,
	enqueueClockChange: <StepT, PhaseT, DirectionT>(
		view: ReconciliationView<StepT, PhaseT, DirectionT>,
		sample: DefTypes.ClockSample
	) -> (),
	drain: <StepT, PhaseT, DirectionT>(view: ReconciliationView<StepT, PhaseT, DirectionT>) -> (),
	request: <StepT, PhaseT, DirectionT>(
		view: ReconciliationView<StepT, PhaseT, DirectionT>,
		clockPosition: number,
		runUpdates: boolean,
		observedDirection: DirectionT?
	) -> (),
	reconcileClockChange: <StepT, PhaseT, DirectionT>(
		view: ReconciliationView<StepT, PhaseT, DirectionT>,
		change: DefTypes.ClockChange
	) -> (),
	runContinuous: <StepT, PhaseT, DirectionT>(
		view: ReconciliationView<StepT, PhaseT, DirectionT>,
		now: number
	) -> (),
}

local MAX_EXACT_INTEGER = 9_007_199_254_740_991
local MAX_RECONCILE_WORK = 4_096

local Reconciliation = {}

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isAliveStatus(status: DefTypes.Status): boolean
	return status == "idle" or status == "playing" or status == "paused"
end

local function sign(value: number): number
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	end
	return 0
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

local function journalKey<StepT>(event: CompiledEvent<StepT>, loopIndex: number): string
	return `{event._identity}:{loopIndex}`
end

function Reconciliation.canStep<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	step: StepT?,
	payload: unknown?
): (boolean, string?)
	if step == nil then
		return true, nil
	end
	local compiledStep: CompiledStep<StepT>? = view._sequence._compiledSteps[step]
	if compiledStep == nil then
		return false, "missingStep"
	end

	local canEnter = compiledStep.definition.canEnter
	if canEnter ~= nil then
		local allowed, reason = view:_callGate(function()
			return canEnter(view._context, payload)
		end)
		if not allowed then
			return false, reason
		end
	end

	local transitions = view._sequence.transitions
	if #transitions == 0 then
		return true, nil
	end
	local timePosition = Timeline.localTimePosition(view)
	for _, transition in transitions do
		local matches = (transition.from == nil or transition.from == view._step)
			and (transition.to == nil or transition.to == step)
			and (transition.after == nil or timePosition >= transition.after)
			and (transition.before == nil or timePosition <= transition.before)
		if matches then
			local canTransition = transition.canStep
			if canTransition ~= nil then
				return view:_callGate(function()
					return canTransition(view._context, view._step, step, payload)
				end)
			end
			return true, nil
		end
	end
	return false, "blockedTransition"
end

local function emitStep<StepT, PhaseT, DirectionT>(view: ReconciliationView<StepT, PhaseT, DirectionT>, change: StepChange<StepT>): boolean
	local callback = view._sequence.definition.onStep
	if callback == nil then
		return true
	end
	return view:_callUser(function()
		callback(view._context, change)
	end)
end

function Reconciliation.applyStep<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	step: StepT?,
	payload: unknown?,
	cause: DefTypes.StepChangeCause,
	direction: DefTypes.TraversalDirection?
): boolean
	local from = view._step
	view._step = step
	if step ~= nil then
		local compiledStep = view._sequence._compiledSteps[step]
		assert(compiledStep ~= nil, "Pulse step disappeared from a compiled sequence")
		local run = compiledStep.definition.run
		if run ~= nil and not view:_callUser(function()
			run(view._context, payload)
		end) then
			return false
		end
	end
	if not isAliveStatus(view._status) then
		return false
	end
	return emitStep(view, {
		from = from,
		to = step,
		payload = payload,
		cause = cause,
		direction = direction,
	})
end

local function processForwardEvent<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	event: CompiledEvent<StepT>,
	loopIndex: number
): boolean
	local definition = event.definition
	local targetStep = definition.step
	if targetStep ~= nil then
		local allowed = Reconciliation.canStep(view, targetStep, nil)
		if not isAliveStatus(view._status) then
			return false
		end
		local key = journalKey(event, loopIndex)
		if not allowed then
			view._journal[key] = {
				state = "blocked",
				from = view._step,
				to = targetStep,
				payload = nil,
			}
			return true
		end

		local from = view._step
		if not Reconciliation.applyStep(view, targetStep, nil, "event", "forward") then
			return false
		end
		local run = definition.run
		if run ~= nil and not view:_callUser(function()
			run(view._context)
		end) then
			return false
		end
		if not isAliveStatus(view._status) then
			return false
		end
		view._journal[key] = {
			state = "applied",
			from = from,
			to = targetStep,
			payload = nil,
		}
		return true
	end

	local run = definition.run
	if run ~= nil then
		return view:_callUser(function()
			run(view._context)
		end)
	end
	return true
end

local function processReverseEvent<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	event: CompiledEvent<StepT>,
	loopIndex: number
): boolean
	local definition = event.definition
	local targetStep = definition.step
	if targetStep == nil then
		local reverse = event.reverse
		if reverse == "cancel" then
			view:_terminate("cancelled", "reverseEventUnavailable", nil)
			return false
		elseif reverse == "ignore" then
			return true
		end
		return view:_callUser(function()
			(reverse :: (Context<StepT>) -> ())(view._context)
		end)
	end

	local key = journalKey(event, loopIndex)
	local occurrence = view._journal[key]
	if occurrence == nil then
		view:_terminate("cancelled", "missingReverseHistory", nil)
		return false
	end
	if occurrence.state == "blocked" then
		view._journal[key] = nil
		return true
	end
	if view._step ~= occurrence.to then
		view:_terminate("cancelled", "stepHistoryDiverged", nil)
		return false
	end

	local eventReverse = event.reverse
	local compiledStep = view._sequence._compiledSteps[targetStep]
	assert(compiledStep ~= nil, "Pulse step disappeared from a compiled sequence")
	local stepReverse = compiledStep.reverse
	if eventReverse == "cancel" then
		view:_terminate("cancelled", "reverseEventUnavailable", nil)
		return false
	end
	if stepReverse == "cancel" then
		view:_terminate("cancelled", "reverseStepUnavailable", nil)
		return false
	end

	if
		eventReverse ~= "ignore"
		and not view:_callUser(function()
			(eventReverse :: (Context<StepT>) -> ())(view._context)
		end)
	then
		return false
	end
	if
		stepReverse ~= "ignore"
		and not view:_callUser(function()
			(stepReverse :: (Context<StepT>, unknown?) -> ())(view._context, occurrence.payload)
		end)
	then
		return false
	end
	if not isAliveStatus(view._status) then
		return false
	end

	local previous = view._step
	view._step = occurrence.from
	if
		not emitStep(view, {
			from = previous,
			to = occurrence.from,
			payload = occurrence.payload,
			cause = "event",
			direction = "backward",
		})
	then
		return false
	end
	view._journal[key] = nil
	return true
end

local function fireLoopObservers<StepT, PhaseT, DirectionT>(view: ReconciliationView<StepT, PhaseT, DirectionT>, change: DefTypes.LoopChange)
	local snapshot = snapshotListeners(view._callbacks.looped)
	for _, callback in snapshot do
		view:_callObserver(function()
			callback(change)
		end)
	end
end

local function processLoop<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	action: Action<StepT>,
	direction: DefTypes.TraversalDirection
): boolean
	local change: DefTypes.LoopChange
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
	local callback = view._sequence.definition.onLoop
	if callback ~= nil and not view:_callUser(function()
		callback(view._context, change)
	end) then
		return false
	end
	if not isAliveStatus(view._status) then
		return false
	end
	fireLoopObservers(view, change)
	return isAliveStatus(view._status)
end

local function processAction<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	action: Action<StepT>,
	direction: DefTypes.TraversalDirection
): boolean
	if action.kind == "loop" then
		return processLoop(view, action, direction)
	end
	local event = action.event
	assert(event ~= nil, "Pulse event action invariant failed")
	if direction == "forward" then
		return processForwardEvent(view, event, action.loopIndex)
	end
	return processReverseEvent(view, event, action.loopIndex)
end

local function processCurrentCoordinate<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	direction: DefTypes.TraversalDirection,
	work: WorkState
): boolean
	local actions = Timeline.actionsAt(view._sequence, view._position)
	while isAliveStatus(view._status) do
		local actionIndex = if direction == "forward" then view._boundaryStage + 1 else view._boundaryStage
		if actionIndex < 1 or actionIndex > #actions then
			return true
		end
		if work.count >= MAX_RECONCILE_WORK then
			view:_terminate("failed", "catchUpLimitExceeded", "Pulse reconciliation work limit exceeded")
			return false
		end
		work.count += 1
		local generation = view._mutationGeneration
		if not processAction(view, actions[actionIndex], direction) then
			return false
		end
		if direction == "forward" then
			view._boundaryStage += 1
		else
			view._boundaryStage -= 1
		end
		view:_flushMutations()
		if view._mutationGeneration ~= generation and not view._pendingReconcile then
			view._pendingReconcile = true
			view._pendingClockPosition = Scheduling.readClock(view).timePosition
		end
		if view._mutationGeneration ~= generation or view._pendingReconcile then
			return false
		end
	end
	return false
end

local function reconcileToward<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	target: number,
	direction: DefTypes.TraversalDirection,
	work: WorkState
): boolean
	if view._sequence.loop then
		local duration = view._sequence.duration
		assert(duration ~= nil and duration > 0, "Pulse loop duration invariant failed")
		local targetLoop = math.floor(target / duration)
		local adjacentLoop = if targetLoop >= 0 then targetLoop + 1 else targetLoop - 1
		if math.abs(targetLoop) > MAX_EXACT_INTEGER or targetLoop * duration == adjacentLoop * duration then
			view:_terminate("failed", "loopIdentityExceeded", "Pulse loop identity is no longer exactly representable")
			return false
		end
	end

	if not processCurrentCoordinate(view, direction, work) then
		return false
	end
	while isAliveStatus(view._status) do
		local coordinate = Timeline.nextCheckpoint(view._sequence, view._position, direction)
		if
			coordinate == nil
			or (direction == "forward" and coordinate > target)
			or (direction == "backward" and coordinate < target)
		then
			if view._position ~= target then
				view._position = target
				view._boundaryStage = 0
			end
			break
		end
		view._position = coordinate
		local actions = Timeline.actionsAt(view._sequence, coordinate)
		view._boundaryStage = if direction == "forward" then 0 else #actions
		if not processCurrentCoordinate(view, direction, work) then
			return false
		end
		if coordinate == target then
			break
		end
	end

	if not isAliveStatus(view._status) then
		return false
	end
	local duration = view._sequence.duration
	if not view._sequence.loop and duration ~= nil then
		if
			(direction == "forward" and view._position >= duration)
			or (direction == "backward" and view._position <= 0)
		then
			view:_terminate("completed", "completed", nil)
			return false
		end
	end
	return true
end

local function expectedTraversalDirection<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	clockRate: number,
	observedDirection: DirectionT?
): DefTypes.TraversalDirection?
	local clockSign = sign(clockRate)
	if observedDirection ~= nil then
		if observedDirection == view._directions.forward then
			clockSign = 1
		elseif observedDirection == view._directions.backward then
			clockSign = -1
		else
			view:_terminate("failed", "invalidClockDirection", nil)
			return nil
		end
	end
	local sequenceSign = clockSign * sign(view._playbackSpeed)
	if sequenceSign > 0 then
		return "forward"
	elseif sequenceSign < 0 then
		return "backward"
	end
	return nil
end

local function processClockChange<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	pending: PendingClockChange,
	work: WorkState
): boolean
	if view._clock:isDestroyed() then
		view:_terminate("destroyed", "clockDestroyed", nil)
		return false
	end

	if pending.stage == "catchUp" then
		local target = Scheduling.sequenceAtClock(view, pending.sample.timePosition)
		if target == nil then
			return false
		end
		local traversal: DefTypes.TraversalDirection?
		if target > view._position then
			traversal = "forward"
		elseif target < view._position then
			traversal = "backward"
		else
			traversal = expectedTraversalDirection(view, view._lastClockRate, nil)
		end
		if traversal ~= nil then
			local workCountBefore = work.count
			local reconciled = reconcileToward(view, target, traversal, work)
			if work.count > workCountBefore then
				pending.requiresRefresh = true
			end
			if not reconciled then
				return false
			end
		else
			view._position = target
		end

		local previousRateSign = sign(view._lastClockRate)
		local currentRateSign = sign(pending.sample.rate)
		view._lastClockRate = pending.sample.rate
		if currentRateSign == previousRateSign then
			view._scheduleRefreshPending = view._scheduleRefreshPending or pending.requiresRefresh
			view._activeClockChange = nil
			return true
		end

		view._anchorClock = pending.sample.timePosition
		view._anchorSequence = target
		view._position = target
		Scheduling.cancelTask(view)
		view._scheduleRefreshPending = true
		pending.stage = "reorient"
	end

	local traversal: DefTypes.TraversalDirection? = expectedTraversalDirection(view, view._lastClockRate, nil)
	if traversal ~= nil and not reconcileToward(view, view._position, traversal, work) then
		return false
	end
	view._activeClockChange = nil
	return true
end

local function runUpdates<StepT, PhaseT, DirectionT>(view: ReconciliationView<StepT, PhaseT, DirectionT>)
	if view._status ~= "playing" then
		return
	end
	local delta = view._position - view._lastContinuousPosition
	if not isFinite(delta) then
		view:_terminate("failed", "numericOverflow", "Pulse continuous sequence delta is non-finite")
		return
	end
	view._lastContinuousPosition = view._position
	local current = Timeline.localTimePosition(view)
	for _, update in view._sequence.updates do
		local generation = view._mutationGeneration
		if not view:_callUser(function()
			update.run(view._context, delta, current)
		end) then
			return
		end
		view:_flushMutations()
		if view._status ~= "playing" or view._mutationGeneration ~= generation then
			if view._status == "playing" and not view._pendingReconcile then
				local sample = Scheduling.readClock(view)
				if view._status == "playing" then
					view._pendingReconcile = true
					view._pendingClockPosition = sample.timePosition
				end
			end
			return
		end
	end
end

function Reconciliation.drain<StepT, PhaseT, DirectionT>(view: ReconciliationView<StepT, PhaseT, DirectionT>)
	if view._reconciling or view._callbackDepth > 0 or view._flushingMutations or view._status ~= "playing" then
		return
	end

	view._reconciling = true
	local work: WorkState = { count = 0 }
	while view._status == "playing" do
		if view._activeClockChange == nil and #view._queuedClockChanges == 0 and #view._queuedMutations > 0 then
			view:_flushMutations()
		end
		if view._activeClockChange == nil and #view._queuedClockChanges > 0 then
			view._activeClockChange = table.remove(view._queuedClockChanges, 1)
		end
		local activeClockChange = view._activeClockChange
		if activeClockChange ~= nil then
			processClockChange(view, activeClockChange, work)
		elseif view._pendingReconcile then
			view._pendingReconcile = false
			local pendingPosition = view._pendingClockPosition
			view._pendingClockPosition = nil
			local pendingObserved = view._pendingObservedDirection
			view._pendingObservedDirection = nil
			if pendingPosition == nil then
				pendingPosition = Scheduling.readClock(view).timePosition
			end
			if view._status ~= "playing" then
				break
			end
			local target = Scheduling.sequenceAtClock(view, pendingPosition :: number)
			if target == nil then
				break
			end
			local traversal: DefTypes.TraversalDirection?
			if target > view._position then
				traversal = "forward"
			elseif target < view._position then
				traversal = "backward"
			else
				traversal = expectedTraversalDirection(view, view._lastClockRate, pendingObserved)
			end
			if traversal ~= nil then
				reconcileToward(view, target, traversal, work)
			else
				view._position = target
			end
		elseif view._pendingUpdate then
			view._pendingUpdate = false
			runUpdates(view)
		else
			break
		end
	end
	view._reconciling = false
	if view._scheduleRefreshPending then
		view._scheduleRefreshPending = false
		if view._status == "playing" then
			view:_refreshScheduling()
		end
	end
end

function Reconciliation.request<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	clockPosition: number,
	shouldRunUpdates: boolean,
	observedDirection: DirectionT?
)
	if not isFinite(clockPosition) then
		view:_terminate("failed", "invalidClockSample", "Pulse phase/reached clock position must be finite")
		return
	end
	view._pendingReconcile = true
	view._pendingClockPosition = clockPosition
	view._pendingUpdate = view._pendingUpdate or shouldRunUpdates
	if observedDirection ~= nil then
		view._pendingObservedDirection = observedDirection
	end
	Reconciliation.drain(view)
end

function Reconciliation.enqueueClockChange<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<StepT, PhaseT, DirectionT>,
	sample: DefTypes.ClockSample
)
	table.insert(view._queuedClockChanges, {
		sample = sample,
		stage = "catchUp",
		requiresRefresh = false,
	})
	view._mutationGeneration += 1
end

function Reconciliation.reconcileClockChange<StepT, PhaseT, DirectionT>(
	view: ReconciliationView<
		StepT,
		PhaseT,
		DirectionT
	>,
	change: DefTypes.ClockChange
)
	if not isAliveStatus(view._status) then
		return
	end
	if view._clock:isDestroyed() then
		view:_terminate("destroyed", "clockDestroyed", nil)
		return
	end
	if view._status ~= "playing" then
		return
	end
	if change.discontinuous then
		view:_terminate("cancelled", "clockDiscontinuity", nil)
		return
	end
	local sample = Scheduling.readClock(view)
	if view._status ~= "playing" then
		return
	end
	if view._callbackDepth > 0 then
		table.insert(view._queuedMutations, function()
			if view._status == "playing" then
				Reconciliation.enqueueClockChange(view, sample)
			end
		end)
		return
	end
	Reconciliation.enqueueClockChange(view, sample)
	Reconciliation.drain(view)
end

function Reconciliation.runContinuous<StepT, PhaseT, DirectionT>(view: ReconciliationView<StepT, PhaseT, DirectionT>, now: number)
	if view._status ~= "playing" then
		return
	end
	Reconciliation.request(view, now, true, nil)
	if view._status == "playing" then
		view:_refreshScheduling()
	end
end

local module: ReconciliationModule = {
	canStep = Reconciliation.canStep,
	applyStep = Reconciliation.applyStep,
	enqueueClockChange = Reconciliation.enqueueClockChange,
	drain = Reconciliation.drain,
	request = Reconciliation.request,
	reconcileClockChange = Reconciliation.reconcileClockChange,
	runContinuous = Reconciliation.runContinuous,
}

return module
