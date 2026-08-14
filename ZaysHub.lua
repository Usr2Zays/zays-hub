--[[
	Zays Hub

	Outil QA/admin LOCAL et autonome pour une expérience Roblox que vous possédez.
	Collez tout ce code directement dans un LocalScript placé dans :
	StarterPlayer > StarterPlayerScripts

	IMPORTANT :
	- Aucune liste d'UserIds ni configuration d'autorisation n'est nécessaire.
	- Tout joueur qui reçoit ce LocalScript peut ouvrir l'outil.
	- Toutes les fonctions restent locales au client.
	- Les contrôles du Fly utilisent le clavier AZERTY : Z/Q/S/D.
]]

--=====================================================================
-- Services et garde de sécurité
--=====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	warn("[Zays Hub] Ce code doit être placé dans un LocalScript.")
	return
end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local oldGui = PlayerGui:FindFirstChild("ZaysHub_HUD")
if oldGui then
	oldGui:Destroy()
end

local oldVisuals = Workspace:FindFirstChild("ZaysHub_Visuals_" .. LocalPlayer.UserId)
if oldVisuals then
	oldVisuals:Destroy()
end

--=====================================================================
-- Configuration et état
--=====================================================================

local THEME = {
	Background = Color3.fromRGB(250, 244, 246),
	Panel = Color3.fromRGB(255, 255, 255),
	PanelAlt = Color3.fromRGB(255, 232, 237),
	Hover = Color3.fromRGB(255, 214, 222),
	Stroke = Color3.fromRGB(232, 27, 58),
	Text = Color3.fromRGB(91, 10, 25),
	TextOnAccent = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(145, 72, 86),
	Accent = Color3.fromRGB(232, 27, 58),
	AccentHover = Color3.fromRGB(255, 52, 82),
	AccentSoft = Color3.fromRGB(255, 204, 214),
	AccentDark = Color3.fromRGB(150, 12, 37),
	On = Color3.fromRGB(232, 27, 58),
	Off = Color3.fromRGB(255, 222, 229),
	Danger = Color3.fromRGB(255, 52, 78),
}

local state = {
	menuOpen = true,

	fly = false,
	flySpeed = 65,
	noclip = false,
	carFly = false,
	carFlySpeed = 95,

	invisible = false,
	aimBot = false,
	aimPart = "Head",
	aimFov = 180, -- Rayon en pixels.
	aimSmoothness = 8, -- 1 = instantané, valeur élevée = plus doux.
	aimMaxDistance = 750,

	esp = false,
	nameEsp = false,
	skeletonEsp = false,
	healthEsp = false,
	distanceEsp = false,
	roleEsp = false,
}

-- Roblox représente les touches par leur position QWERTY physique.
-- Sur un clavier AZERTY : KeyCode.W = touche Z et KeyCode.A = touche Q.
-- Ces valeurs donnent donc bien Z/Q/S/D au joueur.
local KEYBINDS = {
	Forward = Enum.KeyCode.W, -- Z sur AZERTY
	Left = Enum.KeyCode.A, -- Q sur AZERTY
	Backward = Enum.KeyCode.S,
	Right = Enum.KeyCode.D,
	Up = Enum.KeyCode.Space,
	Down = Enum.KeyCode.LeftControl,
	DownAlt = Enum.KeyCode.RightControl,
}

local heldKeys = {}
local currentCharacter = nil
local currentHumanoid = nil
local currentRoot = nil
local characterSerial = 0
local characterDescendantConnection = nil

local originalCollisions = {}
local invisibleOriginals = {}
local flyHumanoidOriginals = setmetatable({}, { __mode = "k" })
local flyAppliedHumanoid = nil
local lastCarAssemblyRoot = nil

local toggleRefreshers = {}
local refreshPlayerList = nil
local targetStatusLabel = nil

--=====================================================================
-- Création des couches visuelles
--=====================================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ZaysHub_HUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 200
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = PlayerGui

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Active = false
overlay.ZIndex = 1
overlay.Parent = screenGui

local visualFolder = Instance.new("Folder")
visualFolder.Name = "ZaysHub_Visuals_" .. LocalPlayer.UserId
visualFolder.Parent = Workspace

local fovCircle = Instance.new("Frame")
fovCircle.Name = "AimFOV"
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Position = UDim2.fromScale(0.5, 0.5)
fovCircle.Size = UDim2.fromOffset(state.aimFov * 2, state.aimFov * 2)
fovCircle.BackgroundTransparency = 1
fovCircle.BorderSizePixel = 0
fovCircle.Visible = false
fovCircle.ZIndex = 20
fovCircle.Parent = overlay

local fovCorner = Instance.new("UICorner")
fovCorner.CornerRadius = UDim.new(1, 0)
fovCorner.Parent = fovCircle

local fovStroke = Instance.new("UIStroke")
fovStroke.Color = THEME.Accent
fovStroke.Thickness = 2
fovStroke.Transparency = 0.08
fovStroke.Parent = fovCircle

--=====================================================================
-- Utilitaires généraux
--=====================================================================

local function tween(instance, duration, properties)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local animation = TweenService:Create(instance, info, properties)
	animation:Play()
	return animation
end

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or THEME.Stroke
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function refreshToggle(key)
	local refresher = toggleRefreshers[key]
	if refresher then
		refresher()
	end
end

local function getCamera()
	return Workspace.CurrentCamera
end

local function getMovementDirection()
	local camera = getCamera()
	if not camera then
		return Vector3.zero
	end

	local forwardAmount = (heldKeys[KEYBINDS.Forward] and 1 or 0) - (heldKeys[KEYBINDS.Backward] and 1 or 0)
	local rightAmount = (heldKeys[KEYBINDS.Right] and 1 or 0) - (heldKeys[KEYBINDS.Left] and 1 or 0)
	local upAmount = (heldKeys[KEYBINDS.Up] and 1 or 0)
		- ((heldKeys[KEYBINDS.Down] or heldKeys[KEYBINDS.DownAlt]) and 1 or 0)

	local direction = camera.CFrame.LookVector * forwardAmount
		+ camera.CFrame.RightVector * rightAmount
		+ Vector3.yAxis * upAmount

	if direction.Magnitude > 1 then
		direction = direction.Unit
	end

	return direction
end

--=====================================================================
-- Personnage : respawn, NoClip et invisibilité locale
--=====================================================================

local function rememberCollision(part)
	if originalCollisions[part] == nil then
		originalCollisions[part] = part.CanCollide
	end
end

local function applyNoClipTo(instance)
	if instance:IsA("BasePart") then
		rememberCollision(instance)
		instance.CanCollide = false
	end
end

local function applyNoClipNow()
	if not currentCharacter then
		return
	end

	for _, descendant in ipairs(currentCharacter:GetDescendants()) do
		applyNoClipTo(descendant)
	end
end

local function restoreCollisions()
	for part, canCollide in pairs(originalCollisions) do
		if part and part.Parent then
			part.CanCollide = canCollide
		end
	end
	table.clear(originalCollisions)
end

local function rememberInvisibleProperty(instance, propertyName, value)
	if invisibleOriginals[instance] == nil then
		invisibleOriginals[instance] = {
			property = propertyName,
			value = value,
		}
	end
end

local function applyInvisibleTo(instance)
	if instance:IsA("BasePart") then
		rememberInvisibleProperty(instance, "LocalTransparencyModifier", instance.LocalTransparencyModifier)
		instance.LocalTransparencyModifier = 1
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		rememberInvisibleProperty(instance, "Transparency", instance.Transparency)
		instance.Transparency = 1
	elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail") then
		rememberInvisibleProperty(instance, "Enabled", instance.Enabled)
		instance.Enabled = false
	elseif instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") then
		rememberInvisibleProperty(instance, "Enabled", instance.Enabled)
		instance.Enabled = false
	elseif instance:IsA("Humanoid") then
		rememberInvisibleProperty(instance, "DisplayDistanceType", instance.DisplayDistanceType)
		instance.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function applyInvisibleNow()
	if not currentCharacter then
		return
	end

	for _, descendant in ipairs(currentCharacter:GetDescendants()) do
		applyInvisibleTo(descendant)
	end
