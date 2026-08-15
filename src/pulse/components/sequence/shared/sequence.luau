--!strict
--!optimize 2
--!native

local SequenceTypes = require(script.Parent.Parent.Parent.Parent.types.components.sequence)

type Params = SequenceTypes.Params
type AddressPolicy = SequenceTypes.AddressPolicy
type Event<StepT> = SequenceTypes.Event<StepT>
type Step<StepT> = SequenceTypes.Step<StepT>
type Steps<StepT> = SequenceTypes.Steps<StepT>
type TransitionRule<StepT> = SequenceTypes.TransitionRule<StepT>
type Update<StepT> = SequenceTypes.Update<StepT>
type SignalHandler<StepT> = SequenceTypes.SignalHandler<StepT>
type ReverseEventAction<StepT> = SequenceTypes.ReverseEventAction<StepT>
type ReverseStepAction<StepT> = SequenceTypes.ReverseStepAction<StepT>
type CompiledEvent<StepT> = SequenceTypes.CompiledEvent<StepT>
type CompiledStep<StepT> = SequenceTypes.CompiledStep<StepT>
type Definition<StepT> = SequenceTypes.Definition<StepT>
type Sequence<StepT> = SequenceTypes.Sequence<StepT>
type SequenceImpl<StepT> = SequenceTypes.SequenceImpl<StepT>
type SequenceAddress = SequenceTypes.SequenceAddress
type PlaybackPosition = SequenceTypes.PlaybackPosition

type SequenceModule = {
	compile: <StepT>(definition: Definition<StepT>) -> Sequence<StepT>,
	validateAddress: <StepT>(sequence: Sequence<StepT>, address: SequenceAddress) -> PlaybackPosition,
}

local MAX_EXACT_INTEGER = 9_007_199_254_740_991

local Sequence = {}

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function assertFiniteNonNegative(value: number, label: string)
	assert(isFinite(value) and value >= 0, `Pulse {label} must be a finite non-negative number`)
end

local function assertWithinDuration(value: number, duration: number?, label: string)
	if duration ~= nil then
		assert(value <= duration, `Pulse {label} must not exceed the sequence duration`)
	end
end

local function assertDenseArray<T>(values: { T }, label: string)
	local count = 0
	for index in values do
		assert(
			type(index) == "number" and index >= 1 and index % 1 == 0,
			`Pulse {label} must use positive integer keys`
		)
		count += 1
	end
	for index = 1, count do
		assert(values[index] ~= nil, `Pulse {label} must be a dense array`)
	end
end

local function resolveEventReverse<StepT>(event: Event<StepT>): ReverseEventAction<StepT>
	local reverse = event.reverse
	if reverse == nil then
		return if event.run == nil then "ignore" :: ReverseEventAction<StepT> else "cancel" :: ReverseEventAction<StepT>
	end

	assert(
		type(reverse) == "function" or reverse == "ignore" or reverse == "cancel",
		"Pulse event reverse must be a callback, 'ignore', or 'cancel'"
	)
	return reverse :: ReverseEventAction<StepT>
end

local function resolveStepReverse<StepT>(step: Step<StepT>): ReverseStepAction<StepT>
	local reverse = step.reverse
	if reverse == nil then
		return if step.run == nil then "ignore" :: ReverseStepAction<StepT> else "cancel" :: ReverseStepAction<StepT>
	end

	assert(
		type(reverse) == "function" or reverse == "ignore" or reverse == "cancel",
		"Pulse step reverse must be a callback, 'ignore', or 'cancel'"
	)
	return reverse :: ReverseStepAction<StepT>
end

local function copyParams(params: Params?): Params
	local copy: Params = {}
	if params ~= nil then
		for name, value in params do
			copy[name] = value
		end
	end
	return table.freeze(copy)
end

local function copyEvents<StepT>(events: { Event<StepT> }?, duration: number?): { CompiledEvent<StepT> }
	local compiled: { CompiledEvent<StepT> } = {}
	if events == nil then
		return table.freeze(compiled)
	end
	assertDenseArray(events, "events")

	for authorIndex, event in events do
		assertFiniteNonNegative(event.time, `event #{authorIndex} time`)
		assertWithinDuration(event.time, duration, `event #{authorIndex} time`)
		assert(event.run == nil or type(event.run) == "function", `Pulse event #{authorIndex} run must be a callback`)

		local reverse: ReverseEventAction<StepT> = resolveEventReverse(event)
		local definition: Event<StepT> = table.freeze({
			time = event.time,
			name = event.name,
			step = event.step,
			run = event.run,
			reverse = reverse :: ReverseEventAction<StepT>,
		})
		local record: CompiledEvent<StepT> = table.freeze({
			_identity = authorIndex,
			_authorIndex = authorIndex,
			definition = definition,
			reverse = reverse :: ReverseEventAction<StepT>,
		})
		table.insert(compiled, record)
	end

	table.sort(compiled, function(left, right)
		if left.definition.time == right.definition.time then
			return left._authorIndex < right._authorIndex
		end
		return left.definition.time < right.definition.time
	end)

	return table.freeze(compiled)
