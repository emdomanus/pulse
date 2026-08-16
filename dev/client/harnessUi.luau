--!strict

export type ScenarioKey = "rebuild" | "skip" | "cancel" | "loop"

export type ViewModel = {
	scenarioKey: ScenarioKey,
	scenarioLabel: string,
	policy: string,
	status: string,
	position: number,
	duration: number,
	loopIndex: number,
	playbackSpeed: number,
	clockTime: number,
	reachedTasks: number,
	changedBindings: number,
	phaseBindings: number,
	eventCount: number,
	updateCount: number,
	lastEvent: string,
	lastEventDirection: "forward" | "reverse" | "neutral",
}

export type Callbacks = {
	selectRebuild: () -> (),
	selectSkip: () -> (),
	selectCancel: () -> (),
	selectLoop: () -> (),
	restart: () -> (),
	togglePause: () -> (),
	toggleReverse: () -> (),
	slower: () -> (),
	faster: () -> (),
	cancel: () -> (),
	seekStart: () -> (),
	seekMiddle: () -> (),
	seekEnd: () -> (),
	seekBackward: () -> (),
	seekForward: () -> (),
	clockBackward: () -> (),
	clockForward: () -> (),
	nextLoop: () -> (),
}

export type Controller = {
	update: (self: Controller, viewModel: ViewModel) -> (),
	setLogs: (self: Controller, lines: { string }) -> (),
	destroy: (self: Controller) -> (),
}

type ControllerImpl = Controller & {
	_screenGui: ScreenGui,
	_statusLabels: { [string]: TextLabel },
	_scenarioButtons: { [ScenarioKey]: TextButton },
	_timelineFill: Frame,
	_timelinePlayhead: Frame,
	_timelineEvent: TextLabel,
	_logLabel: TextLabel,
}

local COLORS = table.freeze({
	background = Color3.fromRGB(11, 15, 23),
	panel = Color3.fromRGB(17, 23, 34),
	card = Color3.fromRGB(24, 32, 46),
	cardRaised = Color3.fromRGB(31, 42, 59),
	border = Color3.fromRGB(74, 94, 121),
	text = Color3.fromRGB(239, 246, 255),
	muted = Color3.fromRGB(151, 169, 193),
	accent = Color3.fromRGB(80, 204, 255),
	accentDim = Color3.fromRGB(36, 104, 135),
	forward = Color3.fromRGB(86, 227, 167),
	reverse = Color3.fromRGB(255, 173, 92),
	danger = Color3.fromRGB(255, 105, 122),
})

local Ui = {}

