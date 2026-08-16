--!strict

local Workspace = game:GetService("Workspace")

export type ScenarioKey = "rebuild" | "skip" | "cancel" | "loop"
export type EventDirection = "forward" | "reverse" | "neutral"

export type ViewModel = {
	scenarioKey: ScenarioKey,
	status: string,
	timePosition: number,
	duration: number,
	loopIndex: number,
	playbackSpeed: number,
}

export type Controller = {
	update: (self: Controller, viewModel: ViewModel, deltaTime: number) -> (),
	flash: (self: Controller, direction: EventDirection) -> (),
	destroy: (self: Controller) -> (),
}

type CameraSnapshot = {
	camera: Camera,
	cameraType: Enum.CameraType,
	cameraSubject: (BasePart | Humanoid)?,
	cframe: CFrame,
	focus: CFrame,
	fieldOfView: number,
}

type Nucleon = {
	part: Part,
	offset: Vector3,
	phase: number,
	color: Color3,
}

type Electron = {
	part: Part,
	phase: number,
}

type Orbit = {
	plane: Part,
	electrons: { Electron },
	tilt: CFrame,
	radius: number,
	speed: number,
	color: Color3,
}

type OrbitSpec = {
	tilt: CFrame,
	radius: number,
	speed: number,
	color: Color3,
}

type ControllerImpl = Controller & {
	_root: Folder,
	_backdrop: Part,
	_nucleons: { Nucleon },
	_orbits: { Orbit },
	_cameraSnapshot: CameraSnapshot?,
	_flash: number,
	_flashColor: Color3,
	_destroyed: boolean,
}

local ROOT_NAME = "PulseFunctionalStage"
local STAGE_ORIGIN = Vector3.new(0, 1_000, 0)
local CAMERA_FIELD_OF_VIEW = 42
local BASE_CAMERA_DISTANCE = 19
local STAGE_RADIUS = 5

local COLORS = table.freeze({
	background = Color3.fromRGB(8, 12, 20),
	proton = Color3.fromRGB(255, 99, 112),
	neutron = Color3.fromRGB(95, 177, 255),
	forward = Color3.fromRGB(86, 227, 167),
	reverse = Color3.fromRGB(255, 173, 92),
	rebuild = Color3.fromRGB(80, 204, 255),
	skip = Color3.fromRGB(86, 227, 167),
	cancel = Color3.fromRGB(255, 105, 122),
	loop = Color3.fromRGB(180, 120, 255),
})

local NUCLEON_OFFSETS = table.freeze({
	Vector3.new(-0.48, 0.12, 0.1),
	Vector3.new(0.44, 0.18, -0.12),
	Vector3.new(0.02, 0.54, 0.24),
	Vector3.new(-0.08, -0.5, -0.22),
	Vector3.new(0.22, 0.04, 0.52),
	Vector3.new(-0.22, -0.08, -0.5),
})

local ORBIT_SPECS: { OrbitSpec } = {
	{
		tilt = CFrame.Angles(math.rad(12), math.rad(20), math.rad(8)),
		radius = 3.6,
		speed = 1.05,
		color = Color3.fromRGB(80, 204, 255),
	},
	{
		tilt = CFrame.Angles(math.rad(68), math.rad(-18), math.rad(24)),
		radius = 4.15,
		speed = -0.82,
		color = Color3.fromRGB(180, 120, 255),
	},
	{
		tilt = CFrame.Angles(math.rad(-58), math.rad(32), math.rad(-18)),
		radius = 4.65,
		speed = 0.64,
		color = Color3.fromRGB(86, 227, 167),
	},
}

local Stage = {}

local function createPart(parent: Instance, name: string, shape: Enum.PartType): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Parent = parent
	return part
end

local function createNucleons(root: Folder): { Nucleon }
	local nucleons: { Nucleon } = {}
	for index, offset in NUCLEON_OFFSETS do
		local color = if index % 2 == 0 then COLORS.neutron else COLORS.proton
		local part = createPart(root, `Nucleon{index}`, Enum.PartType.Ball)
		part.Color = color
		part.Size = Vector3.new(1.18, 1.18, 1.18)
		part.Transparency = 0.08
		table.insert(nucleons, {
			part = part,
			offset = offset,
			phase = (index - 1) * math.pi / #NUCLEON_OFFSETS,
			color = color,
		})
	end

	local light = Instance.new("PointLight")
	light.Name = "NucleusGlow"
	light.Brightness = 2.2
	light.Color = COLORS.rebuild
	light.Range = 16
	light.Shadows = false
	light.Parent = nucleons[1].part

	return nucleons
