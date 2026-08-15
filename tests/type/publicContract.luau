--!strict

local Types = require(script.Parent.Parent.pulse.pulse.types)
local Def = require(script.Parent.Parent.pulse.pulse.types.def)
local RuntimeTypes = require(script.Parent.Parent.pulse.pulse.types.managers.runtimeManager)

type Direction = {
	name: "forward" | "backward",
}
type PhaseToken = {
	name: "render" | "simulation",
}
type PhaseInput = PhaseToken | "render" | "simulation"

type ProviderClockSample = {
	timePosition: number,
	rate: number,
	revision: number,
}
type ProviderClockChange = {
	previousTimePosition: number?,
	currentTimePosition: number,
	discontinuous: boolean,
	kind: string,
}
type ProviderClockReader = {
	read: (self: ProviderClockReader) -> ProviderClockSample,
	bindToChanged: (
		self: ProviderClockReader,
		callback: (change: ProviderClockChange) -> (),
		runInitially: boolean?
	) -> Types.Release,
	isDestroyed: (self: ProviderClockReader) -> boolean,
}
type ProviderClockScheduling<PhaseT> = {
	bindToReached: (
		self: ProviderClockScheduling<PhaseT>,
		timePosition: number,
		direction: Direction,
		callback: (now: number, direction: Direction) -> (),
		phase: PhaseT?
	) -> number,
	cancel: (self: ProviderClockScheduling<PhaseT>, id: number) -> boolean,
	rescheduleAt: (
		self: ProviderClockScheduling<PhaseT>,
		id: number,
		runAt: number,
		phase: PhaseT?
	) -> boolean,
	bindPhase: (
		self: ProviderClockScheduling<PhaseT>,
		phase: PhaseT,
		callback: Types.PhaseCallback
	) -> Types.Release,
}
type ProviderClock<PhaseT> = ProviderClockReader & ProviderClockScheduling<PhaseT> & {
	providerOnly: boolean,
}

type MinimalReader = {
	read: (self: MinimalReader) -> unknown,
	bindToChanged: (
		self: MinimalReader,
		callback: (change: unknown) -> (),
		runInitially: boolean?
	) -> Types.Release,
	isDestroyed: (self: MinimalReader) -> boolean,
}

local function acceptStructuralClock(clock: Types.Clock<PhaseInput, Direction>)
	local _sample: Types.ClockSample = Def.assertClockSample(clock:read())
end

local function proveProviderConformance(clock: ProviderClock<PhaseInput>)
	acceptStructuralClock(clock)
end

local function proveReaderConformance(reader: ProviderClockReader)
	local _reader: MinimalReader = reader
end

type AlphaStep = string
type AlphaPhase = "render"
type AlphaDirection = "positive" | "negative"
type BetaStep = number
type BetaPhase = {
	name: "simulation",
}
type BetaDirection = {
	sign: number,
}
type AuthorStep = "idle" | "active"

local function proveHeterogeneousRuntime(
	runtime: Types.Runtime,
	alphaSequence: Types.Sequence<AlphaStep>,
	alphaOptions: Types.PlaybackOptions<AlphaStep, AlphaPhase, AlphaDirection>,
	betaSequence: Types.Sequence<BetaStep>,
	betaOptions: Types.PlaybackOptions<BetaStep, BetaPhase, BetaDirection>
)
	local createAlpha: (
		Types.Runtime,
		Types.Sequence<AlphaStep>,
		Types.PlaybackOptions<AlphaStep, AlphaPhase, AlphaDirection>
	) -> Types.Playback<AlphaStep> =
		runtime.createPlayback
	local createBeta: (
		Types.Runtime,
		Types.Sequence<BetaStep>,
		Types.PlaybackOptions<BetaStep, BetaPhase, BetaDirection>
	) -> Types.Playback<BetaStep> =
		runtime.createPlayback
	local alphaPlayback = createAlpha(runtime, alphaSequence, alphaOptions)
	local betaPlayback = createBeta(runtime, betaSequence, betaOptions)
	alphaPlayback:setParam("payload", betaPlayback:getParam("payload"))
end

local function erasePlayback<StepT, PhaseT, DirectionT>(
	sequence: Types.Sequence<StepT>,
	options: Types.PlaybackOptions<StepT, PhaseT, DirectionT>
): RuntimeTypes.PlaybackOwned
	local clock = options.clock
	return {
		terminate = function(_status, _reason)
			local _sequence = sequence
		end,
		reconcileClockChange = function(change)
			local _sample: unknown = clock:read()
			local _continuous = not change.discontinuous
		end,
		runContinuous = function(_now)
			local _phase: PhaseT = options.phase
		end,
		dispose = function()
			local _direction: DirectionT = options.directions.forward
		end,
	}
