--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AtomStage = require(script.atomStage)
local LiveClock = require(script.liveClock)
local HarnessUi = require(script.harnessUi)

local packages = ReplicatedStorage:WaitForChild("packages")
local Pulse = require(packages:WaitForChild("pulse"))

type AddressMode = Pulse.AddressMode
type DriverDiscontinuityMode = Pulse.DriverDiscontinuityMode
type Playback = Pulse.DrivenPlayback
type PlaybackControl = Pulse.PlaybackControl
type Sequence = Pulse.Sequence<nil>
type StageController = AtomStage.Controller
type ScenarioKey = HarnessUi.ScenarioKey
type UiController = HarnessUi.Controller

type Scenario = {
	key: ScenarioKey,
	label: string,
	addressMode: AddressMode,
	discontinuityMode: DriverDiscontinuityMode,
	looping: boolean,
	sequence: Sequence,
}

type EventDirection = AtomStage.EventDirection

local player = Players.LocalPlayer
local clock = LiveClock.new()
local phase: LiveClock.Phase = "heartbeat"
local driver = Pulse.clockDriver(clock, phase, clock.directions)

local activePlayback: Playback? = nil
local activeScenario: Scenario? = nil
local configuredSpeed = 1
local eventCount = 0
local sampleCount = 0
local lastEvent = "waiting for playback"
local lastEventDirection: EventDirection = "neutral"
local logLines: { string } = {}
local ui: UiController? = nil
local stage: StageController? = nil

local function record(message: string, direction: EventDirection?)
	if direction ~= nil then
		lastEventDirection = direction
		lastEvent = message
	end
	local timePosition = clock:read().timePosition
	table.insert(logLines, string.format("[%7.2f] %s", timePosition, message))
	while #logLines > 6 do
		table.remove(logLines, 1)
	end
	print(`[Pulse Dev] {message}`)
	local currentUi = ui
	if currentUi ~= nil then
		currentUi:setLogs(logLines)
	end
end

local function runEvent(label: string, marker: string, direction: EventDirection)
	eventCount += 1
	local currentStage = stage
	if currentStage ~= nil then
		currentStage:flash(direction)
	end
	local arrow = if direction == "forward" then "→" else "←"
	record(`{arrow} {label} / {marker}`, direction)
end

local function createScenarioSequence(label: string, looping: boolean): Sequence
	local builder: Pulse.Builder<nil> = Pulse.builder()
	return builder
		:duration(6)
		:loop(looping)
		:onPlay(function(playback: PlaybackControl)
			record(`{label}: generation began`, "neutral")
			playback:addCleanup(function()
				record(`{label}: generation cleanup`, "neutral")
			end)
		end)
		:event({
			time = 0.8,
			run = function()
				runEvent(label, "ignite @ 0.8", "forward")
			end,
			reverse = function()
				runEvent(label, "undo ignite @ 0.8", "reverse")
			end,
		})
		:event({
			time = 2.4,
			run = function()
				runEvent(label, "pulse @ 2.4", "forward")
			end,
			reverse = function()
				runEvent(label, "undo pulse @ 2.4", "reverse")
			end,
		})
		:event({
			time = 4.6,
			run = function()
				runEvent(label, "release @ 4.6", "forward")
			end,
			reverse = function()
				runEvent(label, "undo release @ 4.6", "reverse")
			end,
		})
		:sample({
			startTime = 0,
			endTime = 6,
			run = function(_playback: PlaybackControl, _sample: Pulse.SampleInfo)
				sampleCount += 1
			end,
		})
		:onLoop(function(_playback: PlaybackControl, change: Pulse.LoopChange)
			local direction: EventDirection = if change.direction == "forward" then "forward" else "reverse"
			record(`{label}: loop {change.fromLoopIndex} → {change.toLoopIndex} ({change.direction})`, direction)
		end)
		:compile()
end

local scenarios: { [ScenarioKey]: Scenario } = {
	reconstruct = {
		key = "reconstruct",
		label = "Reconstruct",
		addressMode = "reconstruct",
		discontinuityMode = "reconstruct",
		looping = false,
		sequence = createScenarioSequence("Reconstruct", false),
	},
	skip = {
		key = "skip",
		label = "Skip",
		addressMode = "skip",
		discontinuityMode = "skip",
		looping = false,
		sequence = createScenarioSequence("Skip", false),
	},
	cancel = {
		key = "cancel",
		label = "Cancel",
		addressMode = "skip",
		discontinuityMode = "cancel",
		looping = false,
		sequence = createScenarioSequence("Cancel", false),
	},
	loop = {
		key = "loop",
		label = "Loop",
		addressMode = "reconstruct",
		discontinuityMode = "reconstruct",
		looping = true,
		sequence = createScenarioSequence("Loop", true),
	},
}

