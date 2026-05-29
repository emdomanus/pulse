--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local packages = ReplicatedStorage:WaitForChild("packages")
local Pulse = require(packages:WaitForChild("pulse"))
local Tempo = require(packages:WaitForChild("roblox_packages"):WaitForChild("tempo"))

type LoopStepId = "orbit"
type GatedStepId = "start" | "charge" | "release" | "finish"
type CleanupStepId = "burst" | "done"
type AnyPlayback = Pulse.Playback<any>

local player = Players.LocalPlayer

local tempo = Tempo.new({
	protected = true,
})

RunService.Heartbeat:Connect(tempo:evaluatePhase(tempo.phases.heartbeat))

local runtime = Pulse.Runtime.new({
	tempo = tempo,
	phase = tempo.phases.heartbeat,
})

local activePlayback: AnyPlayback? = nil
local activeName = "none"
local activeScale = 1

local logLines: { string } = {}
local atomOrigin = Vector3.new(0, 8, 0)
local nucleusColorA = Color3.fromRGB(255, 80, 70)
local nucleusColorB = Color3.fromRGB(80, 180, 255)
local gatedColor = Color3.fromRGB(255, 235, 130)

local visualFolder = Instance.new("Folder")
visualFolder.Name = "PulseDevAtom"
visualFolder.Parent = Workspace