local function addCorner(guiObject: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = guiObject
end

local function addStroke(guiObject: GuiObject, color: Color3, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Thickness = 1
	stroke.Parent = guiObject
end

local function addTextConstraint(textObject: TextLabel | TextButton, minimum: number, maximum: number)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minimum
	constraint.MaxTextSize = maximum
	constraint.Parent = textObject
end

local function createTextLabel(parent: Instance, name: string, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = text
	label.TextColor3 = COLORS.text
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	addTextConstraint(label, 10, 18)
	return label
end

local function createCard(parent: Instance, name: string, layoutOrder: number, height: number): Frame
	local card = Instance.new("Frame")
	card.Name = name
	card.LayoutOrder = layoutOrder
	card.Size = UDim2.fromScale(1, height)
	card.BackgroundColor3 = COLORS.card
	card.BorderSizePixel = 0
	card.Parent = parent
	addCorner(card, 10)
	addStroke(card, COLORS.border, 0.62)
	return card
end

local function createSection(
	parent: Instance,
	name: string,
	titleText: string,
	layoutOrder: number,
	height: number
): Frame
	local card = createCard(parent, name, layoutOrder, height)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.035, 0)
	padding.PaddingBottom = UDim.new(0.035, 0)
	padding.PaddingLeft = UDim.new(0.025, 0)
	padding.PaddingRight = UDim.new(0.025, 0)
	padding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.03, 0)
	layout.Parent = card

	local title = createTextLabel(card, "SectionTitle", titleText:upper())
	title.LayoutOrder = 1
	title.Size = UDim2.fromScale(1, 0.18)
	title.TextColor3 = COLORS.muted
	title.Font = Enum.Font.GothamBold
	addTextConstraint(title, 9, 13)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.LayoutOrder = 2
	content.Size = UDim2.fromScale(1, 0.72)
	content.BackgroundTransparency = 1
	content.Parent = card
	return content
end

local function createButton(parent: Instance, name: string, text: string, callback: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = true
	button.BackgroundColor3 = COLORS.cardRaised
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamMedium
	button.Text = text
	button.TextColor3 = COLORS.text
	button.TextScaled = true
	button.Parent = parent
	addCorner(button, 8)
	addStroke(button, COLORS.border, 0.65)
	addTextConstraint(button, 9, 15)
	button.Activated:Connect(callback)
	return button
end

local function addGrid(parent: Instance, columns: number, rows: number)
	local horizontalGap = 0.018
	local verticalGap = 0.1
	local grid = Instance.new("UIGridLayout")
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.FillDirectionMaxCells = columns
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.VerticalAlignment = Enum.VerticalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellPadding = UDim2.fromScale(horizontalGap, verticalGap)
	grid.CellSize =
		UDim2.fromScale((1 - horizontalGap * (columns - 1)) / columns, (1 - verticalGap * (rows - 1)) / rows)
	grid.Parent = parent
end

local function createStatusLabel(parent: Instance, name: string, order: number): TextLabel
	local label = createTextLabel(parent, name, "—")
	label.LayoutOrder = order
	label.BackgroundColor3 = COLORS.cardRaised
	label.BackgroundTransparency = 0.2
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextWrapped = true
	addCorner(label, 7)
	addTextConstraint(label, 9, 15)
	return label
end

local function createTimelineMarker(parent: Instance, progress: number, color: Color3)
	local marker = Instance.new("Frame")
	marker.Name = "EventMarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(progress, 0.5)
	marker.Size = UDim2.new(0, 2, 1.65, 0)
	marker.BackgroundColor3 = color
	marker.BorderSizePixel = 0
	marker.Parent = parent
end

function Ui.new(playerGui: PlayerGui, callbacks: Callbacks): Controller
	local previous = playerGui:FindFirstChild("PulseFunctionalHarness")
	if previous ~= nil then
		previous:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PulseFunctionalHarness"
	screenGui.DisplayOrder = 20
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.fromScale(0.015, 0.5)
	panel.Size = UDim2.fromScale(0.47, 0.94)
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.04
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	addCorner(panel, 14)
	addStroke(panel, COLORS.border, 0.25)

	local panelPadding = Instance.new("UIPadding")
	panelPadding.PaddingTop = UDim.new(0.012, 0)
	panelPadding.PaddingBottom = UDim.new(0.012, 0)
	panelPadding.PaddingLeft = UDim.new(0.022, 0)
	panelPadding.PaddingRight = UDim.new(0.022, 0)
	panelPadding.Parent = panel

	local panelLayout = Instance.new("UIListLayout")
	panelLayout.FillDirection = Enum.FillDirection.Vertical
	panelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
	panelLayout.Padding = UDim.new(0.007, 0)
	panelLayout.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.fromScale(1, 0.058)
	header.BackgroundTransparency = 1
	header.Parent = panel

	local title = createTextLabel(header, "Title", "PULSE  /  ATOM LAB")
	title.Size = UDim2.fromScale(0.64, 1)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = COLORS.accent
	addTextConstraint(title, 13, 23)

	local liveBadge = createTextLabel(header, "LiveBadge", "● LIVE PROVIDER")
	liveBadge.AnchorPoint = Vector2.new(1, 0)
	liveBadge.Position = UDim2.fromScale(1, 0)
	liveBadge.Size = UDim2.fromScale(0.34, 1)
	liveBadge.TextColor3 = COLORS.forward
	liveBadge.TextXAlignment = Enum.TextXAlignment.Right
	addTextConstraint(liveBadge, 9, 14)

	local statusContent = createSection(panel, "Status", "Runtime state", 2, 0.125)
	addGrid(statusContent, 2, 2)
	local statusLabels: { [string]: TextLabel } = {
		scenario = createStatusLabel(statusContent, "Scenario", 1),
		playback = createStatusLabel(statusContent, "Playback", 2),
		position = createStatusLabel(statusContent, "Position", 3),
		provider = createStatusLabel(statusContent, "Provider", 4),
	}

	local timelineContent = createSection(panel, "Timeline", "Traversal monitor", 3, 0.09)
	local timelineEvent = createTextLabel(timelineContent, "LastEvent", "waiting for playback")
	timelineEvent.Size = UDim2.fromScale(0.38, 1)
	timelineEvent.TextColor3 = COLORS.muted
	timelineEvent.TextWrapped = true
	addTextConstraint(timelineEvent, 8, 13)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.fromScale(1, 0.5)
	track.Size = UDim2.fromScale(0.59, 0.32)
	track.BackgroundColor3 = COLORS.cardRaised
	track.BorderSizePixel = 0
	track.ClipsDescendants = false
	track.Parent = timelineContent
	addCorner(track, 6)

	local timelineFill = Instance.new("Frame")
	timelineFill.Name = "Progress"
	timelineFill.Size = UDim2.fromScale(0, 1)
	timelineFill.BackgroundColor3 = COLORS.accentDim
	timelineFill.BorderSizePixel = 0
	timelineFill.Parent = track
	addCorner(timelineFill, 6)

	createTimelineMarker(track, 0.133, COLORS.forward)
	createTimelineMarker(track, 0.4, COLORS.forward)
	createTimelineMarker(track, 0.767, COLORS.forward)

	local timelinePlayhead = Instance.new("Frame")
	timelinePlayhead.Name = "Playhead"
	timelinePlayhead.AnchorPoint = Vector2.new(0.5, 0.5)
	timelinePlayhead.Position = UDim2.fromScale(0, 0.5)
	timelinePlayhead.Size = UDim2.new(0, 3, 1.8, 0)
	timelinePlayhead.BackgroundColor3 = COLORS.accent
	timelinePlayhead.BorderSizePixel = 0
	timelinePlayhead.Parent = track
	addCorner(timelinePlayhead, 2)

	local scenarioContent = createSection(panel, "Scenarios", "Discontinuity policy", 4, 0.13)
	addGrid(scenarioContent, 2, 2)
	local scenarioButtons: { [ScenarioKey]: TextButton } = {
		rebuild = createButton(scenarioContent, "Rebuild", "REBUILD  · replay state", callbacks.selectRebuild),
		skip = createButton(scenarioContent, "Skip", "SKIP  · jump cleanly", callbacks.selectSkip),
		cancel = createButton(scenarioContent, "Cancel", "CANCEL  · end on seek", callbacks.selectCancel),
		loop = createButton(scenarioContent, "Loop", "LOOP  · repeat traversal", callbacks.selectLoop),
	}

	local transportContent = createSection(panel, "Transport", "Playback controls", 5, 0.145)
	addGrid(transportContent, 3, 2)
	createButton(transportContent, "Restart", "RESTART", callbacks.restart)
	createButton(transportContent, "Pause", "PAUSE / RESUME", callbacks.togglePause)
	createButton(transportContent, "Reverse", "REVERSE", callbacks.toggleReverse)
	createButton(transportContent, "Slower", "SPEED −", callbacks.slower)
	createButton(transportContent, "Faster", "SPEED +", callbacks.faster)
	local cancelButton = createButton(transportContent, "Cancel", "CANCEL", callbacks.cancel)
	cancelButton.TextColor3 = COLORS.danger

	local seekContent = createSection(panel, "Discontinuities", "Playback seeks + provider jumps", 6, 0.145)
	addGrid(seekContent, 4, 2)
	createButton(seekContent, "SeekStart", "SEEK 0%", callbacks.seekStart)
	createButton(seekContent, "SeekMiddle", "SEEK 50%", callbacks.seekMiddle)
	createButton(seekContent, "SeekEnd", "SEEK 100%", callbacks.seekEnd)
	createButton(seekContent, "NextLoop", "LOOP +1", callbacks.nextLoop)
	createButton(seekContent, "SeekBackward", "SEEK −1s", callbacks.seekBackward)
	createButton(seekContent, "SeekForward", "SEEK +1s", callbacks.seekForward)
	createButton(seekContent, "ClockBackward", "CLOCK −1.5s", callbacks.clockBackward)
	createButton(seekContent, "ClockForward", "CLOCK +1.5s", callbacks.clockForward)

	local logContent = createSection(panel, "Log", "Event, update, loop, cleanup, completion", 7, 0.205)
	local logLabel = createTextLabel(logContent, "Lines", "")
	logLabel.Size = UDim2.fromScale(1, 1)
	logLabel.Font = Enum.Font.RobotoMono
	logLabel.TextColor3 = COLORS.muted
	logLabel.TextWrapped = true
	logLabel.TextXAlignment = Enum.TextXAlignment.Left
	logLabel.TextYAlignment = Enum.TextYAlignment.Top
	addTextConstraint(logLabel, 8, 13)

	local footer = createTextLabel(
		panel,
		"Shortcuts",
		"1–4 scenario  •  Space pause  •  R reverse  •  −/+ speed  •  Backspace cancel"
	)
	footer.LayoutOrder = 8
	footer.Size = UDim2.fromScale(1, 0.026)
	footer.TextColor3 = COLORS.muted
	footer.TextXAlignment = Enum.TextXAlignment.Center
	addTextConstraint(footer, 8, 12)

	return (
		{
			_screenGui = screenGui,
			_statusLabels = statusLabels,
			_scenarioButtons = scenarioButtons,
			_timelineFill = timelineFill,
			_timelinePlayhead = timelinePlayhead,
			_timelineEvent = timelineEvent,
			_logLabel = logLabel,
			update = Ui.update,
			setLogs = Ui.setLogs,
			destroy = Ui.destroy,
		} :: unknown
	) :: Controller
end

function Ui.update(self: ControllerImpl, viewModel: ViewModel)
	self._statusLabels.scenario.Text = `{viewModel.scenarioLabel:upper()}  ·  {viewModel.policy}`
	self._statusLabels.playback.Text =
		`{viewModel.status:upper()}  ·  speed {string.format("%+.2f", viewModel.playbackSpeed)}×`
	self._statusLabels.position.Text =
		string.format("%.2f / %.2fs  ·  loop %d", viewModel.position, viewModel.duration, viewModel.loopIndex)
	self._statusLabels.provider.Text = string.format(
		"clock %.1f  ·  tasks %d  ·  C/P %d/%d",
		viewModel.clockTime,
		viewModel.reachedTasks,
		viewModel.changedBindings,
		viewModel.phaseBindings
	)

	local progress = if viewModel.duration > 0 then math.clamp(viewModel.position / viewModel.duration, 0, 1) else 0
	self._timelineFill.Size = UDim2.fromScale(progress, 1)
	self._timelinePlayhead.Position = UDim2.fromScale(progress, 0.5)
	local directionColor = if viewModel.lastEventDirection == "forward"
		then COLORS.forward
		elseif viewModel.lastEventDirection == "reverse" then COLORS.reverse
		else COLORS.muted
	self._timelinePlayhead.BackgroundColor3 = directionColor
	self._timelineEvent.TextColor3 = directionColor
	self._timelineEvent.Text = `{viewModel.lastEvent}  ·  E{viewModel.eventCount} / U{viewModel.updateCount}`

	for key, button in self._scenarioButtons do
		local selected = key == viewModel.scenarioKey
		button.BackgroundColor3 = if selected then COLORS.accentDim else COLORS.cardRaised
		button.TextColor3 = if selected then COLORS.text else COLORS.muted
	end
end

function Ui.setLogs(self: ControllerImpl, lines: { string })
	self._logLabel.Text = table.concat(lines, "\n")
end

function Ui.destroy(self: ControllerImpl)
	if self._screenGui.Parent ~= nil then
		self._screenGui:Destroy()
	end
end

return Ui