local function getActive(): (Playback?, Scenario?)
	return activePlayback, activeScenario
end

local function startScenario(key: ScenarioKey)
	local previous = activePlayback
	if previous ~= nil and previous:isAlive() then
		previous:destroy()
	end

	local scenario = scenarios[key]
	activeScenario = scenario
	eventCount = 0
	sampleCount = 0
	lastEvent = `${scenario.label} ready`
	lastEventDirection = "neutral"
	local initialPosition = if configuredSpeed < 0 and not scenario.looping then scenario.sequence:getDuration() else 0
	local rawPlayback = Pulse.playback(scenario.sequence, nil, {
		playbackSpeed = configuredSpeed,
		position = {
			timePosition = initialPosition,
		},
		initialMode = scenario.addressMode,
	})
	local playback = driver:attach(rawPlayback, {
		discontinuityMode = scenario.discontinuityMode,
	})
	activePlayback = playback
	playback:onLooped(function(change)
		record(
			`observer: loop {change.fromLoopIndex} → {change.toLoopIndex} ({change.direction})`,
			if change.direction == "forward" then "forward" else "reverse"
		)
	end)
	playback:onEnded(function(completion)
		record(`completion: {completion.status} / {completion.reason or "no reason"}`, "neutral")
	end)
	playback:play()
	record(`started {scenario.label} mode at {string.format("%+.2f", configuredSpeed)}×`, "neutral")
end

local function restart()
	local scenario = activeScenario
	startScenario(if scenario == nil then "reconstruct" else scenario.key)
end

local function togglePause()
	local playback = activePlayback
	if playback == nil or not playback:isAlive() then
		record("pause ignored: no live playback", "neutral")
		return
	end
	if playback:getStatus() == "paused" then
		playback:resume()
		record("resumed playback", "neutral")
	elseif playback:getStatus() == "playing" then
		playback:pause()
		record("paused playback", "neutral")
	end
end

local function setSpeed(speed: number)
	configuredSpeed = speed
	local playback = activePlayback
	if playback ~= nil and playback:isAlive() then
		playback:setPlaybackSpeed(speed)
	end
	record(`playback speed {string.format("%+.2f", speed)}×`, "neutral")
end

local function adjustSpeed(delta: number)
	local playback = activePlayback
	local current = if playback ~= nil then playback:getPlaybackSpeed() else configuredSpeed
	local sign = if current < 0 then -1 else 1
	local magnitude = math.clamp(math.abs(current) + delta, 0.25, 3)
	setSpeed(sign * magnitude)
end

local function toggleReverse()
	local playback = activePlayback
	local current = if playback ~= nil then playback:getPlaybackSpeed() else configuredSpeed
	setSpeed(if current == 0 then -1 else -current)
end

local function seekTo(timePosition: number, loopOffset: number?)
	local playback, scenario = getActive()
	if playback == nil or scenario == nil or not playback:isAlive() then
		record("seek ignored: no live playback", "neutral")
		return
	end
	local current = playback:getPosition()
	local address: Pulse.SequenceAddress = {
		timePosition = math.clamp(timePosition, 0, scenario.sequence:getDuration()),
	}
	if scenario.looping then
		address.loopIndex = current.loopIndex + (loopOffset or 0)
	end
	local accepted = playback:seek(address, scenario.addressMode)
	record(
		string.format(
			"seek %s to %.2f%s",
			if accepted then "accepted" else "rejected",
			address.timePosition,
			if address.loopIndex == nil then "" else ` / loop {address.loopIndex}`
		),
		"neutral"
	)
end

local function seekFraction(fraction: number)
	local scenario = activeScenario
	if scenario ~= nil then
		seekTo(scenario.sequence:getDuration() * fraction)
	end
end

local function seekRelative(delta: number)
	local playback = activePlayback
	if playback ~= nil then
		seekTo(playback:getPosition().timePosition + delta)
	end
end

local function nextLoop()
	local playback, scenario = getActive()
	if playback == nil or scenario == nil or not scenario.looping then
		record("loop +1 is available in the Loop scenario", "neutral")
		return
	end
	seekTo(playback:getPosition().timePosition, 1)