end

local function restoreVisibility()
	for instance, saved in pairs(invisibleOriginals) do
		if instance and instance.Parent then
			local ok = pcall(function()
				instance[saved.property] = saved.value
			end)
			if not ok then
				warn("[Zays Hub] Impossible de restaurer :", instance:GetFullName())
			end
		end
	end
	table.clear(invisibleOriginals)
end

local function setNoclip(enabled)
	state.noclip = enabled
	if enabled then
		applyNoClipNow()
	else
		restoreCollisions()
	end
	refreshToggle("noclip")
end

local function setInvisible(enabled)
	state.invisible = enabled
	if enabled then
		applyInvisibleNow()
	else
		restoreVisibility()
	end
	refreshToggle("invisible")
end

local function applyFlyHumanoid(humanoid)
	if flyAppliedHumanoid == humanoid then
		return
	end

	if flyAppliedHumanoid then
		local saved = flyHumanoidOriginals[flyAppliedHumanoid]
		if saved and flyAppliedHumanoid.Parent then
			flyAppliedHumanoid.PlatformStand = saved.PlatformStand
			flyAppliedHumanoid.AutoRotate = saved.AutoRotate
		end
	end

	if not flyHumanoidOriginals[humanoid] then
		flyHumanoidOriginals[humanoid] = {
			PlatformStand = humanoid.PlatformStand,
			AutoRotate = humanoid.AutoRotate,
		}
	end

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	flyAppliedHumanoid = humanoid
end

local function restoreFlyHumanoid()
	local humanoid = flyAppliedHumanoid
	if humanoid then
		local saved = flyHumanoidOriginals[humanoid]
		if saved and humanoid.Parent then
			humanoid.PlatformStand = saved.PlatformStand
			humanoid.AutoRotate = saved.AutoRotate
		end
	end
	flyAppliedHumanoid = nil
end

local function setFly(enabled)
	state.fly = enabled
	if not enabled then
		restoreFlyHumanoid()
		if currentRoot and currentRoot.Parent then
			currentRoot.AssemblyLinearVelocity = Vector3.zero
			currentRoot.AssemblyAngularVelocity = Vector3.zero
		end
	end
	refreshToggle("fly")
end

local function setCarFly(enabled)
	state.carFly = enabled
	if not enabled and lastCarAssemblyRoot and lastCarAssemblyRoot.Parent then
		lastCarAssemblyRoot.AssemblyLinearVelocity = Vector3.zero
		lastCarAssemblyRoot.AssemblyAngularVelocity = Vector3.zero
		lastCarAssemblyRoot = nil
	end
	refreshToggle("carFly")
end

local function bindCharacter(character)
	characterSerial += 1
	local mySerial = characterSerial

	if characterDescendantConnection then
		characterDescendantConnection:Disconnect()
		characterDescendantConnection = nil
	end

	restoreFlyHumanoid()
	table.clear(originalCollisions)
	table.clear(invisibleOriginals)

	currentCharacter = character
	currentHumanoid = nil
	currentRoot = nil

	characterDescendantConnection = character.DescendantAdded:Connect(function(descendant)
		if state.noclip then
			applyNoClipTo(descendant)
		end
		if state.invisible then
			applyInvisibleTo(descendant)
		end
	end)

	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if mySerial ~= characterSerial or currentCharacter ~= character then
			return
		end

		currentHumanoid = humanoid
		currentRoot = root

		if state.noclip then
			applyNoClipNow()
		end
		if state.invisible then
			applyInvisibleNow()
		end
	end)
end

--=====================================================================
-- ESP local : noms, distance, santé, vrai rôle, contour et squelette R6/R15
--=====================================================================

-- Mets ici l'ID de ton groupe Roblox si tu veux afficher le rôle du groupe.
-- Laisse 0 si ton jeu stocke déjà le rôle dans un Attribute/Value/leaderstats.
local ROLE_GROUP_ID = 0

local ROLE_KEYS = { "Role", "role", "PlayerRole", "playerRole", "TeamRole", "Class", "Job" }
local groupRoleCache = setmetatable({}, { __mode = "k" })

local function roleValueToText(value)
	if value == nil then
		return nil
	end

	local valueType = typeof(value)
	if valueType == "string" then
		return value ~= "" and value or nil
	elseif valueType == "number" or valueType == "boolean" then
		return tostring(value)
	end

	return nil
end

local function findRoleInContainer(container)
	if not container then
		return nil
	end

	-- D'abord les noms de rôle connus.
	for _, key in ipairs(ROLE_KEYS) do
		local attributeRole = roleValueToText(container:GetAttribute(key))
		if attributeRole then
			return attributeRole
		end

		local valueObject = container:FindFirstChild(key)
		if valueObject and valueObject:IsA("ValueBase") then
			local objectRole = roleValueToText(valueObject.Value)
			if objectRole then
				return objectRole
			end
		end
	end

	-- Puis n'importe quel Attribute/Value dont le nom contient "role".
	for attributeName, attributeValue in pairs(container:GetAttributes()) do
		if string.find(string.lower(attributeName), "role", 1, true) then
			local attributeRole = roleValueToText(attributeValue)
			if attributeRole then
				return attributeRole
			end
		end
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("ValueBase") and string.find(string.lower(child.Name), "role", 1, true) then
			local objectRole = roleValueToText(child.Value)
			if objectRole then
				return objectRole
			end
		end
	end

	return nil
end

local function normalizeTeamName(teamName)
	if not teamName or teamName == "" then
		return nil
	end

	local lower = string.lower(teamName)

	-- Noms courants des rôles type Murder Mystery.
	if string.find(lower, "murder", 1, true)
		or string.find(lower, "killer", 1, true)
		or string.find(lower, "meurtr", 1, true) then
		return "Murder"
	elseif string.find(lower, "sheriff", 1, true)
		or string.find(lower, "detective", 1, true) then
		return "Sheriff"
	elseif string.find(lower, "civil", 1, true)
		or string.find(lower, "innocent", 1, true)
		or string.find(lower, "innoc", 1, true) then
		return "Civil"
	end

	-- Pour toute autre Team, garde simplement son vrai nom Roblox.
	return teamName
end

local function getPlayerRole(player, character)
	-- Priorité à la Team Roblox : c'est ce que l'ESP doit afficher.
	if player.Team then
		local teamName = normalizeTeamName(player.Team.Name)
		if teamName then
			return teamName
		end
	end

	-- Fallback si le jeu n'utilise pas le service Teams.
	local role = findRoleInContainer(player)
		or findRoleInContainer(character)
		or findRoleInContainer(player:FindFirstChild("leaderstats"))

	if role then
		return normalizeTeamName(role) or role
	end

	if ROLE_GROUP_ID > 0 then
		local groupRole = groupRoleCache[player]
		if groupRole == nil then
			local ok, result = pcall(function()
				return player:GetRoleInGroup(ROLE_GROUP_ID)
			end)
			if ok and result and result ~= "" and result ~= "Guest" then
				groupRole = result
			else
				groupRole = false
			end
			groupRoleCache[player] = groupRole
		end

		if groupRole then
			return groupRole
		end
	end

	return "Non détecté"
end

local espRecords = {}
local espGeneration = {}
local playerConnections = {}

local R15_SEGMENTS = {
	{ "Head", "UpperTorso" },
	{ "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" },
	{ "LeftUpperArm", "LeftLowerArm" },
	{ "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" },
	{ "RightUpperArm", "RightLowerArm" },
	{ "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" },
	{ "LeftUpperLeg", "LeftLowerLeg" },
	{ "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" },
	{ "RightUpperLeg", "RightLowerLeg" },
	{ "RightLowerLeg", "RightFoot" },
}

