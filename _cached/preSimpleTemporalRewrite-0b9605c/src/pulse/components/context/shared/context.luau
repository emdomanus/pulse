--!strict
--!optimize 2
--!native

local ContextTypes = require(script.Parent.Parent.Parent.Parent.types.components.context)
export type StepId = ContextTypes.StepId
export type Context<StepT = StepId> = ContextTypes.Context<StepT>
type PlaybackContextPort<StepT = StepId> = ContextTypes.PlaybackContextPort<StepT>
type ContextImpl<StepT = StepId> = ContextTypes.ContextImpl<StepT>

type ContextModule = {
	new: <StepT>(playback: PlaybackContextPort<StepT>) -> Context<StepT>,
}

local Context = {}
Context.__index = Context

function Context.new<StepT>(playback: PlaybackContextPort<StepT>): Context<StepT>
	local self = (setmetatable({
		_playback = playback,
	}, Context) :: unknown) :: ContextImpl<StepT>

	return self
end

function Context.getPosition<StepT>(self: ContextImpl<StepT>): ContextTypes.PlaybackPosition
	return self._playback:getPosition()
end

function Context.seek<StepT>(self: ContextImpl<StepT>, address: ContextTypes.SequenceAddress): boolean
	return self._playback:seek(address)
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

function Context.canStep<StepT>(self: ContextImpl<StepT>, step: StepT?, payload: unknown?): (boolean, string?)
	return self._playback:canStep(step, payload)
end

function Context.step<StepT>(self: ContextImpl<StepT>, step: StepT?, payload: unknown?): (boolean, string?)
	return self._playback:step(step, payload)
end

function Context.getParam<StepT>(self: ContextImpl<StepT>, name: string): unknown
	return self._playback:getParam(name)
end

function Context.setParam<StepT>(self: ContextImpl<StepT>, name: string, value: unknown)
	self._playback:setParam(name, value)
end

function Context.signal<StepT>(self: ContextImpl<StepT>, name: string, payload: unknown?)
	self._playback:signal(name, payload)
end

function Context.addCleanup<StepT>(self: ContextImpl<StepT>, cleanup: () -> ())
	self._playback:addCleanup(cleanup)
end

function Context.pause<StepT>(self: ContextImpl<StepT>)
	self._playback:pause()
end

function Context.resume<StepT>(self: ContextImpl<StepT>)
	self._playback:resume()
end

function Context.getStatus<StepT>(self: ContextImpl<StepT>): ContextTypes.Status
	return self._playback:getStatus()
end

function Context.stop<StepT>(self: ContextImpl<StepT>, reason: string?)
	self._playback:stop(reason)
end

function Context.cancel<StepT>(self: ContextImpl<StepT>, reason: string?)
	self._playback:cancel(reason)
end

function Context.destroy<StepT>(self: ContextImpl<StepT>)
	self._playback:destroy()
end

local module: ContextModule = {
	new = Context.new,
}

return module
