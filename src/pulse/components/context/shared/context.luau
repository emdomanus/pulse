--!strict
--!optimize 2
--!native

local ContextTypes = require(script.Parent.Parent.Parent.Parent.types.components.context)
local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def)

export type StepId = ContextTypes.StepId
export type SeekRequest<StepT = StepId> = ContextTypes.SeekRequest<StepT>
export type CompletionReason = ContextTypes.CompletionReason
export type Context<StepT = StepId> = ContextTypes.Context<StepT>
type ContextImpl<StepT = StepId> = ContextTypes.ContextImpl<StepT>

local Context = {}
Context.__index = Context

local function isTerminalStatus(status: DefTypes.Status): boolean
	return status == "completed"
		or status == "stopped"
		or status == "cancelled"
		or status == "destroyed"
		or status == "failed"
end

function Context.new<StepT>(playback: any): Context<StepT>
	local self: ContextImpl<StepT> = setmetatable({
		_playback = playback,
	}, Context) :: any

	return self
end

function Context.getTimePosition<StepT>(self: ContextImpl<StepT>): number
	return self._playback:getTimePosition()
end

function Context.setTimePosition<StepT>(self: ContextImpl<StepT>, timePosition: number)
	self._playback:setTimePosition(timePosition)
end

function Context.seek<StepT>(self: ContextImpl<StepT>, request: SeekRequest<StepT>)
	self._playback:seek(request)
end

function Context.getPlaybackSpeed<StepT>(self: ContextImpl<StepT>): number
	return self._playback:getPlaybackSpeed()
end

function Context.setPlaybackSpeed<StepT>(self: ContextImpl<StepT>, speed: number)
	self._playback:setPlaybackSpeed(speed)
end

function Context.getStep<StepT>(self: ContextImpl<StepT>): StepT?
	return self._playback:getStep()
end

function Context.canStep<StepT>(self: ContextImpl<StepT>, step: StepT?, payload: any?): (boolean, string?)
	return self._playback:canStep(step, payload)
end

function Context.step<StepT>(self: ContextImpl<StepT>, step: StepT?, payload: any?): (boolean, string?)
	return self._playback:step(step, payload)
end

function Context.getParam<StepT>(self: ContextImpl<StepT>, name: string): any
	return self._playback:getParam(name)
end

function Context.setParam<StepT>(self: ContextImpl<StepT>, name: string, value: any)
	self._playback:setParam(name, value)
end

function Context.signal<StepT>(self: ContextImpl<StepT>, name: string, payload: any?)
	self._playback:signal(name, payload)
end

function Context.addCleanup<StepT>(self: ContextImpl<StepT>, cleanup: () -> ())
	local playback = self._playback
	if playback._cleanupHasRun or isTerminalStatus(playback._status) then
		pcall(cleanup)
		return
	end

	table.insert(playback._cleanups, cleanup)
end

function Context.pause<StepT>(self: ContextImpl<StepT>)
	self._playback:pause()
end

function Context.resume<StepT>(self: ContextImpl<StepT>)
	self._playback:resume()
end

function Context.isPaused<StepT>(self: ContextImpl<StepT>): boolean
	return self._playback:isPaused()
end

function Context.stop<StepT>(self: ContextImpl<StepT>, reason: CompletionReason?)
	self._playback:stop(reason)
end

function Context.cancel<StepT>(self: ContextImpl<StepT>, reason: CompletionReason?)
	self._playback:cancel(reason)
end

function Context.destroy<StepT>(self: ContextImpl<StepT>)
	self._playback:destroy()
end

return {
	new = Context.new,
}