local R6_SEGMENTS = {
	{ "Head", "Torso" },
	{ "Torso", "Left Arm" },
	{ "Torso", "Right Arm" },
	{ "Torso", "Left Leg" },
	{ "Torso", "Right Leg" },
}

local function destroyEspRecord(player)
	local record = espRecords[player]
	if not record then
		return
	end

	if record.highlight then
		record.highlight:Destroy()
	end
	if record.billboard then
		record.billboard:Destroy()
	end
	for _, segment in ipairs(record.skeleton) do
		segment.line:Destroy()
	end

	espRecords[player] = nil
end

local function createSkeletonLine()
	local line = Instance.new("Frame")
	line.Name = "SkeletonLine"
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.BackgroundColor3 = THEME.TextOnAccent
	line.BackgroundTransparency = 0.08
	line.BorderSizePixel = 0
	line.Size = UDim2.fromOffset(10, 2)
	line.Visible = false
	line.ZIndex = 8
	line.Parent = overlay
	addCorner(line, 2)
	return line
end

local function buildEspRecord(player, character)
	if player == LocalPlayer then
		return
	end

	espGeneration[player] = (espGeneration[player] or 0) + 1
	local generation = espGeneration[player]
	destroyEspRecord(player)

	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		local head = character:FindFirstChild("Head") or root

		if not humanoid or not root then
			return
		end
		if espGeneration[player] ~= generation or player.Character ~= character then
			return
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "ZaysHub_ESP_" .. player.Name
		highlight.Adornee = character
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillColor = THEME.Accent
		highlight.FillTransparency = 0.82
		highlight.OutlineColor = THEME.TextOnAccent
		highlight.OutlineTransparency = 0.05
		highlight.Enabled = state.esp
		highlight.Parent = visualFolder

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "ZaysHub_Info_" .. player.Name
		billboard.Adornee = head
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.Size = UDim2.fromOffset(280, 86)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.25, 0)
		billboard.Enabled = false
		billboard.Parent = screenGui

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameDistance"
		nameLabel.Size = UDim2.new(1, 0, 0, 20)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamSemibold
		nameLabel.TextColor3 = THEME.TextOnAccent
		nameLabel.TextStrokeColor3 = THEME.AccentDark
		nameLabel.TextStrokeTransparency = 0.25
		nameLabel.TextSize = 14
		nameLabel.Text = ""
		nameLabel.Parent = billboard

		local roleLabel = Instance.new("TextLabel")
		roleLabel.Name = "RoleText"
		roleLabel.Position = UDim2.fromOffset(0, 21)
		roleLabel.Size = UDim2.new(1, 0, 0, 18)
		roleLabel.BackgroundTransparency = 1
		roleLabel.Font = Enum.Font.GothamBold
		roleLabel.TextColor3 = THEME.AccentSoft
		roleLabel.TextStrokeColor3 = THEME.AccentDark
		roleLabel.TextStrokeTransparency = 0.2
		roleLabel.TextSize = 13
		roleLabel.Text = ""
		roleLabel.Visible = false
		roleLabel.Parent = billboard

		local healthLabel = Instance.new("TextLabel")
		healthLabel.Name = "HealthText"
		healthLabel.Position = UDim2.fromOffset(0, 40)
		healthLabel.Size = UDim2.new(1, 0, 0, 18)
		healthLabel.BackgroundTransparency = 1
		healthLabel.Font = Enum.Font.GothamMedium
		healthLabel.TextColor3 = THEME.TextOnAccent
		healthLabel.TextStrokeColor3 = THEME.AccentDark
		healthLabel.TextStrokeTransparency = 0.3
		healthLabel.TextSize = 12
		healthLabel.Text = ""
		healthLabel.Parent = billboard

		local healthBack = Instance.new("Frame")
		healthBack.Name = "HealthBack"
		healthBack.AnchorPoint = Vector2.new(0.5, 0)
		healthBack.Position = UDim2.new(0.5, 0, 0, 62)
		healthBack.Size = UDim2.fromOffset(128, 7)
		healthBack.BackgroundColor3 = THEME.Off
		healthBack.BorderSizePixel = 0
		healthBack.Parent = billboard
		addCorner(healthBack, 4)

		local healthFill = Instance.new("Frame")
		healthFill.Name = "Fill"
		healthFill.Size = UDim2.fromScale(1, 1)
		healthFill.BackgroundColor3 = THEME.On
		healthFill.BorderSizePixel = 0
		healthFill.Parent = healthBack
		addCorner(healthFill, 4)

		local skeleton = {}
		local pairsToUse = humanoid.RigType == Enum.HumanoidRigType.R15 and R15_SEGMENTS or R6_SEGMENTS
		for _, pair in ipairs(pairsToUse) do
			local partA = character:FindFirstChild(pair[1])
			local partB = character:FindFirstChild(pair[2])
			if partA and partA:IsA("BasePart") and partB and partB:IsA("BasePart") then
				table.insert(skeleton, {
					a = partA,
					b = partB,
					line = createSkeletonLine(),
				})
			end
		end

		espRecords[player] = {
			player = player,
			character = character,
			humanoid = humanoid,
			root = root,
			highlight = highlight,
			billboard = billboard,
			nameLabel = nameLabel,
			roleLabel = roleLabel,
			healthLabel = healthLabel,
			healthBack = healthBack,
			healthFill = healthFill,
			skeleton = skeleton,
		}
	end)
end

local function refreshAllEspVisibility()
	for _, record in pairs(espRecords) do
		record.highlight.Enabled = state.esp
		record.billboard.Enabled = state.esp and (state.nameEsp or state.distanceEsp or state.healthEsp or state.roleEsp)
		record.nameLabel.Visible = state.esp and (state.nameEsp or state.distanceEsp)
		record.roleLabel.Visible = state.esp and state.roleEsp
		record.healthLabel.Visible = state.esp and state.healthEsp
		record.healthBack.Visible = state.esp and state.healthEsp
		for _, segment in ipairs(record.skeleton) do
			if not (state.esp and state.skeletonEsp) then
				segment.line.Visible = false
			end
		end
	end
end

local function setEspFlag(key, enabled)
	state[key] = enabled
	refreshToggle(key)
	refreshAllEspVisibility()
end

local function registerPlayer(player)
	if player == LocalPlayer or playerConnections[player] then
		return
	end

	local connections = {}
	connections.characterAdded = player.CharacterAdded:Connect(function(character)
		buildEspRecord(player, character)
	end)
	connections.characterRemoving = player.CharacterRemoving:Connect(function()
		espGeneration[player] = (espGeneration[player] or 0) + 1
		destroyEspRecord(player)
	end)
	playerConnections[player] = connections

	if player.Character then
		buildEspRecord(player, player.Character)
	end
end

local function unregisterPlayer(player)
	espGeneration[player] = (espGeneration[player] or 0) + 1
	destroyEspRecord(player)

	local connections = playerConnections[player]
	if connections then
		for _, connection in pairs(connections) do
			connection:Disconnect()
		end
		playerConnections[player] = nil
	end
end

--=====================================================================
-- AimBot de test local : FOV, visibilité et lissage caméra
--=====================================================================

local function isTargetVisible(targetPart, targetCharacter)
	local camera = getCamera()
	if not camera then
		return false
	end

	local origin = camera.CFrame.Position
	local direction = targetPart.Position - origin
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = currentCharacter and { currentCharacter } or {}
	raycastParams.IgnoreWater = true

	local result = Workspace:Raycast(origin, direction, raycastParams)
	return result == nil or result.Instance:IsDescendantOf(targetCharacter)
end

