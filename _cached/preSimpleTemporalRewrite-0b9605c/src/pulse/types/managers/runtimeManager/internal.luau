--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.def)
local RuntimeTypes = require(script.Parent)
local OwnershipTypes = require(script.Parent.Parent.Parent.internal.ownership)

export type PlaybackOwned = OwnershipTypes.PlaybackOwned

export type PhaseGroupOwned = {
	_samePhase: (self: PhaseGroupOwned, candidate: unknown) -> boolean,
	_addPlayback: (self: PhaseGroupOwned, playback: PlaybackOwned) -> (),
	_removePlayback: (self: PhaseGroupOwned, playback: PlaybackOwned) -> boolean,
	_isEmpty: (self: PhaseGroupOwned) -> boolean,
	_destroy: (self: PhaseGroupOwned) -> (),
}

export type PhaseGroupImpl<PhaseT, DirectionT> = PhaseGroupOwned & {
	_phase: PhaseT,
	_playbacks: { PlaybackOwned },
	_release: DefTypes.Release?,
}

export type ClockStateOwned = {
	_sameClock: (self: ClockStateOwned, candidate: unknown) -> boolean,
	_isDestroyed: (self: ClockStateOwned) -> boolean,
	_addPlayback: (self: ClockStateOwned, playback: PlaybackOwned) -> (),
	_removePlayback: (self: ClockStateOwned, playback: PlaybackOwned) -> boolean,
	_hasPlayback: (self: ClockStateOwned, playback: PlaybackOwned) -> boolean,
	_isEmpty: (self: ClockStateOwned) -> boolean,
	_findPhaseGroup: (self: ClockStateOwned, candidate: unknown) -> PhaseGroupOwned?,
	_addPhaseGroup: (self: ClockStateOwned, group: PhaseGroupOwned) -> (),
	_removePhaseGroup: (self: ClockStateOwned, group: PhaseGroupOwned) -> (),
	_removeFromPhaseGroups: (self: ClockStateOwned, playback: PlaybackOwned) -> (),
	_destroy: (self: ClockStateOwned) -> (),
}

export type ClockStateImpl<PhaseT, DirectionT> = ClockStateOwned & {
	_clock: DefTypes.Clock<PhaseT, DirectionT>,
	_playbacks: { PlaybackOwned },
	_phaseGroups: { PhaseGroupOwned },
	_release: DefTypes.Release?,
}

export type RuntimeImpl = RuntimeTypes.Runtime & OwnershipTypes.RuntimeOwner & {
	_config: DefTypes.RuntimeConfig,
	_destroyed: boolean,
	_playbacks: { PlaybackOwned },
	_clockStates: { ClockStateOwned },
}

return {}
