--!strict

local Pulse = require(script.Parent.Parent.pulse)

type Phase = "presentation"
type DirectionToken = {
	name: "forward" | "backward",
}

type ProviderSample = {
	timePosition: number,
	rate: number,
	revision: number,
	epoch: number,
}

type ProviderChange = {
	kind: string,
	previousTimePosition: number?,
	currentTimePosition: number,
	discontinuous: boolean,
	revision: number,
}

type Provider = {
	read: (self: Provider) -> ProviderSample,
	bindToChanged: (self: Provider, callback: (change: ProviderChange) -> (), runInitially: boolean?) -> Pulse.Release,
	isDestroyed: (self: Provider) -> boolean,
	bindToReached: (
		self: Provider,
		position: number,
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

local function proveCoreContract(): Pulse.Completion?
	local definition: Pulse.SequenceDefinition<InvocationContext> = {
		duration = 2,
		events = {
			{
				time = 1,
				run = function(playback: Pulse.PlaybackControl, context: InvocationContext)
					local _actorId: number = context.actorId
					playback:addCleanup(function() end)
				end,
				reverse = function(playback: Pulse.PlaybackControl, context: InvocationContext)
					local _worldPosition: Vector3 = context.worldPosition
					playback:seek({ timePosition = 0 }, "skip")
				end,
			},
		},
		samples = {
			{
				startTime = 0,
				endTime = 2,
				run = function(playback: Pulse.PlaybackControl, sample: Pulse.SampleInfo, context: InvocationContext)
					local _status: Pulse.Status = playback:getStatus()
					local _rate: number = sample.rate
					local _position: Pulse.PlaybackPositionSnapshot = sample.position
					local _actorId: number = context.actorId
				end,
			},
		},
		onAddress = function(playback, info, context)
			local _cause: Pulse.AddressCause = info.cause
			local _mode: Pulse.AddressMode = info.mode
			local _target: Pulse.PlaybackPositionSnapshot = info.target
			local _actorId: number = context.actorId
			local _status: Pulse.Status = playback:getStatus()
		end,
	}
	local sequence = Pulse.sequence(definition)
	local playback: Pulse.Playback = Pulse.playback(sequence, {
		actorId = 42,
		worldPosition = Vector3.zero,
	}, {
		playbackSpeed = 1,
		position = { timePosition = 0 },
		initialMode = "reconstruct",
	})
	local output: Pulse.PlaybackPosition = { timePosition = 0, loopIndex = 0, unwrappedTimePosition = 0 }
	playback:writePositionInto(output)
	local initial: Pulse.TimeSample = { position = 100, rate = 1 }
	playback:play(initial)
	playback:evaluate({ position = 100.5, rate = 1 })
	playback:pause()
	playback:resume()
	playback:evaluate({ position = 200, rate = 1 })
	playback:setPlaybackSpeed(2)
	playback:seek({ timePosition = 0.25 }, "reconstruct")
	playback:cancel("fixture")
	return playback:getCompletion()
end

local function proveDriverContract(
	provider: Provider,
	directions: Pulse.DirectionTokens<DirectionToken>
): Pulse.DrivenPlayback
	-- Bind a concrete provider at the host boundary; the adapter owns no clock.
	local structuralProvider: Pulse.ProviderClock<Phase, DirectionToken> = {
		read = function()
			return provider:read()
		end,
		bindToChanged = function(_, callback, initially)
			return provider:bindToChanged(callback, initially)
		end,
		isDestroyed = function()
			return provider:isDestroyed()
		end,
		bindToReached = function(_, position, direction, callback, phase)
			return provider:bindToReached(position, direction, callback, phase)
		end,
		cancel = function(_, id)
			return provider:cancel(id)
		end,
		rescheduleAt = function(_, id, position, phase)
			return provider:rescheduleAt(id, position, phase)
		end,
		bindPhase = function(_, phase, callback)
			return provider:bindPhase(phase, callback)
		end,
	}
	local driver: Pulse.ClockDriver = Pulse.clockDriver(structuralProvider, "presentation" :: Phase, directions)
	local definition: Pulse.SequenceDefinition<nil> = { duration = 1 }
	local sequence: Pulse.Sequence<nil> = Pulse.sequence(definition)
	local playback = Pulse.playback(sequence, nil)
	local driven = driver:attach(playback, {
		discontinuityMode = "skip",
	})
	driven:play()
	driven:setPlaybackSpeed(0.5)
	driven:seek({ timePosition = 0.25 }, "reconstruct")
	driven:pause()
	driven:resume()
	return driven
end

local function proveBuilderContract(): Pulse.Sequence<InvocationContext>
	local makeBuilder = Pulse.builder :: () -> Pulse.SequenceBuilder<InvocationContext>
	local builder = makeBuilder()
	return builder
		:duration(1)
		:loop()
		:event({
			time = 0.5,
			run = function(_playback, _context) end,
		})
		:sample({
			run = function(_playback, _sample, _context) end,
		})
		:onPlay(function(_playback, _context) end)
		:onAddress(function(_playback, _info, _context) end)
		:onLoop(function(_playback, _change, _context) end)
		:compile()
end

return {
	proveCoreContract = proveCoreContract,
	proveDriverContract = proveDriverContract,
	proveBuilderContract = proveBuilderContract,
}