local function findBestAimTarget()
	local camera = getCamera()
	if not camera then
		return nil, nil
	end

	local center = camera.ViewportSize / 2
	local bestPart = nil
	local bestPlayer = nil
	local bestScreenDistance = math.huge
	local distanceOrigin = currentRoot and currentRoot.Position or camera.CFrame.Position

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local targetPart = character and character:FindFirstChild(state.aimPart)
			if not targetPart and character then
				targetPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
			end

			if humanoid and humanoid.Health > 0 and targetPart and targetPart:IsA("BasePart") then
				local worldDistance = (targetPart.Position - distanceOrigin).Magnitude
				if worldDistance <= state.aimMaxDistance then
					local screenPoint, onScreen = camera:WorldToViewportPoint(targetPart.Position)
					if onScreen and screenPoint.Z > 0 then
						local screenDistance = (Vector2.new(screenPoint.X, screenPoint.Y) - center).Magnitude
						if screenDistance <= state.aimFov
							and screenDistance < bestScreenDistance
							and isTargetVisible(targetPart, character)
						then
							bestScreenDistance = screenDistance
							bestPart = targetPart
							bestPlayer = player
						end
					end
				end
			end
		end
	end

	return bestPart, bestPlayer
end

local function setAimBot(enabled)
	state.aimBot = enabled
	fovCircle.Visible = enabled
	if not enabled then
		fovStroke.Color = THEME.Accent
		if targetStatusLabel then
			targetStatusLabel.Text = "Cible actuelle : aucune"
		end
	end
	refreshToggle("aimBot")
end

--=====================================================================
-- Interface : fenêtre, onglets et composants
--=====================================================================

local window = Instance.new("CanvasGroup")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(700, 460)
window.BackgroundColor3 = THEME.Background
window.BorderSizePixel = 0
window.GroupTransparency = 0
window.ZIndex = 100
window.Parent = screenGui
addCorner(window, 14)
addStroke(window, THEME.Accent, 1.4, 0.18)

local windowGradient = Instance.new("UIGradient")
windowGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, THEME.PanelAlt),
	ColorSequenceKeypoint.new(0.36, THEME.Background),
	ColorSequenceKeypoint.new(1, THEME.Panel),
})
windowGradient.Rotation = 22
windowGradient.Parent = window

local windowScale = Instance.new("UIScale")
windowScale.Scale = 1
windowScale.Parent = window

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 54)
topBar.BackgroundColor3 = THEME.Panel
topBar.BorderSizePixel = 0
topBar.Active = true
topBar.ZIndex = 101
topBar.Parent = window

local topBarGradient = Instance.new("UIGradient")
topBarGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, THEME.AccentDark),
	ColorSequenceKeypoint.new(0.55, THEME.Accent),
	ColorSequenceKeypoint.new(1, THEME.AccentHover),
})
topBarGradient.Rotation = 0
topBarGradient.Parent = topBar

local logoBadge = Instance.new("Frame")
logoBadge.Name = "LogoBadge"
logoBadge.Position = UDim2.fromOffset(16, 9)
logoBadge.Size = UDim2.fromOffset(36, 36)
logoBadge.BackgroundColor3 = THEME.Panel
logoBadge.BorderSizePixel = 0
logoBadge.ZIndex = 102
logoBadge.Parent = topBar
addCorner(logoBadge, 10)
addStroke(logoBadge, THEME.Text, 1, 0.55)

local logoGradient = Instance.new("UIGradient")
logoGradient.Color = ColorSequence.new(THEME.Panel, THEME.PanelAlt)
logoGradient.Rotation = 45
logoGradient.Parent = logoBadge

local logoText = Instance.new("TextLabel")
logoText.Size = UDim2.fromScale(1, 1)
logoText.BackgroundTransparency = 1
logoText.Font = Enum.Font.GothamBlack
logoText.Text = "Z"
logoText.TextColor3 = THEME.Accent
logoText.TextSize = 20
logoText.ZIndex = 103
logoText.Parent = logoBadge

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(64, 6)
title.Size = UDim2.new(1, -230, 0, 24)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.Text = "ZAYS HUB"
title.TextColor3 = THEME.TextOnAccent
title.TextSize = 17
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 102
title.Parent = topBar

local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.fromOffset(64, 30)
subtitle.Size = UDim2.new(1, -230, 0, 16)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.GothamMedium
subtitle.Text = "CENTRE DE CONTRÔLE  ·  ROUGE / BLANC"
subtitle.TextColor3 = THEME.TextOnAccent
subtitle.TextSize = 10
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.ZIndex = 102
subtitle.Parent = topBar

local accessBadge = Instance.new("TextLabel")
accessBadge.AnchorPoint = Vector2.new(1, 0.5)
accessBadge.Position = UDim2.new(1, -16, 0.5, 0)
accessBadge.Size = UDim2.fromOffset(132, 30)
accessBadge.BackgroundColor3 = THEME.Panel
accessBadge.BorderSizePixel = 0
accessBadge.Font = Enum.Font.GothamBold
accessBadge.Text = RunService:IsStudio() and "STUDIO TEST" or "ZAYS HUB"
accessBadge.TextColor3 = THEME.Accent
accessBadge.TextSize = 11
accessBadge.ZIndex = 102
accessBadge.Parent = topBar
addCorner(accessBadge, 8)
addStroke(accessBadge, THEME.Accent, 1, 0.15)

local divider = Instance.new("Frame")
divider.Position = UDim2.fromOffset(0, 52)
divider.Size = UDim2.new(1, 0, 0, 2)
divider.BackgroundColor3 = THEME.Accent
divider.BackgroundTransparency = 0
divider.BorderSizePixel = 0
divider.ZIndex = 102
divider.Parent = window

local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Position = UDim2.fromOffset(0, 54)
sidebar.Size = UDim2.new(0, 158, 1, -82)
sidebar.BackgroundColor3 = THEME.Panel
sidebar.BorderSizePixel = 0
sidebar.ZIndex = 101
sidebar.Parent = window

local sidebarGradient = Instance.new("UIGradient")
sidebarGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, THEME.Panel),
	ColorSequenceKeypoint.new(1, THEME.PanelAlt),
})
sidebarGradient.Rotation = 90
sidebarGradient.Parent = sidebar

local sidebarPadding = Instance.new("UIPadding")
sidebarPadding.PaddingTop = UDim.new(0, 14)
sidebarPadding.PaddingLeft = UDim.new(0, 12)
sidebarPadding.PaddingRight = UDim.new(0, 12)
sidebarPadding.Parent = sidebar

local sidebarLayout = Instance.new("UIListLayout")
sidebarLayout.Padding = UDim.new(0, 8)
sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
sidebarLayout.Parent = sidebar

local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.fromOffset(158, 54)
content.Size = UDim2.new(1, -158, 1, -82)
content.BackgroundColor3 = THEME.Background
content.BorderSizePixel = 0
content.ClipsDescendants = true
content.ZIndex = 101
content.Parent = window

local footer = Instance.new("Frame")
footer.Position = UDim2.new(0, 0, 1, -28)
footer.Size = UDim2.new(1, 0, 0, 28)
footer.BackgroundColor3 = THEME.Accent
footer.BorderSizePixel = 0
footer.ZIndex = 101
footer.Parent = window

local footerLine = Instance.new("Frame")
footerLine.Size = UDim2.new(1, 0, 0, 1)
footerLine.BackgroundColor3 = THEME.TextOnAccent
footerLine.BackgroundTransparency = 0.25
footerLine.BorderSizePixel = 0
footerLine.ZIndex = 102
footerLine.Parent = footer

local footerText = Instance.new("TextLabel")
footerText.Position = UDim2.fromOffset(14, 0)
footerText.Size = UDim2.new(1, -28, 1, 0)
footerText.BackgroundTransparency = 1
footerText.Font = Enum.Font.GothamMedium
footerText.Text = "Z  AVANCER    •    Q  GAUCHE    •    S  RECULER    •    D  DROITE    ·    RightShift  MENU"
footerText.TextColor3 = THEME.TextOnAccent
footerText.TextSize = 10
footerText.TextXAlignment = Enum.TextXAlignment.Left
footerText.ZIndex = 102
footerText.Parent = footer

