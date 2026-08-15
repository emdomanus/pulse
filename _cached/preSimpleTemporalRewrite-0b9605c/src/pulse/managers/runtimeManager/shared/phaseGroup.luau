--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local RuntimeInternalTypes = require(script.Parent.Parent.Parent.Parent.types.managers.runtimeManager.internal)

type PlaybackOwned = RuntimeInternalTypes.PlaybackOwned
type PhaseGroupOwned = RuntimeInternalTypes.PhaseGroupOwned
type PhaseGroupImpl<PhaseT, DirectionT> = RuntimeInternalTypes.PhaseGroupImpl<PhaseT, DirectionT>

type PhaseGroupModule = {
	new: <PhaseT, DirectionT>(clock: DefTypes.Clock<PhaseT, DirectionT>, phase: PhaseT) -> PhaseGroupOwned,
}

local PhaseGroup = {}
PhaseGroup.__index = PhaseGroup

local function findValue<T>(values: { T }, candidate: T): number?
	for index, value in values do
		if value == candidate then
			return index
		end
	end
	return nil
end

local function runContinuous<PhaseT, DirectionT>(self: PhaseGroupImpl<PhaseT, DirectionT>, now: number)
	local snapshot = table.clone(self._playbacks)
	for _, playback in snapshot do
		if findValue(self._playbacks, playback) ~= nil then
			playback:_runContinuous(now)
		end
	end
end

function PhaseGroup.new<PhaseT, DirectionT>(clock: DefTypes.Clock<PhaseT, DirectionT>, phase: PhaseT): PhaseGroupOwned
	local self = (
		setmetatable({
			_phase = phase,
			_playbacks = {},
			_release = nil,
		}, PhaseGroup) :: unknown
	) :: PhaseGroupImpl<PhaseT, DirectionT>

	self._release = clock:bindPhase(phase, function(_clockDt: number, now: number)
		runContinuous(self, now)
	end)
	return self
end

function PhaseGroup._samePhase<PhaseT, DirectionT>(self: PhaseGroupImpl<PhaseT, DirectionT>, candidate: unknown): boolean
	return candidate == self._phase
end

function PhaseGroup._addPlayback<PhaseT, DirectionT>(self: PhaseGroupImpl<PhaseT, DirectionT>, playback: PlaybackOwned)
	if findValue(self._playbacks, playback) == nil then
		table.insert(self._playbacks, playback)
	end
end

function PhaseGroup._removePlayback<PhaseT, DirectionT>(self: PhaseGroupImpl<PhaseT, DirectionT>, playback: PlaybackOwned): boolean
	local index = findValue(self._playbacks, playback)
	if index == nil then
		return false
	end
	table.remove(self._playbacks, index)
	return true
end

function PhaseGroup._isEmpty<PhaseT, DirectionT>(self: PhaseGroupImpl<PhaseT, DirectionT>): boolean
	return #self._playbacks == 0
end

function PhaseGroup._destroy<PhaseT, DirectionT>(self: PhaseGroupImpl<PhaseT, DirectionT>)
	local release = self._release
	self._release = nil
	if release ~= nil then
		release()
	end
	table.clear(self._playbacks)
end

local module: PhaseGroupModule = {
	new = PhaseGroup.new,
}

return module
