--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local RuntimeInternalTypes = require(script.Parent.Parent.Parent.Parent.types.managers.runtimeManager.internal)

type PlaybackOwned = RuntimeInternalTypes.PlaybackOwned
type PhaseGroupOwned = RuntimeInternalTypes.PhaseGroupOwned
type ClockStateOwned = RuntimeInternalTypes.ClockStateOwned
type ClockStateImpl<PhaseT, DirectionT> = RuntimeInternalTypes.ClockStateImpl<PhaseT, DirectionT>

type ClockStateModule = {
	new: <PhaseT, DirectionT>(clock: DefTypes.Clock<PhaseT, DirectionT>) -> ClockStateOwned,
}

local ClockState = {}
ClockState.__index = ClockState

local function findValue<T>(values: { T }, candidate: T): number?
	for index, value in values do
		if value == candidate then
			return index
		end
	end
	return nil
end

local function publishInvalid<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>, err: unknown)
	local snapshot = table.clone(self._playbacks)
	for _, playback in snapshot do
		if findValue(self._playbacks, playback) ~= nil then
			playback:_terminate("failed", "invalidClockChange", err)
		end
	end
end

local function publishChange<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>, rawChange: unknown)
	local ok, result = pcall(function(): unknown
		return DefTypes.assertClockChange(rawChange)
	end)
	if not ok then
		publishInvalid(self, result)
		return
	end

	local change = (result :: unknown) :: DefTypes.ClockChange
	local snapshot = table.clone(self._playbacks)
	for _, playback in snapshot do
		if findValue(self._playbacks, playback) ~= nil then
			playback:_reconcileClockChange(change)
		end
	end
end

function ClockState.new<PhaseT, DirectionT>(clock: DefTypes.Clock<PhaseT, DirectionT>): ClockStateOwned
	local self = (
		setmetatable({
			_clock = clock,
			_playbacks = {},
			_phaseGroups = {},
			_release = nil,
		}, ClockState) :: unknown
	) :: ClockStateImpl<PhaseT, DirectionT>

	self._release = clock:bindToChanged(function(rawChange: unknown)
		publishChange(self, rawChange)
	end, false)
	return self
end

function ClockState._sameClock<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>, candidate: unknown): boolean
	return candidate == self._clock
end

function ClockState._isDestroyed<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>): boolean
	return self._clock:isDestroyed()
end

function ClockState._addPlayback<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>, playback: PlaybackOwned)
	if findValue(self._playbacks, playback) == nil then
		table.insert(self._playbacks, playback)
	end
end

function ClockState._removePlayback<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>, playback: PlaybackOwned): boolean
	local index = findValue(self._playbacks, playback)
	if index == nil then
		return false
	end
	table.remove(self._playbacks, index)
	return true
end

function ClockState._hasPlayback<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>, playback: PlaybackOwned): boolean
	return findValue(self._playbacks, playback) ~= nil
end

function ClockState._isEmpty<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>): boolean
	return #self._playbacks == 0
end

function ClockState._findPhaseGroup<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>, candidate: unknown): PhaseGroupOwned?
	for _, group in self._phaseGroups do
		if group:_samePhase(candidate) then
			return group
		end
	end
	return nil
end

function ClockState._addPhaseGroup<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>, group: PhaseGroupOwned)
	assert(findValue(self._phaseGroups, group) == nil, "Pulse phase group already belongs to its clock state")
	table.insert(self._phaseGroups, group)
end

function ClockState._removePhaseGroup<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>, group: PhaseGroupOwned)
	local index = findValue(self._phaseGroups, group)
	if index ~= nil then
		table.remove(self._phaseGroups, index)
	end
end

function ClockState._removeFromPhaseGroups<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>, playback: PlaybackOwned)
	for index = #self._phaseGroups, 1, -1 do
		local group = self._phaseGroups[index]
		group:_removePlayback(playback)
		if group:_isEmpty() then
			group:_destroy()
			table.remove(self._phaseGroups, index)
		end
	end
end

function ClockState._destroy<PhaseT, DirectionT>(self: ClockStateImpl<PhaseT, DirectionT>)
	local release = self._release
	self._release = nil
	if release ~= nil then
		release()
	end
	for _, group in self._phaseGroups do
		group:_destroy()
	end
	table.clear(self._phaseGroups)
	table.clear(self._playbacks)
end

local module: ClockStateModule = {
	new = ClockState.new,
}

return module