end

local function copySteps<StepT>(steps: Steps<StepT>?, duration: number?): (Steps<StepT>, { [StepT]: CompiledStep<StepT> })
	local publicSteps: Steps<StepT> = {}
	local compiledSteps: { [StepT]: CompiledStep<StepT> } = {}
	if steps == nil then
		return table.freeze(publicSteps), table.freeze(compiledSteps)
	end

	for stepId, step in steps do
		assertFiniteNonNegative(step.time, "step time")
		assertWithinDuration(step.time, duration, "step time")
		assert(step.run == nil or type(step.run) == "function", "Pulse step run must be a callback")
		assert(step.canEnter == nil or type(step.canEnter) == "function", "Pulse step canEnter must be a callback")

		local reverse: ReverseStepAction<StepT> = resolveStepReverse(step)
		local definition: Step<StepT> = table.freeze({
			time = step.time,
			run = step.run,
			reverse = reverse :: ReverseStepAction<StepT>,
			canEnter = step.canEnter,
		})
		publicSteps[stepId] = definition
		compiledSteps[stepId] = table.freeze({
			definition = definition,
			reverse = reverse :: ReverseStepAction<StepT>,
		})
	end

	return table.freeze(publicSteps), table.freeze(compiledSteps)
end

local function copyTransitions<StepT>(transitions: { TransitionRule<StepT> }?, duration: number?): { TransitionRule<StepT> }
	local copy: { TransitionRule<StepT> } = {}
	if transitions == nil then
		return table.freeze(copy)
	end
	assertDenseArray(transitions, "transitions")

	for index, rule in transitions do
		if rule.after ~= nil then
			assertFiniteNonNegative(rule.after, `transition #{index} after`)
			assertWithinDuration(rule.after, duration, `transition #{index} after`)
		end
		if rule.before ~= nil then
			assertFiniteNonNegative(rule.before, `transition #{index} before`)
			assertWithinDuration(rule.before, duration, `transition #{index} before`)
		end
		if rule.after ~= nil and rule.before ~= nil then
			assert(rule.after <= rule.before, `Pulse transition #{index} after must not exceed before`)
		end
		assert(
			rule.canStep == nil or type(rule.canStep) == "function",
			`Pulse transition #{index} canStep must be a callback`
		)

		local copiedRule: TransitionRule<StepT> = table.freeze({
			from = rule.from,
			to = rule.to,
			after = rule.after,
			before = rule.before,
			canStep = rule.canStep,
		})
		table.insert(copy, copiedRule)
	end

	return table.freeze(copy)
end

local function copyUpdates<StepT>(updates: { Update<StepT> }?): { Update<StepT> }
	local copy: { Update<StepT> } = {}
	if updates == nil then
		return table.freeze(copy)
	end
	assertDenseArray(updates, "updates")

	for index, update in updates do
		assert(type(update.run) == "function", `Pulse update #{index} run must be a callback`)
		local copiedUpdate: Update<StepT> = table.freeze({
			name = update.name,
			run = update.run,
		})
		table.insert(copy, copiedUpdate)
	end

	return table.freeze(copy)
end

local function copySignals<StepT>(signals: { [string]: SignalHandler<StepT> }?): { [string]: SignalHandler<StepT> }
	local copy: { [string]: SignalHandler<StepT> } = {}
	if signals ~= nil then
		for name, handler in signals do
			assert(type(handler) == "function", `Pulse signal '{name}' must be a callback`)
			copy[name] = handler
		end
	end
	return table.freeze(copy)
end