local function createSphere(name: string, size: number, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(size, size, size)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = visualFolder

	return part
end

local nucleus = createSphere("Nucleus", 2.25, nucleusColorA)
local electrons: { Part } = {
	createSphere("Electron1", 0.55, Color3.fromRGB(120, 230, 255)),
	createSphere("Electron2", 0.55, Color3.fromRGB(180, 120, 255)),
	createSphere("Electron3", 0.55, Color3.fromRGB(120, 255, 170)),
}

local camera = Workspace.CurrentCamera
if camera then
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(atomOrigin + Vector3.new(0, 3.25, 13), atomOrigin)
end

local function setAtomVisible(visible: boolean)
	local transparency = if visible then 0 else 1
	nucleus.Transparency = transparency

	for _, electron in electrons do
		electron.Transparency = transparency
	end
end

local function updateAtom(timePosition: number, scale: number, gatedBlend: number)
	local pulse = (math.sin(timePosition * math.pi * 2) + 1) * 0.5
	local radius = 3.5 * scale
	local baseColor = nucleusColorA:Lerp(nucleusColorB, pulse)

	nucleus.CFrame = CFrame.new(atomOrigin)
	nucleus.Color = baseColor:Lerp(gatedColor, gatedBlend)
	nucleus.Size = Vector3.new(1, 1, 1) * ((2.25 + pulse * 0.4) * scale)

	for index, electron in electrons do
		local phase = (index - 1) * ((math.pi * 2) / #electrons)
		local angle = timePosition * math.pi * 2 + phase
		local tilt = CFrame.Angles(math.rad(65), phase, math.rad(25))
		local localPosition = tilt:VectorToWorldSpace(Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))

		electron.CFrame = CFrame.new(atomOrigin + localPosition)
	end
end

local function log(message: string)
	local line = (`[{string.format("%.2f", os.clock())}] {message}`)
	table.insert(logLines, line)

	if #logLines > 12 then
		table.remove(logLines, 1)
	end

	print("[Pulse Dev]", message)
end

local loopBuilder: Pulse.Builder<LoopStepId> = Pulse.define()
local loopSequence = loopBuilder
	:duration(3)
	:cleanupDelay(0.75)
	:seekMode("procedural" :: "procedural")
	:loop()
	:param("scale", 1)
	:step("orbit", 0, function(_ctx: Pulse.CallbackContext)
		log("loop step orbit")
	end)
	:event(0, "orbit", function(ctx: Pulse.CallbackContext)
		log(`loop event scale={ctx:getParam("scale")}`)
	end)
	:update("loopAtom", function(ctx: Pulse.CallbackContext, _dt: number, timePosition: number)
		local scale = (ctx:getParam("scale") :: number?) or 1
		updateAtom(timePosition, scale, 0)
	end)
	:onPlay(function(ctx: Pulse.CallbackContext)
		setAtomVisible(true)
		ctx:addCleanup(function()
			setAtomVisible(false)
			log("loop cleanup")
		end)
		log("loop play")
	end)
	:onLoop(function(_ctx: Pulse.CallbackContext, loopCount: number)
		log(`loop count {loopCount}`)
	end)
	:onStop(function(_ctx: Pulse.CallbackContext, reason)
		log(`loop stop {tostring(reason)}`)
	end)
	:onCancel(function(_ctx: Pulse.CallbackContext, reason)
		setAtomVisible(false)
		log(`loop cancel {tostring(reason)}`)
	end)
	:onDestroy(function()
		setAtomVisible(false)
		log("loop destroy")
	end)
	:onParamChanged(function(_ctx: Pulse.CallbackContext, name: string, value: any, oldValue: any?)
		log(`loop param {name}: {tostring(oldValue)} -> {tostring(value)}`)
	end)
	:compile()

local gatedBuilder: Pulse.Builder<GatedStepId> = Pulse.define()
local gatedSequence = gatedBuilder
	:duration(2.35)
	:cleanupDelay(1.25)
	:seekMode("procedural" :: "procedural")
	:param("scale", 1)
	:step("start", 0, function(_ctx: Pulse.CallbackContext)
		log("gated step start")
	end)
	:step("charge", 0.65, function(_ctx: Pulse.CallbackContext)
		log("gated step charge")
	end)
	:step("release", 1.3, function(_ctx: Pulse.CallbackContext)
		log("gated step release")
	end)
	:step("finish", 2, function(_ctx: Pulse.CallbackContext)
		log("gated step finish")
	end)
	:event(0, "start", function(_ctx: Pulse.CallbackContext)
		log("gated event start")
	end)
	:hold(0.65, "charge", "proceed")
	:hold(1.3, "release", "proceed")
	:event(2, "finish", function(_ctx: Pulse.CallbackContext)
		log("gated event finish")
	end)
	:update("gatedAtom", function(ctx: Pulse.CallbackContext, _dt: number, timePosition: number)
		local scale = (ctx:getParam("scale") :: number?) or 1
		local gatedBlend = math.clamp(timePosition / 2, 0, 1)
		updateAtom(timePosition * 0.75, scale, gatedBlend)
	end)
	:signal("proceed", function(ctx: Pulse.CallbackContext, payload)
		log(`gated proceed {tostring(payload)}`)
		ctx:resume()
	end)
	:onPlay(function(ctx: Pulse.CallbackContext)
		setAtomVisible(true)
		ctx:addCleanup(function()
			setAtomVisible(false)
			log("gated cleanup after delay")
		end)
		log("gated play")
	end)
	:onStep(function(_ctx: Pulse.CallbackContext, from, to)
		log(`gated step {tostring(from)} -> {tostring(to)}`)
	end)
	:onStop(function(_ctx: Pulse.CallbackContext, reason)
		log(`gated stop {tostring(reason)}`)
	end)
	:onCancel(function(_ctx: Pulse.CallbackContext, reason)
		setAtomVisible(false)
		log(`gated cancel {tostring(reason)}`)
	end)
	:onDestroy(function()
		setAtomVisible(false)
		log("gated destroy")
	end)
	:compile()

local cleanupBuilder: Pulse.Builder<CleanupStepId> = Pulse.define()
local cleanupSequence = cleanupBuilder
	:duration(0.7)
	:cleanupDelay(1.75)
	:seekMode("procedural" :: "procedural")
	:param("scale", 1)
	:step("burst", 0, function(_ctx: Pulse.CallbackContext)
		log("cleanup step burst")
	end)
	:step("done", 0.7, function(_ctx: Pulse.CallbackContext)
		log("cleanup step done")
	end)
	:event(0, "burst", function(_ctx: Pulse.CallbackContext)
		log("cleanup event burst")
	end)
	:event(0.7, "done", function(_ctx: Pulse.CallbackContext)
		log("cleanup completed timeline; linger begins")
	end)
	:update("cleanupAtom", function(ctx: Pulse.CallbackContext, _dt: number, timePosition: number)
		local scale = (ctx:getParam("scale") :: number?) or 1
		local alpha = math.clamp(timePosition / 0.7, 0, 1)
		updateAtom(timePosition * 2.2, scale + alpha * 0.45, 1 - alpha * 0.25)
	end)
	:onPlay(function(ctx: Pulse.CallbackContext)
		setAtomVisible(true)
		ctx:addCleanup(function()
			setAtomVisible(false)
			log("cleanup delayed cleanup fired")
		end)
		log("cleanup play")
	end)
	:onStop(function(_ctx: Pulse.CallbackContext, reason)
		log(`cleanup stop {tostring(reason)}`)
	end)
	:onCancel(function(_ctx: Pulse.CallbackContext, reason)
		setAtomVisible(false)
		log(`cleanup cancel {tostring(reason)}`)
	end)
	:onDestroy(function()
		setAtomVisible(false)
		log("cleanup destroy")
	end)
	:compile()
updateAtom(0, 1, 0)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PulseDevControls"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.fromOffset(16, 16)
panel.Size = UDim2.fromOffset(360, 352)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = screenGui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.fromOffset(336, 24)
title.Font = Enum.Font.Code
title.Text = "Pulse Dev"
title.TextColor3 = Color3.fromRGB(245, 245, 245)
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.BackgroundTransparency = 1
statusLabel.Position = UDim2.fromOffset(12, 36)
statusLabel.Size = UDim2.fromOffset(336, 54)
statusLabel.Font = Enum.Font.Code
statusLabel.TextColor3 = Color3.fromRGB(205, 225, 255)
statusLabel.TextSize = 14
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Parent = panel

local logLabel = Instance.new("TextLabel")
logLabel.Name = "Log"
logLabel.BackgroundTransparency = 1
logLabel.Position = UDim2.fromOffset(12, 232)
logLabel.Size = UDim2.fromOffset(336, 108)
logLabel.Font = Enum.Font.Code
logLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
logLabel.TextSize = 12
logLabel.TextXAlignment = Enum.TextXAlignment.Left
logLabel.TextYAlignment = Enum.TextYAlignment.Top
logLabel.TextWrapped = false
logLabel.Parent = panel

local function makeButton(text: string, column: number, row: number, callback: () -> ())
	local button = Instance.new("TextButton")
	button.Name = text:gsub("%W", "")
	button.Position = UDim2.fromOffset(12 + column * 116, 96 + row * 34)
	button.Size = UDim2.fromOffset(108, 28)
	button.BackgroundColor3 = Color3.fromRGB(42, 48, 60)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.Code
	button.Text = text
	button.TextColor3 = Color3.fromRGB(245, 245, 245)
	button.TextSize = 13
	button.Parent = panel
	button.Activated:Connect(callback)

	return button
end

local function destroyActive()
	if activePlayback and activePlayback:isAlive() then
		activePlayback:destroy()
	end

	activePlayback = nil
	activeName = "none"
end

local function setActive(playback: AnyPlayback, name: string)
	activePlayback = playback
	activeName = name
	activeScale = ((playback:getParam("scale") :: number?) or 1)
end

local function playLoop()
	destroyActive()

	local playback = runtime:play(loopSequence, {
		params = {
			scale = activeScale,
		},
	})

	setActive(playback :: any, "loop")
	playback.Looped:add(function(loopCount)
		log(`loop hook {loopCount}`)
	end)
end

local function playGated()
	destroyActive()

	local playback = runtime:play(gatedSequence, {
		params = {
			scale = activeScale,
		},
	})

	setActive(playback :: any, "gated")
	playback.Ended:add(function(completion)
		log(`gated ended {completion.status}/{completion.reason}`)
	end)
end

local function playCleanup()
	destroyActive()

	local playback = runtime:play(cleanupSequence, {
		params = {
			scale = activeScale,
		},
	})

	setActive(playback :: any, "cleanup")
	playback.Ended:add(function(completion)
		log(`cleanup ended {completion.status}/{completion.reason}; atom should linger`)
	end)
end

local function adjustSpeed(delta: number)
	if not activePlayback then
		return
	end

	local nextSpeed = math.clamp(activePlayback:getPlaybackSpeed() + delta, 0.1, 3)
	activePlayback:setPlaybackSpeed(nextSpeed)
	log(`speed {string.format("%.2f", nextSpeed)}`)
end

local function adjustScale(delta: number)
	activeScale = math.clamp(activeScale + delta, 0.35, 2.5)

	if activePlayback then
		activePlayback:setParam("scale", activeScale)
	end

	log(`scale {string.format("%.2f", activeScale)}`)
end

local function proceed()
	if activePlayback then
		activePlayback:signal("proceed", "ui")
	end
end

local function togglePause()
	if not activePlayback then
		return
	end

	if activePlayback:isPaused() then
		activePlayback:resume()
		log("manual resume")
	else
		activePlayback:pause()
		log("manual pause")
	end
end

local function seekHalf()
	if activePlayback then
		activePlayback:seek({
			timePosition = 0.5,
			replay = true,
		})
	end
end

local function cancelActive()
	if activePlayback then
		activePlayback:cancel("manualCancel")
	end
end

makeButton("Loop", 0, 0, playLoop)
makeButton("Gated", 1, 0, playGated)
makeButton("Cancel", 2, 0, cancelActive)
makeButton("Speed -", 0, 1, function()
	adjustSpeed(-0.25)
end)
makeButton("Speed +", 1, 1, function()
	adjustSpeed(0.25)
end)
makeButton("Pause", 2, 1, togglePause)
makeButton("Scale -", 0, 2, function()
	adjustScale(-0.15)
end)
makeButton("Scale +", 1, 2, function()
	adjustScale(0.15)
end)
makeButton("Seek .5", 2, 2, seekHalf)
makeButton("Proceed", 0, 3, proceed)
makeButton("Cleanup", 1, 3, playCleanup)

local function bindKey(name: string, keyCode: Enum.KeyCode, callback: () -> ())
	ContextActionService:BindAction(name, function(_, state)
		if state == Enum.UserInputState.Begin then
			callback()
		end

		return Enum.ContextActionResult.Sink
	end, false, keyCode)
end

bindKey("PulseDevLoop", Enum.KeyCode.One, playLoop)
bindKey("PulseDevGated", Enum.KeyCode.Two, playGated)
bindKey("PulseDevSpeedDown", Enum.KeyCode.Three, function()
	adjustSpeed(-0.25)
end)
bindKey("PulseDevSpeedUp", Enum.KeyCode.Four, function()
	adjustSpeed(0.25)
end)
bindKey("PulseDevScaleDown", Enum.KeyCode.Five, function()
	adjustScale(-0.15)
end)
bindKey("PulseDevScaleUp", Enum.KeyCode.Six, function()
	adjustScale(0.15)
end)
bindKey("PulseDevProceed", Enum.KeyCode.Seven, proceed)
bindKey("PulseDevPause", Enum.KeyCode.Eight, togglePause)
bindKey("PulseDevCancel", Enum.KeyCode.Nine, cancelActive)
bindKey("PulseDevCleanup", Enum.KeyCode.Zero, playCleanup)

RunService.RenderStepped:Connect(function()
	local status = if activePlayback then activePlayback:getStatus() else "none"
	local speed = if activePlayback then activePlayback:getPlaybackSpeed() else 0
	local timePosition = if activePlayback then activePlayback:getTimePosition() else 0
	local step = if activePlayback then tostring(activePlayback:getStep()) else "nil"

	statusLabel.Text = string.format(
		"mode: %s  status: %s\nspeed: %.2f  scale: %.2f  time: %.2f\nstep: %s",
		activeName,
		status,
		speed,
		activeScale,
		timePosition,
		step
	)

	logLabel.Text = table.concat(logLines, "\n")
end)

setAtomVisible(true)
playLoop()
log("keys: 1 loop, 2 gated, 0 cleanup, 3/4 speed, 5/6 scale, 7 proceed, 8 pause, 9 cancel")
