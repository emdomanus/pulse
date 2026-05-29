--!strict
--!optimize 2
--!native

local AdvancedUtils = require(script.Parent.Parent.Parent.externalPackages.advancedUtils)
local DefTypes = require(script.Parent.Parent.types.def)
local ContextComponent = require(script.Parent.context)
local PlaybackTypes = require(script.Parent.Parent.types.components.playback)

export type StepId = PlaybackTypes.StepId
export type PlayRequest<StepT = StepId> = DefTypes.PlayRequest<StepT>
export type Sequence<StepT = StepId> = PlaybackTypes.Sequence<StepT>
export type Context<StepT = StepId> = PlaybackTypes.Context<StepT>
export type Playback<StepT = StepId> = PlaybackTypes.Playback<StepT>
type PlaybackImpl<StepT = StepId> = PlaybackTypes.PlaybackImpl<StepT>

local Playback = {}
Playback.__index = Playback

local Hook = AdvancedUtils.core.hook
local MAX_LOOP_CATCH_UP = 16

local function copyParams(baseParams: { [string]: any }, overrideParams: { [string]: any }?): { [string]: any }
	local params = table.clone(baseParams)

	if overrideParams then
		for name, value in overrideParams do
			params[name] = value
		end
	end

	return params
end

local function findNextEventIndex(sequence: any, timePosition: number, includeCurrent: boolean): number
	local events = sequence._sortedEvents
	local count = #events

	for index = 1, count do
		local eventTime = events[index].time
		local isNextEvent = if includeCurrent then eventTime >= timePosition else eventTime > timePosition
		if isNextEvent then
			return index
		end
	end

	return count + 1
end

local function isTerminalStatus(status: DefTypes.Status): boolean
	return status == "completed"
		or status == "stopped"
		or status == "cancelled"
		or status == "destroyed"
		or status == "failed"
end

local function runCleanup<StepT>(self: PlaybackImpl<StepT>): any?
	local cleanups = self._cleanups
	local firstError = nil

	for index = #cleanups, 1, -1 do
		local cleanup = cleanups[index]
		cleanups[index] = nil :: any

		local ok, cleanupErr = pcall(cleanup)
		if not ok and firstError == nil then
			firstError = cleanupErr
		end
	end

	self._cleanupHasRun = true

	return firstError
end

local function fireObserverHook(hook: any, ...: any)
	local ok, hookErr = pcall(hook.fire, hook, ...)

	if not ok then
		warn("[Pulse] observer hook listener failed:", hookErr)
	end
end

local function finish<StepT>(
	self: PlaybackImpl<StepT>,
	status: DefTypes.Status,
	reason: DefTypes.CompletionReason,
	err: any?,
	useCleanupDelay: boolean?
)
	if isTerminalStatus(self._status) then
		return
	end

	if self._status == "stopping" and status ~= "cancelled" and status ~= "destroyed" and status ~= "failed" then
		return
	end

	local previousStatus = self._status

	if previousStatus == "stopping" then
		local completion: DefTypes.Completion = {
			reason = reason,
			status = status,
			error = err,
		}

		self._status = status
		self._completion = completion
		self._cleanupRemaining = 0
		local cleanupErr = runCleanup(self)
		if cleanupErr ~= nil and status ~= "failed" then
			completion.status = "failed"
			completion.reason = "failed"
			completion.error = cleanupErr
			self._status = "failed"
		end
		return
	end

	if status == "cancelled" and self._sequence.definition.onCancel then
		local ok, callbackErr = pcall(self._sequence.definition.onCancel :: any, self._context, reason)
		if not ok then
			status = "failed"
			reason = "failed"
			err = callbackErr
		end
	elseif (status == "completed" or status == "stopped") and previousStatus ~= "idle" and self._sequence.definition.onStop then
		local ok, callbackErr = pcall(self._sequence.definition.onStop :: any, self._context, reason)
		if not ok then
			status = "failed"
			reason = "failed"
			err = callbackErr
		end
	end

	local completion: DefTypes.Completion = {
		reason = reason,
		status = status,
		error = err,
	}

	local cleanupDelay = self._sequence.cleanupDelay
	if status == "completed" and useCleanupDelay == true and cleanupDelay > 0 then
		self._status = "stopping"
		self._completion = completion
		self._cleanupRemaining = cleanupDelay
		fireObserverHook(self.Ended, completion)
		return
	end

	self._status = status
	self._completion = completion
	self._cleanupRemaining = 0
	local cleanupErr = runCleanup(self)
	if cleanupErr ~= nil and status ~= "failed" then
		completion.status = "failed"
		completion.reason = "failed"
		completion.error = cleanupErr
		self._status = "failed"
	end
	fireObserverHook(self.Ended, completion)
