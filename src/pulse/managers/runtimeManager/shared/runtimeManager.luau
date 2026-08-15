--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local RuntimeTypes = require(script.Parent.Parent.Parent.Parent.types.managers.runtimeManager)
local Playback = require(script.Parent.Parent.Parent.Parent.components.playback.shared.playback)

type Runtime = RuntimeTypes.Runtime
type RuntimeConfig = RuntimeTypes.RuntimeConfig
type RuntimeImpl = RuntimeTypes.RuntimeImpl
type PlaybackOwned = RuntimeTypes.PlaybackOwned
type PlaybackRuntimeLink = RuntimeTypes.PlaybackRuntimeLink
type ClockStatePort = RuntimeTypes.ClockStatePort
type PhaseGroupPort = RuntimeTypes.PhaseGroupPort
type ClockStateOwned = RuntimeTypes.ClockStateOwned
type PhaseGroupOwned = RuntimeTypes.PhaseGroupOwned
type PlaybackOptions<StepT, PhaseT, DirectionT> = RuntimeTypes.PlaybackOptions<StepT, PhaseT, DirectionT>
type Sequence<StepT> = RuntimeTypes.Sequence<StepT>
type PublicPlayback<StepT> = RuntimeTypes.Playback<StepT>

type RuntimeModule = {
	new: (config: RuntimeConfig?) -> Runtime,
}

local RuntimeManager = {}
RuntimeManager.__index = RuntimeManager

local function findValue<T>(values: { T }, candidate: T): number?
	for index, value in values do
		if value == candidate then
			return index
		end
	end
	return nil
end

local function removeValue<T>(values: { T }, candidate: T): boolean
	local index = findValue(values, candidate)
	if index == nil then
		return false
	end
	table.remove(values, index)
	return true
end

local function findClockState(self: RuntimeImpl, clockCandidate: unknown): (ClockStateOwned?, number?)
	for index, state in self._clockStates do
		if state.port.sameClock(clockCandidate) then
			return state, index
		end
	end
	return nil, nil
end

local function findPhaseGroup(state: ClockStateOwned, phaseCandidate: unknown): (PhaseGroupOwned?, number?)
	for index, group in state.groups do
		if group.port.samePhase(phaseCandidate) then
			return group, index
		end
	end
	return nil, nil
end

local function releaseContinuous(group: PhaseGroupOwned)
	local release = group.releaseContinuous
	if release ~= nil then
		group.releaseContinuous = nil
		release()
	end
end

local function removeUpdatingMember(group: PhaseGroupOwned, playback: PlaybackOwned)
	if removeValue(group.updatingMembers, playback) and #group.updatingMembers == 0 then
		releaseContinuous(group)
	end
end

local function bindContinuous(group: PhaseGroupOwned)
	if group.releaseContinuous ~= nil or #group.updatingMembers == 0 then
		return
	end

	group.releaseContinuous = group.port.bind(function(_clockDt: number, now: number)
		local snapshot = table.clone(group.updatingMembers)
		for _, playback in snapshot do
			if findValue(group.updatingMembers, playback) ~= nil then
				playback.runContinuous(now)
			end
		end
	end)
end

local function locatePlaybackGroup(self: RuntimeImpl, playback: PlaybackOwned): (ClockStateOwned?, PhaseGroupOwned?)
	for _, state in self._clockStates do
		if findValue(state.playbacks, playback) ~= nil then
			for _, group in state.groups do
				if findValue(group.members, playback) ~= nil then
					return state, group
				end
			end
		end
	end
	return nil, nil
end

local function detachPlayback(self: RuntimeImpl, playback: PlaybackOwned)
	removeValue(self._playbacks, playback)

	local state, group = locatePlaybackGroup(self, playback)
	if state == nil or group == nil then
		return
	end

	removeUpdatingMember(group, playback)
	removeValue(group.members, playback)
	removeValue(state.playbacks, playback)

	if #group.members == 0 then
		releaseContinuous(group)
		for index, candidate in state.groups do
			if candidate == group then
				table.remove(state.groups, index)
				break
			end
		end
	end

	if #state.playbacks == 0 then
		local release = state.releaseChanged
		state.releaseChanged = nil
		if release ~= nil then
			release()
		end
		for _, remainingGroup in state.groups do
			releaseContinuous(remainingGroup)
		end
		table.clear(state.groups)
		for index, candidate in self._clockStates do
			if candidate == state then
				table.remove(self._clockStates, index)
				break
			end
		end
	end
end