end

local function createOrbits(root: Folder): { Orbit }
	local orbits: { Orbit } = {}
	for index, spec in ORBIT_SPECS do
		local plane = createPart(root, `OrbitPlane{index}`, Enum.PartType.Cylinder)
		plane.Color = spec.color
		plane.Size = Vector3.new(0.035, spec.radius * 2, spec.radius * 2)
		plane.Transparency = 0.935

		local electrons: { Electron } = {}
		for electronIndex = 1, 2 do
			local part = createPart(root, `Electron{index}_{electronIndex}`, Enum.PartType.Ball)
			part.Color = spec.color
			part.Size = Vector3.new(0.5, 0.5, 0.5)
			part.Transparency = 0.03

			local light = Instance.new("PointLight")
			light.Name = "ElectronGlow"
			light.Brightness = 1.2
			light.Color = spec.color
			light.Range = 5
			light.Shadows = false
			light.Parent = part

			table.insert(electrons, {
				part = part,
				phase = (electronIndex - 1) * math.pi,
			})
		end

		table.insert(orbits, {
			plane = plane,
			electrons = electrons,
			tilt = spec.tilt,
			radius = spec.radius,
			speed = spec.speed,
			color = spec.color,
		})
	end

	return orbits
end

local function scenarioColor(key: ScenarioKey): Color3
	if key == "skip" then
		return COLORS.skip
	elseif key == "cancel" then
		return COLORS.cancel
	elseif key == "loop" then
		return COLORS.loop
	end
	return COLORS.rebuild
end

local function restoreCamera(snapshot: CameraSnapshot?)
	if snapshot == nil or Workspace.CurrentCamera ~= snapshot.camera then
		return
	end
	pcall(function()
		snapshot.camera.CameraType = snapshot.cameraType
		snapshot.camera.CameraSubject = snapshot.cameraSubject
		snapshot.camera.CFrame = snapshot.cframe
		snapshot.camera.Focus = snapshot.focus
		snapshot.camera.FieldOfView = snapshot.fieldOfView
	end)
end

local function ownCamera(self: ControllerImpl)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	local snapshot = self._cameraSnapshot
	if snapshot == nil or snapshot.camera ~= camera then
		restoreCamera(snapshot)
		self._cameraSnapshot = {
			camera = camera,
			cameraType = camera.CameraType,
			cameraSubject = camera.CameraSubject,
			cframe = camera.CFrame,
			focus = camera.Focus,
			fieldOfView = camera.FieldOfView,
		}
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	camera.FieldOfView = CAMERA_FIELD_OF_VIEW

	local viewport = camera.ViewportSize
	local aspectRatio = math.max(viewport.X, 1) / math.max(viewport.Y, 1)
	local verticalTangent = math.tan(math.rad(CAMERA_FIELD_OF_VIEW * 0.5))
	local fitDistance = STAGE_RADIUS / (0.4 * verticalTangent * aspectRatio)
	local distance = math.max(BASE_CAMERA_DISTANCE, fitDistance)
	local horizontalHalfWidth = distance * verticalTangent * aspectRatio
	local cameraPosition = STAGE_ORIGIN + Vector3.new(0, 2.6, distance)
	local rightBiasedLookAt = STAGE_ORIGIN + Vector3.new(-horizontalHalfWidth * 0.5, 0, 0)
	camera.CFrame = CFrame.lookAt(cameraPosition, rightBiasedLookAt)
	camera.Focus = CFrame.new(STAGE_ORIGIN)
end