end

local function finishCleanupDelay<StepT>(self: PlaybackImpl<StepT>)
	local completion = self._completion
	if self._status ~= "stopping" or completion == nil then
		return
	end

	local cleanupErr = runCleanup(self)
	self._cleanupRemaining = 0
	self._status = completion.status
	if cleanupErr ~= nil and self._status ~= "failed" then
		completion.status = "failed"
		completion.reason = "failed"
		completion.error = cleanupErr
		self._status = "failed"
	end
end

local function fail<StepT>(self: PlaybackImpl<StepT>, err: any?)
	finish(self, "failed", "failed", err, false)
end

local function callUser<StepT>(self: PlaybackImpl<StepT>, callback: any, ...: any): boolean
	local ok, callbackErr = pcall(callback, ...)
	if not ok then
		fail(self, callbackErr)
		return false
	end

	return true
end

local function callUserPacked<StepT>(self: PlaybackImpl<StepT>, callback: any, ...: any): { any }
	local results = table.pack(pcall(callback, ...))
	if not results[1] then
		fail(self, results[2])
	end

	return results
end

local function runEvent<StepT>(self: PlaybackImpl<StepT>, event: any)
	if event.step ~= nil then
		local ok = self:step(event.step, nil)
		if not ok then
			return
		end
	end

	callUser(self, event.run, self._context)
end

local function runEventsThrough<StepT>(self: PlaybackImpl<StepT>, timePosition: number)
	local events = self._sequence._sortedEvents

	while self._nextEventIndex <= #events do
		local event = events[self._nextEventIndex]
		if event.time > timePosition then
			return
		end

		self._nextEventIndex += 1
		runEvent(self, event)

		if self._status ~= "playing" then
			return
		end
	end
end

local function emitLoop<StepT>(self: PlaybackImpl<StepT>)
	self._loopCount += 1

	if self._sequence.definition.onLoop then
		if not callUser(self, self._sequence.definition.onLoop, self._context, self._loopCount) then
			return
		end
	end

	fireObserverHook(self.Looped, self._loopCount)
end

local function seekTo<StepT>(
	self: PlaybackImpl<StepT>,
	timePosition: number?,
	mode: DefTypes.SeekMode?,
	replay: boolean?,
	step: StepT?,
	payload: any?,
	request: DefTypes.SeekRequest<StepT>?
)
	local seekMode = mode or self._sequence.seekMode
	if seekMode == "none" then
		return
	end

	local target = timePosition or self._timePosition
	local duration = self._sequence.duration
	if duration ~= nil then
		target = math.min(target, duration)
	end

	if seekMode == "forward" and target < self._timePosition then
		return
	end

	self._timePosition = math.max(target, 0)
	self._nextEventIndex = if replay then 1 else findNextEventIndex(self._sequence, self._timePosition, false)

	if step ~= nil then
		local ok = self:step(step, payload)
		if not ok then
			return
		end
	end

	if replay then
		runEventsThrough(self, self._timePosition)
		if isTerminalStatus(self._status) then
			return
		end
	end

	if self._sequence.definition.onSeek then
		local seekRequest = request
			or {
				timePosition = self._timePosition,
				mode = seekMode,
				replay = replay,
				step = step,
				payload = payload,
			}

		callUser(self, self._sequence.definition.onSeek, self._context, seekRequest)
	end
end

