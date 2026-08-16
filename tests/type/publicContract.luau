--!strict

local Pulse = require(script.Parent.Parent.pulse)

type Phase = "presentation"
type DirectionToken = {
	name: "forward" | "backward",
}

type ProviderMapping = {
	effectiveRate: number,
	revision: number,
}

type ProviderSample = {
	timePosition: number,
	rate: number,
	revision: number,
	dataRevision: number,
	epoch: number,
}

type ProviderChange = {
	kind: string,
	previous: ProviderMapping?,
	current: ProviderMapping,
	previousTimePosition: number?,
	currentTimePosition: number,
	discontinuous: boolean,
}

type Provider = {
	read: (self: Provider) -> ProviderSample,
	bindToChanged: (
		self: Provider,
		callback: (change: ProviderChange) -> (),
		runInitially: boolean?
	) -> Pulse.Release,
	isDestroyed: (self: Provider) -> boolean,
	bindToReached: (
		self: Provider,
		timePosition: number,
		direction: DirectionToken,
		callback: (now: number, direction: DirectionToken) -> (),
		phase: Phase
	) -> number,
	cancel: (self: Provider, id: number) -> boolean,
	rescheduleAt: (self: Provider, id: number, runAt: number, phase: Phase) -> boolean,
	bindPhase: (self: Provider, phase: Phase, callback: (clockDt: number, now: number) -> ()) -> Pulse.Release,
}

type InvocationContext = {
	actorId: number,
	worldPosition: Vector3,
}

local function provePublicContract(
	provider: Provider,
	directions: Pulse.DirectionTokens<DirectionToken>
): Pulse.Completion?
	local structuralProvider: Pulse.ProviderClock<Phase, DirectionToken> = provider
	local adapter = Pulse.temporalAdapter(structuralProvider, "presentation", directions)
	local definition: Pulse.SequenceDefinition<InvocationContext> = {
		duration = 2,
		addressPolicy = "rebuild",
		events = {
			{
				time = 1,
				run = function(playback: Pulse.PlaybackContext, context: InvocationContext)
					local _actorId: number = context.actorId
					playback:addCleanup(function() end)
				end,
				reverse = function(playback: Pulse.PlaybackContext, context: InvocationContext)
					local _worldPosition: Vector3 = context.worldPosition
					local address: Pulse.SequenceAddress = { timePosition = 0 }
					playback:seek(address)
				end,
			},
		},
		updates = {
			{
				startTime = 0,
				endTime = 2,
				run = function(
					playback: Pulse.PlaybackContext,
					clockDt: number,
					timePosition: number,
					context: InvocationContext
				)
					local _status: Pulse.Status = playback:getStatus()
					local _delta: number = clockDt
					local _position: number = timePosition
					local _actorId: number = context.actorId
				end,
			},
		},
	}
	local sequence = Pulse.sequence(definition)
	local playback: Pulse.Playback = Pulse.playback(sequence, adapter, {
		actorId = 42,
		worldPosition = Vector3.zero,
	}, {
		playbackSpeed = 1,
		position = { timePosition = 0 },
	})
	local releaseEnded: Pulse.Release = playback:onEnded(function(completion)
		local _terminal: Pulse.TerminalStatus = completion.status
	end)
	local releaseLooped: Pulse.Release = playback:onLooped(function(change)
		local _direction: Pulse.TraversalDirection = change.direction
	end)
	playback:play():pause()
	playback:resume()
	playback:setPlaybackSpeed(2)
	playback:cancel("fixture")
	releaseLooped()
	releaseEnded()
	adapter:destroy()
	return playback:getCompletion()
end

local function proveBuilderContract(): Pulse.Sequence<InvocationContext>
	local builder: Pulse.Builder<InvocationContext> = Pulse.builder()
	return builder
		:duration(1)
		:loop()
		:addressPolicy("skip")
		:event({
			time = 0.5,
			run = function(_playback, _context) end,
		})
		:update({
			run = function(_playback, _dt, _timePosition, _context) end,
		})
		:onPlay(function(_playback, _context) end)
		:onLoop(function(_playback, _change, _context) end)
		:compile()
end

return {
	provePublicContract = provePublicContract,
	proveBuilderContract = proveBuilderContract,
}