local function activatePlayback(
	self: RuntimeImpl,
	playback: PlaybackOwned,
	clockPort: ClockStatePort,
	phasePort: PhaseGroupPort,
	clockCandidate: unknown,
	phaseCandidate: unknown
): boolean
	if self._destroyed or clockPort.isDestroyed() then
		return false
	end

	local foundState = findClockState(self, clockCandidate)
	local state: ClockStateOwned
	if foundState == nil then
		local createdState: ClockStateOwned = {
			port = clockPort,
			playbacks = {},
			groups = {},
			releaseChanged = nil,
		}
		state = createdState
		table.insert(self._clockStates, state)
		state.releaseChanged = clockPort.bindChanged(function(change)
			local snapshot = table.clone(state.playbacks)
			for _, member in snapshot do
				if findValue(state.playbacks, member) ~= nil then
					member.reconcileClockChange(change)
				end
			end
		end, function(err)
			local snapshot = table.clone(state.playbacks)
			for _, member in snapshot do
				if findValue(state.playbacks, member) ~= nil then
					member.terminate("failed", "invalidClockChange", err)
				end
			end
		end)
	else
		state = foundState
	end

	if findValue(state.playbacks, playback) == nil then
		table.insert(state.playbacks, playback)
	end

	local foundGroup = findPhaseGroup(state, phaseCandidate)
	local group: PhaseGroupOwned
	if foundGroup == nil then
		local createdGroup: PhaseGroupOwned = {
			port = phasePort,
			members = {},
			updatingMembers = {},
			releaseContinuous = nil,
		}
		group = createdGroup
		table.insert(state.groups, group)
	else
		group = foundGroup
	end
	if findValue(group.members, playback) == nil then
		table.insert(group.members, playback)
	end
	return true
end

local function makeRuntimeLink(self: RuntimeImpl): PlaybackRuntimeLink
	return {
		register = function(playback)
			assert(not self._destroyed, "Pulse Runtime is destroyed")
			table.insert(self._playbacks, playback)
		end,
		activate = function(playback, clock, phase, clockCandidate, phaseCandidate)
			return activatePlayback(self, playback, clock, phase, clockCandidate, phaseCandidate)
		end,
		setUpdating = function(playback, updating)
			local _, group = locatePlaybackGroup(self, playback)
			if group == nil then
				return
			end
			if updating then
				if findValue(group.updatingMembers, playback) == nil then
					table.insert(group.updatingMembers, playback)
				end
				bindContinuous(group)
			else
				removeUpdatingMember(group, playback)
			end
		end,
		detach = function(playback)
			detachPlayback(self, playback)
		end,
		isDestroyed = function(): boolean
			return self._destroyed
		end,
	}
end

function RuntimeManager.new(config: RuntimeConfig?): Runtime
	local resolved: RuntimeConfig = if config == nil
		then {}
		else {
			realTimeScheduler = config.realTimeScheduler,
		}
	local self = (
		setmetatable({
			_config = resolved,
			_destroyed = false,
			_playbacks = {},
			_clockStates = {},
		}, RuntimeManager) :: unknown
	) :: RuntimeImpl
	return self
end

function RuntimeManager.createPlayback<StepT, PhaseT, DirectionT>(
	self: RuntimeImpl,
	sequence: Sequence<StepT>,
	options: PlaybackOptions<StepT, PhaseT, DirectionT>
): PublicPlayback<StepT>
	assert(not self._destroyed, "Pulse Runtime is destroyed")
	local clock = options.clock
	assert((clock :: unknown) ~= nil, "Pulse playback requires a clock")
	assert((options.phase :: unknown) ~= nil, "Pulse playback requires an explicit phase")
	assert((options.directions.forward :: unknown) ~= nil, "Pulse playback requires a forward direction token")
	assert((options.directions.backward :: unknown) ~= nil, "Pulse playback requires a backward direction token")
	assert(options.directions.forward ~= options.directions.backward, "Pulse clock direction tokens must be distinct")
	assert(not clock:isDestroyed(), "Pulse cannot borrow a destroyed clock")
	DefTypes.assertClockSample(clock:read())

	return Playback.new(sequence, options, makeRuntimeLink(self))
end

function RuntimeManager.destroy(self: RuntimeImpl)
	if self._destroyed then
		return
	end
	self._destroyed = true

	local snapshot = table.clone(self._playbacks)
	for _, playback in snapshot do
		playback.terminate("destroyed", "runtimeDestroyed", nil)
		playback.dispose()
	end

	for _, state in self._clockStates do
		for _, group in state.groups do
			releaseContinuous(group)
		end
		local release = state.releaseChanged
		state.releaseChanged = nil
		if release ~= nil then
			release()
		end
	end
	table.clear(self._playbacks)
	table.clear(self._clockStates)
end

local module: RuntimeModule = {
	new = RuntimeManager.new,
}

return module