function Playback.new<StepT>(
	_sequence: Sequence<StepT>,
	_request: PlayRequest<StepT>?
): Playback<StepT>
	local sequence = _sequence :: any
	local request = _request or {}
	local timePosition = request.timePosition or 0

	local self: PlaybackImpl<StepT> = setmetatable({
		Ended = Hook.new(),
		Looped = Hook.new(),
		ParamChanged = Hook.new(),
		Signaled = Hook.new(),
		_sequence = sequence,
		_status = "idle",
		_step = nil,
		_timePosition = timePosition,
		_playbackSpeed = math.max(request.playbackSpeed or 1, 0),
		_nextEventIndex = findNextEventIndex(sequence, timePosition, true),
		_loopCount = 0,
		_completion = nil,
		_cleanupRemaining = 0,
		_cleanupHasRun = false,
		_params = copyParams(sequence.defaultParams, request.params),
		_cleanups = {},
		_context = nil :: any,
	}, Playback) :: any

	self._context = ContextComponent.new(self)

	if sequence.definition.onCreate then
		callUser(self, sequence.definition.onCreate, self._context)
	end

	if request.step ~= nil and self._status == "idle" then
		self:step(request.step, nil)
	end

	return self
end

function Playback.play<StepT>(self: PlaybackImpl<StepT>): Playback<StepT>
	if self._status == "playing" then
		return self
	end

	if self._status == "paused" then
		self:resume()
		return self
	end

	if self._status ~= "idle" then
		return self
	end

	self._status = "playing"

	if self._sequence.definition.onPlay then
		if not callUser(self, self._sequence.definition.onPlay, self._context) then
			return self
		end
	end

	runEventsThrough(self, self._timePosition)

	return self
end

function Playback.pause<StepT>(self: PlaybackImpl<StepT>)
	if self._status == "playing" then
		self._status = "paused"
	end
end

function Playback.resume<StepT>(self: PlaybackImpl<StepT>)
	if self._status == "paused" then
		self._status = "playing"
	end
end

function Playback.stop<StepT>(self: PlaybackImpl<StepT>, reason: DefTypes.CompletionReason?)
	finish(self, "stopped", reason or "stopped", nil, false)
end

function Playback.cancel<StepT>(self: PlaybackImpl<StepT>, reason: DefTypes.CompletionReason?)
	finish(self, "cancelled", reason or "cancelled", nil, false)
end

function Playback.destroy<StepT>(self: PlaybackImpl<StepT>)
	if self._status == "destroyed" then
		return
	end

	if self._sequence.definition.onDestroy then
		callUser(self, self._sequence.definition.onDestroy, self._context)
	end

	finish(self, "destroyed", "destroyed", nil, false)
	self.Ended:clear()
	self.Looped:clear()
	self.ParamChanged:clear()
	self.Signaled:clear()
end

function Playback.isPlaying<StepT>(self: PlaybackImpl<StepT>): boolean
	return self._status == "playing"
end

function Playback.isPaused<StepT>(self: PlaybackImpl<StepT>): boolean
	return self._status == "paused"
end

function Playback.isAlive<StepT>(self: PlaybackImpl<StepT>): boolean
	local status = self._status
	return status == "idle" or status == "playing" or status == "paused" or status == "stopping"
end

function Playback.getStatus<StepT>(self: PlaybackImpl<StepT>): DefTypes.Status
	return self._status
end

function Playback.setParam<StepT>(self: PlaybackImpl<StepT>, name: string, value: any)
	local oldValue = self._params[name]
	if oldValue == value then
		return
	end

	self._params[name] = value

	if self._sequence.definition.onParamChanged then
		if not callUser(self, self._sequence.definition.onParamChanged, self._context, name, value, oldValue) then
			return
		end
	end

	fireObserverHook(self.ParamChanged, name, value, oldValue)
end

function Playback.getParam<StepT>(self: PlaybackImpl<StepT>, name: string): any
	return self._params[name]
end

function Playback.setParams<StepT>(self: PlaybackImpl<StepT>, params: DefTypes.Params)
	for name, value in params do
		self:setParam(name, value)
	end
end

function Playback.signal<StepT>(self: PlaybackImpl<StepT>, name: string, payload: any?)
	local handler = self._sequence.signals[name]
	if handler then
		if not callUser(self, handler, self._context, payload) then
			return
		end
	end

	fireObserverHook(self.Signaled, name, payload)
end

function Playback.getStep<StepT>(self: PlaybackImpl<StepT>): StepT?
	return self._step
end

