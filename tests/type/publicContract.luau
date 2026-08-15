--!strict

local Types = require(script.Parent.Parent.pulse.pulse.types)
local Def = require(script.Parent.Parent.pulse.pulse.types.def)
local OwnershipTypes = require(script.Parent.Parent.pulse.pulse.types.internal.ownership)

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

local function proveNarrowOwnership(
	runtime: OwnershipTypes.RuntimeOwner,
	playback: OwnershipTypes.PlaybackOwned,
	change: Types.ClockChange
)
	runtime:_registerPlayback(playback)
	playback:_reconcileClockChange(change)
	playback:_runContinuous(change.currentTimePosition)
	runtime:_detachPlayback(playback)
	playback:_dispose()
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
	proveNarrowOwnership = proveNarrowOwnership,
	authorCanonicalRecords = authorCanonicalRecords,
	proveLifecycleRecords = proveLifecycleRecords,
}
