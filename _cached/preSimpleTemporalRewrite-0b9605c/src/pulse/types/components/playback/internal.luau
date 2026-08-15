--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.Parent.def)
local ContextTypes = require(script.Parent.Parent.context)
local PlaybackTypes = require(script.Parent)
local SequenceTypes = require(script.Parent.Parent.sequence)
local OwnershipTypes = require(script.Parent.Parent.Parent.internal.ownership)

export type Listener<T...> = {
	callback: (T...) -> (),
	active: boolean,
}

export type CallbackCollections = {
	ended: { Listener<DefTypes.Completion> },
	looped: { Listener<DefTypes.LoopChange> },
	paramChanged: { Listener<string, unknown, unknown?> },
	signaled: { Listener<string, unknown?> },
}

export type Occurrence<StepT> = {
	state: "blocked" | "applied",
	from: StepT?,
	to: StepT?,
	payload: unknown?,
}

export type Action<StepT> = {
	kind: "event" | "loop",
	event: SequenceTypes.CompiledEvent<StepT>?,
	loopIndex: number,
	fromLoopIndex: number,
	toLoopIndex: number,
}

export type WorkState = {
	count: number,
}

export type PendingClockChange = {
	sample: DefTypes.ClockSample,
	stage: "catchUp" | "reorient",
	requiresRefresh: boolean,
}

export type TimelineView<StepT> = {
	_sequence: SequenceTypes.SequenceImpl<StepT>,
	_position: number,
	_boundaryStage: number,
}

export type SchedulingView<PhaseT, DirectionT> = OwnershipTypes.PlaybackOwned & {
	_clock: DefTypes.Clock<PhaseT, DirectionT>,
	_directions: DefTypes.ClockDirections<DirectionT>,
	_phase: PhaseT,
	_runtime: OwnershipTypes.RuntimeOwner,
	_status: DefTypes.Status,
	_attached: boolean,
	_updating: boolean,
	_playbackSpeed: number,
	_position: number,
	_anchorClock: number,
	_anchorSequence: number,
	_lastClockRate: number,
	_taskId: DefTypes.ScheduledTaskId?,
	_taskClockDirection: DirectionT?,
	_requestReconcile: (
		self: SchedulingView<PhaseT, DirectionT>,
		clockPosition: number,
		runUpdates: boolean,
		observedDirection: DirectionT?
	) -> (),
}

export type SchedulingExecutionView<StepT, PhaseT, DirectionT> = SchedulingView<PhaseT, DirectionT> & {
	_sequence: SequenceTypes.SequenceImpl<StepT>,
}

export type ReconciliationView<StepT, PhaseT, DirectionT> = SchedulingExecutionView<StepT, PhaseT, DirectionT> & {
	_context: ContextTypes.Context<StepT>,
	_callbacks: CallbackCollections,
	_step: StepT?,
	_journal: { [string]: Occurrence<StepT> },
	_boundaryStage: number,
	_lastContinuousPosition: number,
	_reconciling: boolean,
	_pendingReconcile: boolean,
	_pendingClockPosition: number?,
	_pendingUpdate: boolean,
	_pendingObservedDirection: DirectionT?,
	_activeClockChange: PendingClockChange?,
	_queuedClockChanges: { PendingClockChange },
	_scheduleRefreshPending: boolean,
	_callbackDepth: number,
	_flushingMutations: boolean,
	_queuedMutations: { () -> () },
	_mutationGeneration: number,
	_callObserver: (self: ReconciliationView<StepT, PhaseT, DirectionT>, callback: () -> ()) -> (),
	_callUser: (self: ReconciliationView<StepT, PhaseT, DirectionT>, callback: () -> ()) -> boolean,
	_callGate: (
		self: ReconciliationView<StepT, PhaseT, DirectionT>,
		callback: () -> (boolean, string?)
	) -> (boolean, string?),
	_flushMutations: (self: ReconciliationView<StepT, PhaseT, DirectionT>) -> (),
	_refreshScheduling: (self: ReconciliationView<StepT, PhaseT, DirectionT>) -> (),
}

export type PlaybackImpl<StepT, PhaseT, DirectionT> =
	PlaybackTypes.Playback<StepT>
	& ContextTypes.PlaybackContextPort<StepT>
	& OwnershipTypes.PlaybackOwned
	& {
		_sequence: SequenceTypes.SequenceImpl<StepT>,
		_clock: DefTypes.Clock<PhaseT, DirectionT>,
		_directions: DefTypes.ClockDirections<DirectionT>,
		_phase: PhaseT,
		_runtime: OwnershipTypes.RuntimeOwner,
		_context: ContextTypes.Context<StepT>,

		_status: DefTypes.Status,
		_completion: DefTypes.Completion?,
		_started: boolean,
		_attached: boolean,
		_updating: boolean,
		_disposed: boolean,

		_callbacks: CallbackCollections,
		_params: DefTypes.Params,
		_cleanups: { () -> () },
		_step: StepT?,
		_journal: { [string]: Occurrence<StepT> },

		_playbackSpeed: number,
		_position: number,
		_boundaryStage: number,
		_anchorClock: number,
		_anchorSequence: number,
		_lastClockRate: number,
		_lastContinuousPosition: number,

		_taskId: DefTypes.ScheduledTaskId?,
		_taskClockDirection: DirectionT?,

		_reconciling: boolean,
		_pendingReconcile: boolean,
		_pendingClockPosition: number?,
		_pendingUpdate: boolean,
		_pendingObservedDirection: DirectionT?,
		_activeClockChange: PendingClockChange?,
		_queuedClockChanges: { PendingClockChange },
		_scheduleRefreshPending: boolean,
		_callbackDepth: number,
		_flushingMutations: boolean,
		_queuedMutations: { () -> () },
		_mutationGeneration: number,

		_requestReconcile: (
			self: PlaybackImpl<StepT, PhaseT, DirectionT>,
			clockPosition: number,
			runUpdates: boolean,
			observedDirection: DirectionT?
		) -> (),
		_callObserver: (self: PlaybackImpl<StepT, PhaseT, DirectionT>, callback: () -> ()) -> (),
		_callUser: (self: PlaybackImpl<StepT, PhaseT, DirectionT>, callback: () -> ()) -> boolean,
		_callGate: (
			self: PlaybackImpl<StepT, PhaseT, DirectionT>,
			callback: () -> (boolean, string?)
		) -> (boolean, string?),
		_flushMutations: (self: PlaybackImpl<StepT, PhaseT, DirectionT>) -> (),
		_refreshScheduling: (self: PlaybackImpl<StepT, PhaseT, DirectionT>) -> (),
	}

return {}