local pages = {}
local tabButtons = {}
local tabIndicators = {}
local tabStrokes = {}
local currentTab = nil

local tabDisplayNames = {
	Movement = "MOUVEMENT",
	Visuals = "VISUELS",
	Players = "JOUEURS",
}

local function createPage(name)
	local page = Instance.new("ScrollingFrame")
	page.Name = name .. "Page"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 3
	page.ScrollBarImageColor3 = THEME.Accent
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.fromOffset(0, 0)
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.Visible = false
	page.ZIndex = 102
	page.Parent = content

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = page

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 9)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page

	pages[name] = page
	return page
end

local function selectTab(name)
	currentTab = name
	for pageName, page in pairs(pages) do
		page.Visible = pageName == name
	end
	for buttonName, button in pairs(tabButtons) do
		local active = buttonName == name
		tween(button, 0.16, {
			BackgroundColor3 = active and THEME.AccentSoft or THEME.PanelAlt,
			TextColor3 = active and THEME.Text or THEME.Muted,
		})

		local indicator = tabIndicators[buttonName]
		if indicator then
			tween(indicator, 0.16, {
				BackgroundTransparency = active and 0 or 1,
			})
		end

		local stroke = tabStrokes[buttonName]
		if stroke then
			tween(stroke, 0.16, {
				Color = active and THEME.Accent or THEME.Stroke,
				Transparency = active and 0.05 or 0.6,
			})
		end
	end
end

local function createTab(name, order)
	local button = Instance.new("TextButton")
	button.Name = name .. "Tab"
	button.Size = UDim2.new(1, 0, 0, 40)
	button.BackgroundColor3 = THEME.PanelAlt
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.ClipsDescendants = true
	button.Font = Enum.Font.GothamBold
	button.Text = "     " .. (tabDisplayNames[name] or string.upper(name))
	button.TextColor3 = THEME.Muted
	button.TextSize = 11
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.LayoutOrder = order
	button.ZIndex = 102
	button.Parent = sidebar
	addCorner(button, 9)
	local buttonStroke = addStroke(button, THEME.Stroke, 1, 0.6)

	local indicator = Instance.new("Frame")
	indicator.Name = "ActiveIndicator"
	indicator.Position = UDim2.fromOffset(0, 7)
	indicator.Size = UDim2.fromOffset(3, 26)
	indicator.BackgroundColor3 = THEME.Accent
	indicator.BackgroundTransparency = 1
	indicator.BorderSizePixel = 0
	indicator.ZIndex = 103
	indicator.Parent = button
	addCorner(indicator, 2)

	button.Activated:Connect(function()
		selectTab(name)
	end)
	button.MouseEnter:Connect(function()
		if currentTab ~= name then
			tween(button, 0.12, { BackgroundColor3 = THEME.Hover })
		end
	end)
	button.MouseLeave:Connect(function()
		if currentTab ~= name then
			tween(button, 0.12, { BackgroundColor3 = THEME.PanelAlt })
		end
	end)
	tabButtons[name] = button
	tabIndicators[name] = indicator
	tabStrokes[name] = buttonStroke
	return button
end

local function createKeyGuide()
	local guide = Instance.new("Frame")
	guide.Name = "KeyGuide"
	guide.Size = UDim2.new(1, 0, 0, 148)
	guide.BackgroundColor3 = THEME.PanelAlt
	guide.BorderSizePixel = 0
	guide.LayoutOrder = 10
	guide.ZIndex = 102
	guide.Parent = sidebar
	addCorner(guide, 10)
	addStroke(guide, THEME.Stroke, 1, 0.45)

	local guideTitle = Instance.new("TextLabel")
	guideTitle.Position = UDim2.fromOffset(10, 7)
	guideTitle.Size = UDim2.new(1, -20, 0, 18)
	guideTitle.BackgroundTransparency = 1
	guideTitle.Font = Enum.Font.GothamBold
	guideTitle.Text = "COMMANDES AZERTY"
	guideTitle.TextColor3 = THEME.Text
	guideTitle.TextSize = 10
	guideTitle.TextXAlignment = Enum.TextXAlignment.Left
	guideTitle.ZIndex = 103
	guideTitle.Parent = guide

	local controls = {
		{ "Z", "AVANCER" },
		{ "Q", "ALLER À GAUCHE" },
		{ "S", "RECULER" },
		{ "D", "ALLER À DROITE" },
	}

	for index, control in ipairs(controls) do
		local keyRow = Instance.new("Frame")
		keyRow.Position = UDim2.fromOffset(8, 27 + (index - 1) * 29)
		keyRow.Size = UDim2.new(1, -16, 0, 25)
		keyRow.BackgroundColor3 = THEME.Background
		keyRow.BorderSizePixel = 0
		keyRow.ZIndex = 103
		keyRow.Parent = guide
		addCorner(keyRow, 6)

		local keyCap = Instance.new("TextLabel")
		keyCap.Position = UDim2.fromOffset(3, 3)
		keyCap.Size = UDim2.fromOffset(24, 19)
		keyCap.BackgroundColor3 = THEME.Accent
		keyCap.BorderSizePixel = 0
		keyCap.Font = Enum.Font.GothamBlack
		keyCap.Text = control[1]
		keyCap.TextColor3 = THEME.TextOnAccent
		keyCap.TextSize = 11
		keyCap.ZIndex = 104
		keyCap.Parent = keyRow
		addCorner(keyCap, 5)

		local action = Instance.new("TextLabel")
		action.Position = UDim2.fromOffset(34, 0)
		action.Size = UDim2.new(1, -39, 1, 0)
		action.BackgroundTransparency = 1
		action.Font = Enum.Font.GothamSemibold
		action.Text = control[2]
		action.TextColor3 = THEME.Muted
		action.TextSize = 8
		action.TextXAlignment = Enum.TextXAlignment.Left
		action.ZIndex = 104
		action.Parent = keyRow
	end

	return guide
end

local function createSectionHeader(parent, titleText, descriptionText)
	local holder = Instance.new("Frame")
	holder.Name = titleText .. "Header"
	holder.Size = UDim2.new(1, 0, 0, descriptionText and 43 or 27)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ZIndex = 103
	holder.Parent = parent

	local accent = Instance.new("Frame")
	accent.Position = UDim2.fromOffset(0, 2)
	accent.Size = UDim2.fromOffset(3, 18)
	accent.BackgroundColor3 = THEME.Accent
	accent.BorderSizePixel = 0
	accent.ZIndex = 104
	accent.Parent = holder
	addCorner(accent, 2)

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(11, 0)
	label.Size = UDim2.new(1, -11, 0, 22)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = string.upper(titleText)
	label.TextColor3 = THEME.Text
	label.TextSize = 11
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 104
	label.Parent = holder

	if descriptionText then
		local description = Instance.new("TextLabel")
		description.Position = UDim2.fromOffset(11, 23)
		description.Size = UDim2.new(1, -11, 0, 16)
		description.BackgroundTransparency = 1
		description.Font = Enum.Font.Gotham
		description.Text = descriptionText
		description.TextColor3 = THEME.Muted
		description.TextSize = 10
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.ZIndex = 104
		description.Parent = holder
	end

	return holder
end

local function createRow(parent, height)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, height or 48)
	row.BackgroundColor3 = THEME.Panel
	row.BorderSizePixel = 0
	row.ZIndex = 103
	row.Parent = parent
	addCorner(row, 10)
	addStroke(row, THEME.Stroke, 1, 0.45)

	local rowGradient = Instance.new("UIGradient")
	rowGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, THEME.Panel),
		ColorSequenceKeypoint.new(1, THEME.PanelAlt),
	})
	rowGradient.Rotation = 0
	rowGradient.Parent = row
	return row