function Playback.canStep<StepT>(self: PlaybackImpl<StepT>, step: StepT?, payload: any?): (boolean, string?)
	if step == nil then
		return true, nil
	end

	local nextStep = self._sequence.steps[step]
	if nextStep == nil then
		return false, "missingStep"
	end

	if nextStep.canEnter then
		local results = callUserPacked(self, nextStep.canEnter, self._context, payload)
		if not results[1] then
			return false, "failed"
		end

		local ok = results[2]
		local reason = results[3]
		if not ok then
			return false, reason
		end
	end

	local transitions = self._sequence.transitions
	if #transitions == 0 then
		return true, nil
	end

	for _, transition in transitions do
		local fromMatches = transition.from == nil or transition.from == self._step
		local toMatches = transition.to == nil or transition.to == step
		if fromMatches and toMatches then
			if transition.canStep then
				local results = callUserPacked(self, transition.canStep, self._context, self._step, step, payload)
				if not results[1] then
					return false, "failed"
				end

				return results[2], results[3]
			end

			return true, nil
		end
	end

	return false, "blockedTransition"
end

function Playback.step<StepT>(self: PlaybackImpl<StepT>, step: StepT?, payload: any?): (boolean, string?)
	local ok, reason = self:canStep(step, payload)
	if not ok then
		return false, reason
	end

	local previousStep = self._step
	self._step = step

	if step ~= nil then
		local stepDefinition = self._sequence.steps[step]
		if stepDefinition and stepDefinition.run then
			if not callUser(self, stepDefinition.run, self._context, payload) then
				return false, "failed"
			end
		end
	end

	if self._sequence.definition.onStep then
		if not callUser(self, self._sequence.definition.onStep, self._context, previousStep, step, payload) then
			return false, "failed"
		end
	end

	return true, nil
end

function Playback.setPlaybackSpeed<StepT>(self: PlaybackImpl<StepT>, speed: number)
	self._playbackSpeed = math.max(speed, 0)
end

function Playback.getPlaybackSpeed<StepT>(self: PlaybackImpl<StepT>): number
	return self._playbackSpeed
end

function Playback.setTimePosition<StepT>(self: PlaybackImpl<StepT>, timePosition: number)
	seekTo(self, timePosition, nil, false, nil, nil, nil)
end

function Playback.getTimePosition<StepT>(self: PlaybackImpl<StepT>): number
	return self._timePosition
end

function Playback.seek<StepT>(self: PlaybackImpl<StepT>, request: DefTypes.SeekRequest<StepT>)
	seekTo(self, request.timePosition, request.mode, request.replay == true, request.step, request.payload, request)
end

function Playback._update<StepT>(self: PlaybackImpl<StepT>, dt: number)
	if self._status == "stopping" then
		self._cleanupRemaining -= dt
		if self._cleanupRemaining <= 0 then
			finishCleanupDelay(self)
		end
		return
	end

	if self._status ~= "playing" then
		return
	end

	local duration = self._sequence.duration
	local nextTime = self._timePosition + dt * self._playbackSpeed
	nextTime = math.max(nextTime, 0)

	if duration ~= nil and duration > 0 and self._sequence.loop and nextTime >= duration then
		self._timePosition = duration
		runEventsThrough(self, duration)

		if self._status ~= "playing" then
			return
		end

		local loops = 0
		while nextTime >= duration do
			loops += 1
			if loops > MAX_LOOP_CATCH_UP then
				nextTime %= duration
				break
			end

			nextTime -= duration
			self._timePosition = 0
			self._nextEventIndex = 1
			emitLoop(self)

			if self._status ~= "playing" then
				return
			end

			self._timePosition = if nextTime >= duration then duration else nextTime
			runEventsThrough(self, self._timePosition)

			if self._status ~= "playing" then
				return
			end
		end
	else
		if duration ~= nil and duration > 0 and nextTime >= duration then
			nextTime = duration
		end

		self._timePosition = nextTime
		runEventsThrough(self, self._timePosition)
	end

	if self._status ~= "playing" then
		return
	end

	for _, update in self._sequence.updates do
		if not callUser(self, update.run, self._context, dt, self._timePosition) then
			return
		end
	end

	if duration ~= nil and self._timePosition >= duration then
		finish(self, "completed", "completed", nil, true)
	end
end

return Playback