function Stage.new(): Controller
	local previousRoot = Workspace:FindFirstChild(ROOT_NAME)
	if previousRoot ~= nil then
		previousRoot:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root.Parent = Workspace

	local backdrop = createPart(root, "StageBackdrop", Enum.PartType.Block)
	backdrop.Color = COLORS.background
	backdrop.Material = Enum.Material.SmoothPlastic
	backdrop.Size = Vector3.new(15, 11, 0.2)
	backdrop.CFrame = CFrame.new(STAGE_ORIGIN + Vector3.new(0, 0, -3.2))
	backdrop.Transparency = 0.12

	return (
		{
			_root = root,
			_backdrop = backdrop,
			_nucleons = createNucleons(root),
			_orbits = createOrbits(root),
			_cameraSnapshot = nil,
			_flash = 0,
			_flashColor = COLORS.forward,
			_destroyed = false,
			update = Stage.update,
			flash = Stage.flash,
			destroy = Stage.destroy,
		} :: unknown
	) :: Controller
end

function Stage.update(self: ControllerImpl, viewModel: ViewModel, deltaTime: number)
	if self._destroyed then
		return
	end

	ownCamera(self)
	self._flash = math.max(0, self._flash - deltaTime * 2.8)

	local accent = scenarioColor(viewModel.scenarioKey)
	local unwrappedPosition = viewModel.timePosition + viewModel.loopIndex * viewModel.duration
	local motion = unwrappedPosition * math.pi * 0.72
	local breathing = (math.sin(unwrappedPosition * math.pi * 2) + 1) * 0.5
	local speedAlpha = math.clamp(math.abs(viewModel.playbackSpeed) / 3, 0, 1)
	local idleTransparency = if viewModel.status == "playing" then 0.03 else 0.28
	local flashColor = accent:Lerp(self._flashColor, self._flash)
	local clusterRotation = CFrame.Angles(motion * 0.08, motion * 0.13, motion * 0.05)
	local nucleusScale = 1 + breathing * 0.09 + self._flash * 0.24

	self._backdrop.Color = COLORS.background:Lerp(accent, 0.055 + self._flash * 0.05)
	for _, nucleon in self._nucleons do
		local drift = Vector3.new(0, math.sin(motion + nucleon.phase) * 0.055, 0)
		local offset = clusterRotation:VectorToWorldSpace(nucleon.offset + drift)
		nucleon.part.CFrame = CFrame.new(STAGE_ORIGIN + offset)
		nucleon.part.Size = Vector3.new(1.18, 1.18, 1.18) * nucleusScale
		nucleon.part.Color = nucleon.color:Lerp(flashColor, 0.18 + self._flash * 0.38)
	end

	for orbitIndex, orbit in self._orbits do
		local precession = CFrame.Angles(0, motion * 0.025 * (if orbitIndex % 2 == 0 then -1 else 1), 0)
		local orbitTransform = precession * orbit.tilt
		orbit.plane.CFrame = CFrame.new(STAGE_ORIGIN) * orbitTransform * CFrame.Angles(0, 0, math.pi / 2)
		orbit.plane.Color = orbit.color:Lerp(accent, 0.2)
		orbit.plane.Transparency = if viewModel.status == "playing" then 0.935 else 0.965

		for _, electron in orbit.electrons do
			local angle = motion * orbit.speed + electron.phase
			local localPosition = Vector3.new(math.cos(angle) * orbit.radius, 0, math.sin(angle) * orbit.radius)
			local worldPosition = STAGE_ORIGIN + orbitTransform:VectorToWorldSpace(localPosition)
			electron.part.CFrame = CFrame.new(worldPosition)
			electron.part.Size = Vector3.new(1, 1, 1) * (0.44 + speedAlpha * 0.12 + self._flash * 0.1)
			electron.part.Transparency = idleTransparency
			electron.part.Color = orbit.color:Lerp(flashColor, self._flash * 0.72)
		end
	end
end

function Stage.flash(self: ControllerImpl, direction: EventDirection)
	if self._destroyed then
		return
	end
	self._flash = 1
	self._flashColor = if direction == "reverse"
		then COLORS.reverse
		elseif direction == "forward" then COLORS.forward
		else COLORS.rebuild
end

function Stage.destroy(self: ControllerImpl)
	if self._destroyed then
		return
	end
	self._destroyed = true
	restoreCamera(self._cameraSnapshot)
	self._cameraSnapshot = nil
	if self._root.Parent ~= nil then
		self._root:Destroy()
	end
end

return Stage
