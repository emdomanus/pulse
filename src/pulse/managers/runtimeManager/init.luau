--!strict
--!optimize 2
--!native

local RuntimeManagerTypes = require(script.Parent.Parent.types.managers.runtimeManager)
local Playback = require(script.Parent.Parent.components.playback)

export type Runtime<PhaseT> = RuntimeManagerTypes.Runtime<PhaseT>
export type RuntimeOptions<PhaseT> = RuntimeManagerTypes.RuntimeOptions<PhaseT>
type RuntimeImpl<PhaseT> = RuntimeManagerTypes.RuntimeImpl<PhaseT>

local RuntimeManager = {}
RuntimeManager.__index = RuntimeManager

function RuntimeManager.new<PhaseT>(_options: RuntimeOptions<PhaseT>): Runtime<PhaseT>
	local options = _options
	local self: RuntimeImpl<PhaseT> = setmetatable({
		_options = options,
		_playbacks = {},
		_unbind = nil,
	}, RuntimeManager) :: any

	local phase = options.phase or options.tempo.phases.heartbeat
	self._unbind = options.tempo:bindPhase(phase, function(dt: number)
		for index = #self._playbacks, 1, -1 do
			local playback = self._playbacks[index]
			local playbackImpl = playback :: any
			playbackImpl:_update(dt)

			if not playback:isAlive() then
				local last = self._playbacks[#self._playbacks]
				self._playbacks[index] = last
				self._playbacks[#self._playbacks] = nil :: any
			end
		end
	end)

	return self
end

function RuntimeManager.play<PhaseT, StepT>(
	self: RuntimeImpl<PhaseT>,
	sequence: RuntimeManagerTypes.Sequence<StepT>,
	request: RuntimeManagerTypes.PlayRequest<StepT>?
): RuntimeManagerTypes.Playback<StepT>
	local playback = Playback.new(sequence, request) :: RuntimeManagerTypes.PlaybackImpl<StepT>
	table.insert(self._playbacks, playback :: any)

	if request == nil or request.autoPlay ~= false then
		playback:play()
	end

	return playback
end

function RuntimeManager.destroy<PhaseT>(self: RuntimeImpl<PhaseT>)
	local unbind = self._unbind
	if unbind ~= nil then
		unbind()
		self._unbind = nil
	end

	for _, playback in self._playbacks do
		playback:destroy()
	end

	table.clear(self._playbacks)
end

return RuntimeManager
