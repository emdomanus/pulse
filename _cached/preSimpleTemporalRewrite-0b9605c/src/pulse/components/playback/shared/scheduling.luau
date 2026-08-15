--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)
local PlaybackInternalTypes = require(script.Parent.Parent.Parent.Parent.types.components.playback.internal)
local OwnershipTypes = require(script.Parent.Parent.Parent.Parent.types.internal.ownership)
local Timeline = require(script.Parent.timeline)

type ClockSample = DefTypes.ClockSample
type ScheduledTaskId = DefTypes.ScheduledTaskId
type Status = DefTypes.Status
type TraversalDirection = DefTypes.TraversalDirection
type PlaybackOwned = OwnershipTypes.PlaybackOwned
type SchedulingView<PhaseT, DirectionT> = PlaybackInternalTypes.SchedulingView<PhaseT, DirectionT>

type SchedulingModule = {
	cancelTask: <PhaseT, DirectionT>(view: SchedulingView<PhaseT, DirectionT>) -> (),
	setUpdating: <PhaseT, DirectionT>(view: SchedulingView<PhaseT, DirectionT>, updating: boolean) -> (),
	readClock: <PhaseT, DirectionT>(view: SchedulingView<PhaseT, DirectionT>) -> ClockSample,
	sequenceAtClock: <PhaseT, DirectionT>(view: SchedulingView<PhaseT, DirectionT>, clockPosition: number) -> number?,
	clockAtSequence: <PhaseT, DirectionT>(
		view: SchedulingView<PhaseT, DirectionT>,
		sequencePosition: number
	) -> number?,
	refresh: <StepT, PhaseT, DirectionT>(
		view: PlaybackInternalTypes.SchedulingExecutionView<StepT, PhaseT, DirectionT>
	) -> (),
}

local Scheduling = {}

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function sign(value: number): number
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	end
	return 0
end

function Scheduling.cancelTask<PhaseT, DirectionT>(view: SchedulingView<PhaseT, DirectionT>)
	local taskId = view._taskId
	view._taskId = nil
	view._taskClockDirection = nil
	if taskId ~= nil then
		view._clock:cancel(taskId)
	end
end

function Scheduling.setUpdating<PhaseT, DirectionT>(view: SchedulingView<PhaseT, DirectionT>, updating: boolean)
	if view._updating == updating then
		return
	end
	view._updating = updating
	if view._attached then
		view._runtime:_setPlaybackUpdating((view :: unknown) :: PlaybackOwned, updating, view._clock, view._phase)
	end
end

function Scheduling.readClock<PhaseT, DirectionT>(view: SchedulingView<PhaseT, DirectionT>): ClockSample
	local ok, result = pcall(function(): unknown
		return DefTypes.assertClockSample(view._clock:read())
	end)
	if not ok then
		view:_terminate("failed", "invalidClockSample", result)
		return {
			timePosition = view._anchorClock,
			rate = 0,
		}
	end
	return (result :: unknown) :: ClockSample
end

function Scheduling.sequenceAtClock<PhaseT, DirectionT>(view: SchedulingView<PhaseT, DirectionT>, clockPosition: number): number?
	local result = view._anchorSequence + (clockPosition - view._anchorClock) * view._playbackSpeed
	if not isFinite(result) then
		view:_terminate("failed", "numericOverflow", "Pulse playback anchor produced a non-finite sequence position")
		return nil
	end
	return result
end

function Scheduling.clockAtSequence<PhaseT, DirectionT>(view: SchedulingView<PhaseT, DirectionT>, sequencePosition: number): number?
	local result = view._anchorClock + (sequencePosition - view._anchorSequence) / view._playbackSpeed
	if not isFinite(result) then
		view:_terminate("failed", "numericOverflow", "Pulse checkpoint mapping produced a non-finite clock position")
		return nil
	end
	return result
end

local function onReached<StepT, PhaseT, DirectionT>(
	view: PlaybackInternalTypes.SchedulingExecutionView<
		StepT,
		PhaseT,
		DirectionT
	>,
	taskId: ScheduledTaskId,
	_now: number,
	direction: DirectionT
)
	if view._status ~= "playing" or view._taskId ~= taskId or view._clock:isDestroyed() then
		return
	end
	local sample = Scheduling.readClock(view)
	if view._status ~= "playing" then
		Scheduling.cancelTask(view)
		return
	end
	view._lastClockRate = sample.rate
	view:_requestReconcile(sample.timePosition, false, direction)
	if view._status == "playing" then
		Scheduling.refresh(view)
	end
end

function Scheduling.refresh<StepT, PhaseT, DirectionT>(view: PlaybackInternalTypes.SchedulingExecutionView<
	StepT,
	PhaseT,
	DirectionT
>)
	if view._status ~= "playing" then
		Scheduling.cancelTask(view)
		return
	end
	local sample = Scheduling.readClock(view)
	if view._status ~= "playing" then
		Scheduling.cancelTask(view)
		return
	end
	view._lastClockRate = sample.rate
	local clockSign = sign(sample.rate)
	local speedSign = sign(view._playbackSpeed)
	if clockSign == 0 or speedSign == 0 then
		Scheduling.cancelTask(view)
		return
	end
	local traversal: TraversalDirection = if clockSign * speedSign > 0 then "forward" else "backward"
	local sequence = view._sequence
	local checkpoint = Timeline.nextCheckpoint(sequence, view._position, traversal)
	if checkpoint == nil then
		Scheduling.cancelTask(view)
		return
	end
	local clockCheckpoint = Scheduling.clockAtSequence(view, checkpoint)
	if clockCheckpoint == nil then
		return
	end
	local clockDirection: DirectionT = if clockSign > 0 then view._directions.forward else view._directions.backward
	local existingId = view._taskId
	if existingId ~= nil and view._taskClockDirection == clockDirection then
		if view._clock:rescheduleAt(existingId, clockCheckpoint, view._phase) then
			return
		end
		view._taskId = nil
		view._taskClockDirection = nil
	end
	if existingId ~= nil then
		view._clock:cancel(existingId)
		view._taskId = nil
		view._taskClockDirection = nil
	end

	local taskId: ScheduledTaskId = 0
	taskId = view._clock:bindToReached(clockCheckpoint, clockDirection, function(now, actualDirection)
		onReached(view, taskId, now, actualDirection)
	end, view._phase)
	view._taskId = taskId
	view._taskClockDirection = clockDirection
end

local module: SchedulingModule = {
	cancelTask = Scheduling.cancelTask,
	setUpdating = Scheduling.setUpdating,
	readClock = Scheduling.readClock,
	sequenceAtClock = Scheduling.sequenceAtClock,
	clockAtSequence = Scheduling.clockAtSequence,
	refresh = Scheduling.refresh,
}

return module