end

local function createToggle(parent, labelText, descriptionText, key, onChanged)
	local row = createRow(parent, descriptionText and 54 or 46)

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(14, descriptionText and 7 or 0)
	label.Size = UDim2.new(1, -116, 0, descriptionText and 20 or 46)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamSemibold
	label.Text = labelText
	label.TextColor3 = THEME.Text
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 104
	label.Parent = row

	if descriptionText then
		local description = Instance.new("TextLabel")
		description.Position = UDim2.fromOffset(14, 28)
		description.Size = UDim2.new(1, -116, 0, 16)
		description.BackgroundTransparency = 1
		description.Font = Enum.Font.Gotham
		description.Text = descriptionText
		description.TextColor3 = THEME.Muted
		description.TextSize = 10
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.ZIndex = 104
		description.Parent = row
	end

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	button.Size = UDim2.fromOffset(82, 30)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.ZIndex = 104
	button.Parent = row
	addCorner(button, 9)
	local buttonStroke = addStroke(button, THEME.Stroke, 1, 0.4)

	local function update()
		local enabled = state[key]
		button.Text = enabled and "ACTIF" or "INACTIF"
		button.TextColor3 = enabled and THEME.TextOnAccent or THEME.Text
		tween(button, 0.16, {
			BackgroundColor3 = enabled and THEME.On or THEME.Off,
		})
		tween(buttonStroke, 0.16, {
			Color = enabled and THEME.TextOnAccent or THEME.Stroke,
			Transparency = enabled and 0.1 or 0.4,
		})
	end

	toggleRefreshers[key] = update
	button.Activated:Connect(function()
		onChanged(not state[key])
	end)
	button.MouseEnter:Connect(function()
		tween(button, 0.12, {
			BackgroundColor3 = state[key] and THEME.AccentHover or THEME.Hover,
		})
	end)
	button.MouseLeave:Connect(update)
	update()
	return row
end

local function roundToStep(value, step)
	return math.floor(value / step + 0.5) * step
end

