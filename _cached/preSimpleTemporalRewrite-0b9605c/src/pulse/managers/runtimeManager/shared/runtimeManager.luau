--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local OwnershipTypes = require(script.Parent.Parent.Parent.Parent.types.internal.ownership)
local RuntimeTypes = require(script.Parent.Parent.Parent.Parent.types.managers.runtimeManager)
local RuntimeInternalTypes = require(script.Parent.Parent.Parent.Parent.types.managers.runtimeManager.internal)
local Playback = require(script.Parent.Parent.Parent.Parent.components.playback.shared.playback)
local ClockState = require(script.Parent.clockState)
local PhaseGroup = require(script.Parent.phaseGroup)

type Runtime = RuntimeTypes.Runtime
type RuntimeConfig = RuntimeTypes.RuntimeConfig
type RuntimeImpl = RuntimeInternalTypes.RuntimeImpl
type RuntimeOwner = OwnershipTypes.RuntimeOwner
type PlaybackOwned = RuntimeInternalTypes.PlaybackOwned
type ClockStateOwned = RuntimeInternalTypes.ClockStateOwned
type PhaseGroupOwned = RuntimeInternalTypes.PhaseGroupOwned
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

local function findClockState(self: RuntimeImpl, clockCandidate: unknown): ClockStateOwned?
	for _, state in self._clockStates do
		if state:_sameClock(clockCandidate) then
			return state
		end
	end
	return nil
end

local function removeClockState(self: RuntimeImpl, state: ClockStateOwned)
	if removeValue(self._clockStates, state) then
		state:_destroy()
	end
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

function RuntimeManager._registerPlayback(self: RuntimeImpl, playback: PlaybackOwned)
	assert(not self._destroyed, "Pulse Runtime is destroyed")
	table.insert(self._playbacks, playback)
end

function RuntimeManager._activatePlayback<PhaseT, DirectionT>(
	self: RuntimeImpl,
	playback: PlaybackOwned,
	clock: DefTypes.Clock<PhaseT, DirectionT>
): boolean
	if self._destroyed or clock:isDestroyed() then
		return false
	end

	local foundState = findClockState(self, clock)
	local state: ClockStateOwned
	if foundState == nil then
		state = ClockState.new(clock)
		table.insert(self._clockStates, state)
	else
		state = foundState
	end
	state:_addPlayback(playback)
	return true
end

function RuntimeManager._setPlaybackUpdating<PhaseT, DirectionT>(
	self: RuntimeImpl,
	playback: PlaybackOwned,
	updating: boolean,
	clock: DefTypes.Clock<PhaseT, DirectionT>,
	phase: PhaseT
)
	local state = findClockState(self, clock)
	if state == nil or not state:_hasPlayback(playback) then
		return
	end

	local foundGroup = state:_findPhaseGroup(phase)
	if updating then
		local group: PhaseGroupOwned
		if foundGroup == nil then
			group = PhaseGroup.new(clock, phase)
			state:_addPhaseGroup(group)
		else
			group = foundGroup
		end
		group:_addPlayback(playback)
	elseif foundGroup ~= nil then
		foundGroup:_removePlayback(playback)
		if foundGroup:_isEmpty() then
			foundGroup:_destroy()
			state:_removePhaseGroup(foundGroup)
		end
	end
end

function RuntimeManager._detachPlayback(self: RuntimeImpl, playback: PlaybackOwned)
	removeValue(self._playbacks, playback)
	for _, state in self._clockStates do
		if state:_hasPlayback(playback) then
			state:_removeFromPhaseGroups(playback)
			state:_removePlayback(playback)
			if state:_isEmpty() then
				removeClockState(self, state)
			end
			return
		end
	end
end

function RuntimeManager._isDestroyed(self: RuntimeImpl): boolean
	return self._destroyed
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

	return Playback.new(sequence, options, (self :: unknown) :: RuntimeOwner)
end

function RuntimeManager.destroy(self: RuntimeImpl)
	if self._destroyed then
		return
	end
	self._destroyed = true

	local snapshot = table.clone(self._playbacks)
	for _, playback in snapshot do
		playback:_terminate("destroyed", "runtimeDestroyed", nil)
		playback:_dispose()
	end

	for _, state in self._clockStates do
		state:_destroy()
	end
	table.clear(self._playbacks)
	table.clear(self._clockStates)
end

local module: RuntimeModule = {
	new = RuntimeManager.new,
}

return module