end

local function jumpClock(delta: number)
	clock:jumpBy(delta)
	record(`provider discontinuity {string.format("%+.1f", delta)}s`, "neutral")
end

local function cancelActive()
	local playback = activePlayback
	if playback ~= nil and playback:isAlive() then
		playback:cancel("manualHarnessCancel")
	else
		record("cancel ignored: no live playback", "neutral")
	end
end

local callbacks: HarnessUi.Callbacks = {
	selectReconstruct = function()
		startScenario("reconstruct")
	end,
	selectSkip = function()
		startScenario("skip")
	end,
	selectCancel = function()
		startScenario("cancel")
	end,
	selectLoop = function()
		startScenario("loop")
	end,
	restart = restart,
	togglePause = togglePause,
	toggleReverse = toggleReverse,
	slower = function()
		adjustSpeed(-0.25)
	end,
	faster = function()
		adjustSpeed(0.25)
	end,
	cancel = cancelActive,
	seekStart = function()
		seekFraction(0)
	end,
	seekMiddle = function()
		seekFraction(0.5)
	end,
	seekEnd = function()
		seekFraction(1)
	end,
	seekBackward = function()
		seekRelative(-1)
	end,
	seekForward = function()
		seekRelative(1)
	end,
	clockBackward = function()
		jumpClock(-1.5)
	end,
	clockForward = function()
		jumpClock(1.5)
	end,
	nextLoop = nextLoop,
}

local controller = HarnessUi.new(player:WaitForChild("PlayerGui") :: PlayerGui, callbacks)
ui = controller
controller:setLogs(logLines)
local stageController = AtomStage.new()
stage = stageController

local heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
	clock:step(deltaTime)
end)

local renderConnection = RunService.RenderStepped:Connect(function(deltaTime)
	local playback, scenario = getActive()
	if playback == nil or scenario == nil then
		return
	end
	local position = playback:getPosition()
	local diagnostics = clock:getDiagnostics()
	stageController:update({
		scenarioKey = scenario.key,
		status = playback:getStatus(),
		timePosition = position.timePosition,
		duration = scenario.sequence:getDuration(),
		loopIndex = position.loopIndex,
		playbackSpeed = playback:getPlaybackSpeed(),
	}, deltaTime)
	controller:update({
		scenarioKey = scenario.key,
		scenarioLabel = scenario.label,
		mode = scenario.discontinuityMode,
		status = playback:getStatus(),
		position = position.timePosition,
		duration = scenario.sequence:getDuration(),
		loopIndex = position.loopIndex,
		playbackSpeed = playback:getPlaybackSpeed(),
		clockTime = clock:read().timePosition,
		reachedTasks = diagnostics.reachedTasks,
		changedBindings = diagnostics.changedBindings,
		phaseBindings = diagnostics.phaseBindings,
		eventCount = eventCount,
		sampleCount = sampleCount,
		lastEvent = lastEvent,
		lastEventDirection = lastEventDirection,
	})
end)

local inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local keyCode = input.KeyCode
	if keyCode == Enum.KeyCode.One then
		startScenario("reconstruct")
	elseif keyCode == Enum.KeyCode.Two then
		startScenario("skip")
	elseif keyCode == Enum.KeyCode.Three then
		startScenario("cancel")
	elseif keyCode == Enum.KeyCode.Four then
		startScenario("loop")
	elseif keyCode == Enum.KeyCode.Space then
		togglePause()
	elseif keyCode == Enum.KeyCode.R then
		toggleReverse()
	elseif keyCode == Enum.KeyCode.Minus then
		adjustSpeed(-0.25)
	elseif keyCode == Enum.KeyCode.Equals then
		adjustSpeed(0.25)
	elseif keyCode == Enum.KeyCode.Backspace then
		cancelActive()
	end
end)

local cleanedUp = false
local function cleanup()
	if cleanedUp then
		return
	end
	cleanedUp = true
	heartbeatConnection:Disconnect()
	renderConnection:Disconnect()
	inputConnection:Disconnect()

	local playback = activePlayback
	activePlayback = nil
	if playback ~= nil and playback:isAlive() then
		playback:destroy()
	end
	driver:destroy()
	clock:destroy()
	controller:destroy()
	stageController:destroy()
	stage = nil
	ui = nil
end

script.Destroying:Connect(cleanup)

startScenario("reconstruct")
record("ready: traverse events, seek, jump the provider, loop, reverse, and cancel", "neutral")