local function createSlider(parent, labelText, key, minimum, maximum, step, suffix, onChanged)
	local row = createRow(parent, 64)

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(14, 7)
	label.Size = UDim2.new(1, -120, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamSemibold
	label.Text = labelText
	label.TextColor3 = THEME.Text
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 104
	label.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.new(1, -14, 0, 7)
	valueLabel.Size = UDim2.fromOffset(102, 20)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextColor3 = THEME.Accent
	valueLabel.TextSize = 11
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.ZIndex = 104
	valueLabel.Parent = row

	local track = Instance.new("TextButton")
	track.Position = UDim2.fromOffset(14, 39)
	track.Size = UDim2.new(1, -28, 0, 7)
	track.BackgroundColor3 = THEME.Off
	track.BorderSizePixel = 0
	track.AutoButtonColor = false
	track.Text = ""
	track.ZIndex = 104
	track.Parent = row
	addCorner(track, 4)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = THEME.Accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 105
	fill.Parent = track
	addCorner(fill, 4)

	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new(THEME.AccentHover, THEME.Accent)
	fillGradient.Rotation = 0
	fillGradient.Parent = fill

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.Size = UDim2.fromOffset(15, 15)
	knob.BackgroundColor3 = THEME.TextOnAccent
	knob.BorderSizePixel = 0
	knob.ZIndex = 106
	knob.Parent = track
	addCorner(knob, 8)
	addStroke(knob, THEME.Accent, 2, 0)

	local dragging = false

	local function setFromRatio(ratio)
		ratio = math.clamp(ratio, 0, 1)
		local value = roundToStep(minimum + (maximum - minimum) * ratio, step)
		value = math.clamp(value, minimum, maximum)
		state[key] = value
		local normalized = (value - minimum) / (maximum - minimum)
		fill.Size = UDim2.fromScale(normalized, 1)
		knob.Position = UDim2.fromScale(normalized, 0.5)
		valueLabel.Text = tostring(value) .. (suffix or "")
		if onChanged then
			onChanged(value)
		end
	end

	local function setFromScreenX(screenX)
		if track.AbsoluteSize.X <= 0 then
			return
		end
		setFromRatio((screenX - track.AbsolutePosition.X) / track.AbsoluteSize.X)
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			setFromScreenX(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch)
		then
			setFromScreenX(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)

	setFromRatio((state[key] - minimum) / (maximum - minimum))
	return row
end

local function createChoice(parent, labelText, getText, onActivated)
	local row = createRow(parent, 48)

	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(14, 0)
	label.Size = UDim2.new(1, -210, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamSemibold
	label.Text = labelText
	label.TextColor3 = THEME.Text
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 104
	label.Parent = row

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	button.Size = UDim2.fromOffset(178, 30)
	button.BackgroundColor3 = THEME.AccentSoft
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = THEME.Text
	button.TextSize = 10
	button.ZIndex = 104
	button.Parent = row
	addCorner(button, 8)
	addStroke(button, THEME.Accent, 1, 0.25)

	button.MouseEnter:Connect(function()
		tween(button, 0.12, {
			BackgroundColor3 = THEME.Accent,
			TextColor3 = THEME.TextOnAccent,
		})
	end)
	button.MouseLeave:Connect(function()
		tween(button, 0.12, {
			BackgroundColor3 = THEME.AccentSoft,
			TextColor3 = THEME.Text,
		})
	end)

	local function refresh()
		button.Text = getText()
	end
	button.Activated:Connect(function()
		onActivated()
		refresh()
	end)
	refresh()
	return row, refresh
end

local movementPage = createPage("Movement")
local visualsPage = createPage("Visuals")
local playersPage = createPage("Players")

createTab("Movement", 1)
createTab("Visuals", 2)
createTab("Players", 3)
createKeyGuide()

-- Movement
createSectionHeader(movementPage, "Vol libre", "Déplacement relatif à la caméra · commandes AZERTY")
createToggle(movementPage, "Fly", "Z avancer · Q gauche · S reculer · D droite · Espace/Ctrl vertical", "fly", setFly)
createSlider(movementPage, "Fly Speed", "flySpeed", 10, 250, 5, " studs/s")
createToggle(movementPage, "NoClip", "Restaure les collisions d'origine une fois désactivé", "noclip", setNoclip)
createSectionHeader(movementPage, "Véhicule", "S'active uniquement sur un VehicleSeat")
createToggle(movementPage, "CarFly", "Le véhicule suit la direction de la caméra", "carFly", setCarFly)
createSlider(movementPage, "CarFly Speed", "carFlySpeed", 20, 300, 5, " studs/s")

-- Visuals
createSectionHeader(visualsPage, "ESP", "Affichage local des autres joueurs de la session")
createToggle(visualsPage, "ESP", "Contour principal et interrupteur maître", "esp", function(enabled)
	setEspFlag("esp", enabled)
end)
createToggle(visualsPage, "Names", "DisplayName et @Username", "nameEsp", function(enabled)
	setEspFlag("nameEsp", enabled)
end)
createToggle(visualsPage, "Skeleton", "Segments 2D compatibles R6 et R15", "skeletonEsp", function(enabled)
	setEspFlag("skeletonEsp", enabled)
end)
createToggle(visualsPage, "Health", "Vie actuelle, maximum et barre colorée", "healthEsp", function(enabled)
	setEspFlag("healthEsp", enabled)
end)
createToggle(visualsPage, "Distance", "Distance en studs depuis ton personnage", "distanceEsp", function(enabled)
	setEspFlag("distanceEsp", enabled)
end)
createToggle(visualsPage, "Teams", "Affiche la Team Roblox du joueur (Murder / Sheriff / Civil), avec fallback sur Role/Class/Job", "roleEsp", function(enabled)
	setEspFlag("roleEsp", enabled)
end)

-- Players
createSectionHeader(playersPage, "Personnage local", "Les changements visuels restent uniquement sur ton client")
createToggle(playersPage, "Invisible", "Corps, accessoires, textures et effets locaux", "invisible", setInvisible)
createSectionHeader(playersPage, "AimBot QA", "Cible visible la plus proche du centre du FOV")
createToggle(playersPage, "AimBot", "Oriente la caméra tant que l'option reste active", "aimBot", setAimBot)
createChoice(playersPage, "Aim Part", function()
	return state.aimPart
end, function()
	state.aimPart = state.aimPart == "Head" and "HumanoidRootPart" or "Head"
end)
createSlider(playersPage, "Aim FOV (rayon)", "aimFov", 40, 500, 10, " px", function(value)
	fovCircle.Size = UDim2.fromOffset(value * 2, value * 2)
end)
createSlider(playersPage, "Smoothness", "aimSmoothness", 1, 30, 1, "", nil)
createSlider(playersPage, "Distance maximale", "aimMaxDistance", 50, 2500, 50, " studs", nil)

targetStatusLabel = Instance.new("TextLabel")
targetStatusLabel.Size = UDim2.new(1, 0, 0, 34)
targetStatusLabel.BackgroundColor3 = THEME.PanelAlt
targetStatusLabel.BorderSizePixel = 0
targetStatusLabel.Font = Enum.Font.GothamMedium
targetStatusLabel.Text = "Cible actuelle : aucune"
targetStatusLabel.TextColor3 = THEME.Muted
targetStatusLabel.TextSize = 11
targetStatusLabel.ZIndex = 103
targetStatusLabel.Parent = playersPage
addCorner(targetStatusLabel, 9)
addStroke(targetStatusLabel, THEME.Stroke, 1, 0.45)

createSectionHeader(playersPage, "Player List", "Mise à jour automatique lors des arrivées et départs")

local playerListFrame = Instance.new("ScrollingFrame")
playerListFrame.Name = "PlayerList"
playerListFrame.Size = UDim2.new(1, 0, 0, 124)
playerListFrame.BackgroundColor3 = THEME.Panel
playerListFrame.BorderSizePixel = 0
playerListFrame.ScrollBarThickness = 3
playerListFrame.ScrollBarImageColor3 = THEME.Accent
playerListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
playerListFrame.CanvasSize = UDim2.fromOffset(0, 0)
playerListFrame.ZIndex = 103
playerListFrame.Parent = playersPage
addCorner(playerListFrame, 10)
addStroke(playerListFrame, THEME.Stroke, 1, 0.55)

local playerListPadding = Instance.new("UIPadding")
playerListPadding.PaddingTop = UDim.new(0, 7)
playerListPadding.PaddingBottom = UDim.new(0, 7)
playerListPadding.PaddingLeft = UDim.new(0, 10)
playerListPadding.PaddingRight = UDim.new(0, 10)
playerListPadding.Parent = playerListFrame

local playerListLayout = Instance.new("UIListLayout")
playerListLayout.Padding = UDim.new(0, 5)
playerListLayout.SortOrder = Enum.SortOrder.Name
playerListLayout.Parent = playerListFrame

refreshPlayerList = function()
	for _, child in ipairs(playerListFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local others = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			table.insert(others, player)
		end
	end
	table.sort(others, function(a, b)
		return string.lower(a.Name) < string.lower(b.Name)
	end)

	if #others == 0 then
		local empty = Instance.new("TextLabel")
		empty.Name = "_Empty"
		empty.Size = UDim2.new(1, 0, 0, 28)
		empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.Gotham
		empty.Text = "Aucun autre joueur · lance un test multi-client"
		empty.TextColor3 = THEME.Muted
		empty.TextSize = 11
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.ZIndex = 104
		empty.Parent = playerListFrame
		return
	end

	for _, player in ipairs(others) do
		local entry = Instance.new("TextLabel")
		entry.Name = player.Name
		entry.Size = UDim2.new(1, 0, 0, 30)
		entry.BackgroundColor3 = THEME.PanelAlt
		entry.BorderSizePixel = 0
		entry.Font = Enum.Font.GothamMedium
		local teamName = getPlayerRole(player, player.Character)
		entry.Text = "  " .. player.DisplayName .. "  (@" .. player.Name .. ")  |  " .. teamName
		entry.TextColor3 = THEME.Text
		entry.TextSize = 11
		entry.TextXAlignment = Enum.TextXAlignment.Left
		entry.ZIndex = 104
		entry.Parent = playerListFrame
		addCorner(entry, 7)
		addStroke(entry, THEME.Stroke, 1, 0.65)
	end
end

selectTab("Movement")

--=====================================================================
-- Déplacement de la fenêtre et animation RightShift
--=====================================================================

local draggingWindow = false
local dragStart = nil
local windowStart = nil
local dragInput = nil

topBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		draggingWindow = true
		dragStart = input.Position
		windowStart = window.Position
		dragInput = input
	end
end)

topBar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
	then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if draggingWindow and input == dragInput and dragStart and windowStart then
		local delta = input.Position - dragStart
		window.Position = UDim2.new(
			windowStart.X.Scale,
			windowStart.X.Offset + delta.X,
			windowStart.Y.Scale,
			windowStart.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		draggingWindow = false
		dragInput = nil
	end
end)

local menuAnimationSerial = 0
local activeMenuTweens = {}

local function setMenuOpen(open)
	state.menuOpen = open
	menuAnimationSerial += 1
	local mySerial = menuAnimationSerial
	local camera = getCamera()
	local targetScale = 1
	if camera then
		local viewport = camera.ViewportSize
		targetScale = math.clamp(math.min(viewport.X / 760, viewport.Y / 510), 0.68, 1)
	end

	for _, animation in ipairs(activeMenuTweens) do
		animation:Cancel()
	end
	table.clear(activeMenuTweens)

	if open then
		window.Visible = true
		window.GroupTransparency = 1
		windowScale.Scale = targetScale * 0.94
	end

	local scaleTween = tween(windowScale, 0.22, {
		Scale = open and targetScale or targetScale * 0.94,
	})
	local fadeTween = tween(window, 0.18, { GroupTransparency = open and 0 or 1 })
	table.insert(activeMenuTweens, scaleTween)
	table.insert(activeMenuTweens, fadeTween)

	if not open then
		fadeTween.Completed:Connect(function()
			if menuAnimationSerial == mySerial and not state.menuOpen then
				window.Visible = false
			end
		end)
	end
end

local function updateResponsiveScale()
	local camera = getCamera()
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local responsiveScale = math.clamp(math.min(viewport.X / 760, viewport.Y / 510), 0.68, 1)
	if state.menuOpen then
		windowScale.Scale = responsiveScale
	end
end

--=====================================================================
-- Boucles temps réel : entrées, Fly, CarFly, AimBot et ESP
--=====================================================================

local movementKeyCodes = {
	[KEYBINDS.Forward] = true,
	[KEYBINDS.Left] = true,
	[KEYBINDS.Backward] = true,
	[KEYBINDS.Right] = true,
	[KEYBINDS.Up] = true,
	[KEYBINDS.Down] = true,
	[KEYBINDS.DownAlt] = true,
}

UserInputService.InputBegan:Connect(function(input, _gameProcessed)
	if input.KeyCode == Enum.KeyCode.RightShift and not UserInputService:GetFocusedTextBox() then
		setMenuOpen(not state.menuOpen)
		return
	end

	-- Roblox peut déjà marquer Z/Q/S/D comme traitées par ses contrôles natifs.
	-- On les lit quand même pour garantir les déplacements du Fly en AZERTY.
	if movementKeyCodes[input.KeyCode] and not UserInputService:GetFocusedTextBox() then
		heldKeys[input.KeyCode] = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if movementKeyCodes[input.KeyCode] then
		heldKeys[input.KeyCode] = nil
	end
end)

RunService.Stepped:Connect(function()
	if state.noclip and currentCharacter then
		for _, descendant in ipairs(currentCharacter:GetDescendants()) do
			if descendant:IsA("BasePart") then
				rememberCollision(descendant)
				descendant.CanCollide = false
			end
		end
	end
end)

RunService.Heartbeat:Connect(function()
	local camera = getCamera()
	if not camera then
		return
	end

	local humanoid = currentHumanoid
	local root = currentRoot
	local seatPart = humanoid and humanoid.SeatPart or nil
	local vehicleSeat = seatPart and seatPart:IsA("VehicleSeat") and seatPart or nil

	if state.carFly and vehicleSeat then
		restoreFlyHumanoid()
		local assemblyRoot = vehicleSeat.AssemblyRootPart or vehicleSeat
		lastCarAssemblyRoot = assemblyRoot

		local direction = getMovementDirection()
		assemblyRoot.AssemblyLinearVelocity = direction * state.carFlySpeed
		assemblyRoot.AssemblyAngularVelocity = Vector3.zero

		local look = camera.CFrame.LookVector
		local up = camera.CFrame.UpVector
		if look.Magnitude > 0.01 then
			assemblyRoot.CFrame = CFrame.lookAt(assemblyRoot.Position, assemblyRoot.Position + look, up)
		end
	elseif state.fly and humanoid and root and humanoid.Health > 0 then
		if lastCarAssemblyRoot and lastCarAssemblyRoot.Parent then
			lastCarAssemblyRoot.AssemblyLinearVelocity = Vector3.zero
			lastCarAssemblyRoot.AssemblyAngularVelocity = Vector3.zero
		end
		lastCarAssemblyRoot = nil

		applyFlyHumanoid(humanoid)
		root.AssemblyLinearVelocity = getMovementDirection() * state.flySpeed
		root.AssemblyAngularVelocity = Vector3.zero

		local look = camera.CFrame.LookVector
		if look.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + look, camera.CFrame.UpVector)
		end
	else
		restoreFlyHumanoid()
		if lastCarAssemblyRoot and lastCarAssemblyRoot.Parent then
			lastCarAssemblyRoot.AssemblyLinearVelocity = Vector3.zero
			lastCarAssemblyRoot.AssemblyAngularVelocity = Vector3.zero
			lastCarAssemblyRoot = nil
		end
	end
end)

local targetLabelUpdateAccumulator = 0

RunService.RenderStepped:Connect(function(deltaTime)
	local camera = getCamera()
	if not camera then
		return
	end

	-- AimBot QA
	local targetPart = nil
	local targetPlayer = nil
	if state.aimBot then
		targetPart, targetPlayer = findBestAimTarget()
		if targetPart then
			local desired = CFrame.lookAt(camera.CFrame.Position, targetPart.Position)
			local alpha = math.clamp(deltaTime * (60 / state.aimSmoothness), 0, 1)
			camera.CFrame = camera.CFrame:Lerp(desired, alpha)
			fovStroke.Color = THEME.AccentHover
		else
			fovStroke.Color = THEME.Accent
		end
	end

	targetLabelUpdateAccumulator += deltaTime
	if targetLabelUpdateAccumulator >= 0.12 then
		targetLabelUpdateAccumulator = 0
		if targetStatusLabel then
			if state.aimBot and targetPlayer then
				targetStatusLabel.Text = "Cible actuelle : " .. targetPlayer.DisplayName .. "  (@" .. targetPlayer.Name .. ")"
				targetStatusLabel.TextColor3 = THEME.On
			else
				targetStatusLabel.Text = "Cible actuelle : aucune"
				targetStatusLabel.TextColor3 = THEME.Muted
			end
		end
	end

	-- ESP et Skeleton
	for player, record in pairs(espRecords) do
		local character = record.character
		local humanoid = record.humanoid
		local root = record.root
		local valid = player.Parent == Players
			and character.Parent ~= nil
			and humanoid.Parent ~= nil
			and root.Parent ~= nil

		if not valid then
			destroyEspRecord(player)
		else
			record.highlight.Enabled = state.esp
			record.billboard.Enabled = state.esp and (state.nameEsp or state.distanceEsp or state.healthEsp or state.roleEsp)

			local distance = 0
			if currentRoot and currentRoot.Parent then
				distance = (root.Position - currentRoot.Position).Magnitude
			end

			if state.esp and (state.nameEsp or state.distanceEsp) then
				local chunks = {}
				if state.nameEsp then
					table.insert(chunks, player.DisplayName .. " (@" .. player.Name .. ")")
				end
				if state.distanceEsp then
					table.insert(chunks, tostring(math.floor(distance + 0.5)) .. " studs")
				end
				record.nameLabel.Text = table.concat(chunks, "  |  ")
				record.nameLabel.Visible = true
			else
				record.nameLabel.Visible = false
			end

			if state.esp and state.roleEsp then
				local role = getPlayerRole(player, character)
				record.roleLabel.Text = "Team : " .. role
				record.roleLabel.Visible = true
			else
				record.roleLabel.Visible = false
			end

			if state.esp and state.healthEsp then
				local maxHealth = math.max(humanoid.MaxHealth, 1)
				local health = math.clamp(humanoid.Health, 0, maxHealth)
				local ratio = health / maxHealth
				record.healthLabel.Text = string.format("%d / %d HP", math.floor(health + 0.5), math.floor(maxHealth + 0.5))
				record.healthLabel.Visible = true
				record.healthBack.Visible = true
				record.healthFill.Size = UDim2.fromScale(ratio, 1)
				record.healthFill.BackgroundColor3 = THEME.Danger:Lerp(THEME.TextOnAccent, ratio)
			else
				record.healthLabel.Visible = false
				record.healthBack.Visible = false
			end

			for _, segment in ipairs(record.skeleton) do
				if state.esp and state.skeletonEsp and segment.a.Parent and segment.b.Parent then
					local pointA, visibleA = camera:WorldToViewportPoint(segment.a.Position)
					local pointB, visibleB = camera:WorldToViewportPoint(segment.b.Position)
					if visibleA and visibleB and pointA.Z > 0 and pointB.Z > 0 then
						local a = Vector2.new(pointA.X, pointA.Y)
						local b = Vector2.new(pointB.X, pointB.Y)
						local delta = b - a
						segment.line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
						segment.line.Size = UDim2.fromOffset(math.max(delta.Magnitude, 1), 2)
						segment.line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
						segment.line.Visible = true
					else
						segment.line.Visible = false
					end
				else
					segment.line.Visible = false
				end
			end
		end
	end
end)

--=====================================================================
-- Initialisation et nettoyage
--=====================================================================

LocalPlayer.CharacterAdded:Connect(bindCharacter)
if LocalPlayer.Character then
	bindCharacter(LocalPlayer.Character)
end

Players.PlayerAdded:Connect(function(player)
	registerPlayer(player)
	if refreshPlayerList then
		refreshPlayerList()
	end
end)

Players.PlayerRemoving:Connect(function(player)
	unregisterPlayer(player)
	if refreshPlayerList then
		refreshPlayerList()
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	registerPlayer(player)
end
refreshPlayerList()

local viewportConnection = nil
local function bindCameraViewport()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = getCamera()
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
		updateResponsiveScale()
	end
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)
bindCameraViewport()

script.Destroying:Connect(function()
	setFly(false)
	setCarFly(false)
	setNoclip(false)
	setInvisible(false)
	for player in pairs(espRecords) do
		destroyEspRecord(player)
	end
	if visualFolder then
		visualFolder:Destroy()
	end
end)

print("[Zays Hub] Chargé. Z/Q/S/D pour le Fly · RightShift pour ouvrir ou fermer le menu.")