local function copyPublicEvents<StepT>(compiled: { CompiledEvent<StepT> }): { Event<StepT> }
	local events: { Event<StepT> } = table.create(#compiled)
	for index, record in compiled do
		events[index] = record.definition
	end
	return table.freeze(events)
end

local function reverseCompiledEvents<StepT>(forward: { CompiledEvent<StepT> }): { CompiledEvent<StepT> }
	local reverse: { CompiledEvent<StepT> } = table.create(#forward)
	for index = #forward, 1, -1 do
		table.insert(reverse, forward[index])
	end
	return table.freeze(reverse)
end

local function validateAddressPolicy(policy: AddressPolicy?): AddressPolicy
	local resolved: AddressPolicy = if policy == nil then "cancel" :: AddressPolicy else policy
	assert(
		resolved == "cancel" or resolved == "skip" or resolved == "rebuild",
		"Pulse addressPolicy must be 'cancel', 'skip', or 'rebuild'"
	)
	return resolved
end

function Sequence.compile<StepT>(definition: Definition<StepT>): Sequence<StepT>
	local duration = definition.duration
	if duration ~= nil then
		assertFiniteNonNegative(duration, "duration")
	end

	local loop = definition.loop == true
	if loop then
		assert(duration ~= nil and duration > 0, "Pulse looped sequences require a finite positive duration")
	end

	local cleanupDelay = definition.cleanupDelay or 0
	assertFiniteNonNegative(cleanupDelay, "cleanupDelay")

	local addressPolicy: AddressPolicy = validateAddressPolicy(definition.addressPolicy)
	if addressPolicy == "rebuild" then
		assert(definition.onRebuild ~= nil, "Pulse rebuild addressPolicy requires onRebuild")
	end

	local forwardEvents: { CompiledEvent<StepT> } = copyEvents(definition.events, duration)
	local reverseEvents: { CompiledEvent<StepT> } = reverseCompiledEvents(forwardEvents)
	local events: { Event<StepT> } = copyPublicEvents(forwardEvents)
	local steps: Steps<StepT>
	local compiledSteps: { [StepT]: CompiledStep<StepT> }
	steps, compiledSteps = copySteps(definition.steps, duration)
	local transitions: { TransitionRule<StepT> } = copyTransitions(definition.transitions, duration)
	local updates: { Update<StepT> } = copyUpdates(definition.updates)
	local signals: { [string]: SignalHandler<StepT> } = copySignals(definition.signals)
	local defaultParams = copyParams(definition.params)

	local compiledDefinition: Definition<StepT> = table.freeze({
		duration = duration,
		cleanupDelay = cleanupDelay,
		addressPolicy = addressPolicy :: AddressPolicy,
		loop = loop,
		params = defaultParams,
		steps = steps,
		transitions = transitions,
		events = events,
		updates = updates,
		signals = signals,
		onPlay = definition.onPlay,
		onStop = definition.onStop,
		onCancel = definition.onCancel,
		onDestroy = definition.onDestroy,
		onRebuild = definition.onRebuild,
		onLoop = definition.onLoop,
		onStep = definition.onStep,
		onParamChanged = definition.onParamChanged,
	})

	local sequence: SequenceImpl<StepT> = table.freeze({
		duration = duration,
		cleanupDelay = cleanupDelay,
		addressPolicy = addressPolicy :: AddressPolicy,
		loop = loop,
		defaultParams = defaultParams,
		steps = steps,
		transitions = transitions,
		events = events,
		updates = updates,
		signals = signals,
		definition = compiledDefinition,
		_forwardEvents = forwardEvents,
		_reverseEvents = reverseEvents,
		_compiledSteps = compiledSteps,
	})

	return sequence
end

function Sequence.validateAddress<StepT>(sequence: Sequence<StepT>, address: SequenceAddress): PlaybackPosition
	local timePosition = address.timePosition
	assertFiniteNonNegative(timePosition, "address timePosition")

	local duration = sequence.duration
	if duration ~= nil then
		assert(timePosition <= duration, "Pulse address timePosition must not exceed the sequence duration")
	end

	local loopIndex = address.loopIndex or 0
	assert(
		isFinite(loopIndex) and loopIndex % 1 == 0 and math.abs(loopIndex) <= MAX_EXACT_INTEGER,
		"Pulse address loopIndex must be an exactly representable finite integer"
	)
	if not sequence.loop then
		assert(loopIndex == 0, "Pulse non-looping sequences only accept loopIndex zero")
	end

	local unwrappedTimePosition = timePosition
	if sequence.loop then
		assert(duration ~= nil and duration > 0, "Pulse compiled loop duration invariant failed")
		local loopBase = loopIndex * duration
		local adjacentBase = (if loopIndex >= 0 then loopIndex + 1 else loopIndex - 1) * duration
		assert(
			isFinite(loopBase) and isFinite(adjacentBase) and adjacentBase ~= loopBase,
			"Pulse loop address loses exact loop identity"
		)
		unwrappedTimePosition = loopBase + timePosition
		assert(isFinite(unwrappedTimePosition), "Pulse loop address must produce a finite unwrapped position")
	end

	return {
		timePosition = timePosition,
		loopIndex = loopIndex,
		unwrappedTimePosition = unwrappedTimePosition,
	}
end

local module: SequenceModule = {
	compile = Sequence.compile,
	validateAddress = Sequence.validateAddress,
}

return module