end

local function makeClockPort<PhaseT, DirectionT>(clock: Types.Clock<PhaseT, DirectionT>): RuntimeTypes.ClockStatePort
	return {
		sameClock = function(candidate: unknown): boolean
			return candidate == clock
		end,
		bindChanged = function(callback, _invalid): Types.Release
			return clock:bindToChanged(function(rawChange: unknown)
				callback(Def.assertClockChange(rawChange))
			end, false)
		end,
		isDestroyed = function(): boolean
			return clock:isDestroyed()
		end,
	}
end

local function makePhasePort<PhaseT, DirectionT>(clock: Types.Clock<PhaseT, DirectionT>, phase: PhaseT): RuntimeTypes.PhaseGroupPort
	return {
		samePhase = function(candidate: unknown): boolean
			return candidate == phase
		end,
		bind = function(callback): Types.Release
			return clock:bindPhase(phase, callback)
		end,
	}
end

local function proveErasedOwners<StepA, PhaseA, DirectionA, StepB, PhaseB, DirectionB>(
	sequenceA: Types.Sequence<StepA>,
	optionsA: Types.PlaybackOptions<
		StepA,
		PhaseA,
		DirectionA
	>,
	sequenceB: Types.Sequence<StepB>,
	optionsB: Types.PlaybackOptions<
		StepB,
		PhaseB,
		DirectionB
	>
): { RuntimeTypes.PlaybackOwned }
	return {
		erasePlayback(sequenceA, optionsA),
		erasePlayback(sequenceB, optionsB),
	}
end

local function authorCanonicalRecords(builder: Types.Builder<AuthorStep>)
	builder
		:addressPolicy("rebuild")
		:step("active", {
			time = 0,
			reverse = "ignore",
		})
		:event({
			time = 0,
			step = "active",
			reverse = "cancel",
		})
		:update({
			name = "sample",
			run = function(ctx, _dt, _timePosition)
				local payload: unknown = ctx:getParam("payload")
				ctx:setParam("payload", payload)
			end,
		})
		:onRebuild(function(_ctx, _request)
			return { step = "idle" }
		end)
end

local function proveLifecycleRecords(
	ctx: Types.Context<AuthorStep>,
	realTimeScheduler: Types.RealTimeScheduler
): Types.Completion
	local address: Types.SequenceAddress = {
		timePosition = 0.5,
		loopIndex = -1,
	}
	local position: Types.PlaybackPosition = {
		timePosition = 0.5,
		loopIndex = -1,
		unwrappedTimePosition = -0.5,
	}
	local loopChange: Types.LoopChange = {
		fromLoopIndex = -1,
		toLoopIndex = 0,
		direction = "forward" :: Types.TraversalDirection,
	}
	local stepChange: Types.StepChange<AuthorStep> = {
		from = "idle",
		to = "active",
		payload = ctx:getParam("payload"),
		cause = "event" :: Types.StepChangeCause,
		direction = "forward" :: Types.TraversalDirection,
	}
	local rebuildRequest: Types.RebuildRequest = {
		from = position,
		to = position,
		cause = "manualSeek" :: Types.AddressCause,
		direction = "stationary" :: Types.AddressDirection,
	}
	local config: Types.RuntimeConfig = {
		realTimeScheduler = realTimeScheduler,
	}
	local release: Types.Release = realTimeScheduler:delay(0, function() end)
	release()
	ctx:seek(address)

	local records = {
		loopChange = loopChange,
		stepChange = stepChange,
		rebuildRequest = rebuildRequest,
		config = config,
	}
	return {
		status = "cancelled" :: Types.TerminalStatus,
		reason = "fixture",
		error = records,
	}
end

return {
	acceptStructuralClock = acceptStructuralClock,
	proveProviderConformance = proveProviderConformance,
	proveReaderConformance = proveReaderConformance,
	proveHeterogeneousRuntime = proveHeterogeneousRuntime,
	erasePlayback = erasePlayback,
	makeClockPort = makeClockPort,
	makePhasePort = makePhasePort,
	proveErasedOwners = proveErasedOwners,
	authorCanonicalRecords = authorCanonicalRecords,
	proveLifecycleRecords = proveLifecycleRecords,
}
