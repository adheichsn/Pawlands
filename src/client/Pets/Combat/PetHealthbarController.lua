local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Pawlands = ReplicatedStorage:WaitForChild("Pawlands")
local Shared = Pawlands:WaitForChild("Shared")
local Catalog = require(Shared.Config.PetCatalog)
local FollowConfig = require(Shared.Config.PetFollow)
local HealthbarConfig = require(Shared.Config.PetHealthbar)
local VitalsConfig = require(Shared.Config.PetVitals)
local PetVitalsObserver = require(script.Parent.PetVitalsObserver)

local PetHealthbarController = {}
local stopCurrent = nil
local templateCache = nil
local bindings = {}
local playerConnections = {}
local folderConnections = {}
local activeFolder = nil

local function roundHealth(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function healthSize(fullSize, ratio)
	return UDim2.new(
		fullSize.X.Scale * ratio,
		math.round(fullSize.X.Offset * ratio),
		fullSize.Y.Scale,
		fullSize.Y.Offset
	)
end

local function resolveTemplate()
	if templateCache and templateCache.Parent then
		return templateCache
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local misc = assets and assets:FindFirstChild(HealthbarConfig.TemplateFolderName)
	local template = misc and misc:FindFirstChild(HealthbarConfig.TemplateName)
	if template and template:IsA("BillboardGui") then
		templateCache = template
		return template
	end
	return nil
end

local function resolveRoot(model)
	local preferred = model:FindFirstChild(HealthbarConfig.RootPartName, true)
	if preferred and preferred:IsA("BasePart") then
		return preferred
	end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveWidgets(gui)
	local progress = gui:FindFirstChild(HealthbarConfig.ProgressName)
	local fill = progress and progress:FindFirstChild(HealthbarConfig.FillName)
	local shadow = progress and progress:FindFirstChild(HealthbarConfig.ShadowName)
	local icon = progress and progress:FindFirstChild(HealthbarConfig.IconName)
	local text = progress and progress:FindFirstChild(HealthbarConfig.TextName)
	if not progress or not progress:IsA("Frame") then
		return nil, "missing Progress Frame"
	end
	if not fill or not fill:IsA("Frame") then
		return nil, "missing Progress > Health Frame"
	end
	if shadow and not shadow:IsA("Frame") then
		shadow = nil
	end
	if icon and not icon:IsA("ImageLabel") and not icon:IsA("ImageButton") then
		icon = nil
	end
	if not text or not text:IsA("TextLabel") then
		return nil, "missing Progress > ProgressText TextLabel"
	end
	return {
		Progress = progress,
		Fill = fill,
		Shadow = shadow,
		Icon = icon,
		Text = text,
	}, nil
end

local function cancelTween(tween)
	if tween then
		tween:Cancel()
	end
end

local function releaseModel(model)
	local binding = bindings[model]
	if not binding then
		return
	end
	bindings[model] = nil
	binding.Released = true
	cancelTween(binding.FillTween)
	cancelTween(binding.ShadowTween)
	for _, connection in ipairs(binding.Connections) do
		connection:Disconnect()
	end
	if binding.Gui and binding.Gui.Parent then
		binding.Gui:Destroy()
	end
end

local function shouldShow(vitals)
	if type(vitals) ~= "table" then
		return false
	end
	local maximum = math.max(1, tonumber(vitals.MaxHealth) or 1)
	local current = math.clamp(tonumber(vitals.Health) or maximum, 0, maximum)
	return vitals.KO == true
		or current < maximum
		or HealthbarConfig.VisibleStates[tostring(vitals.CombatState or "")] == true
end

local function applyBinding(binding, vitals, animate)
	if binding.Released or not binding.Model.Parent or not binding.Gui.Parent then
		return
	end
	local maximum = math.max(1, tonumber(vitals and vitals.MaxHealth) or 1)
	local current = math.clamp(tonumber(vitals and vitals.Health) or maximum, 0, maximum)
	local ratio = current / maximum
	local previous = binding.LastHealth
	binding.LastHealth = current

	binding.Gui.Enabled = shouldShow(vitals)
	binding.Widgets.Text.Text = string.format("%d / %d", roundHealth(current), roundHealth(maximum))

	local targetSize = healthSize(binding.FullFillSize, ratio)
	cancelTween(binding.FillTween)
	binding.FillTween = nil
	if animate and HealthbarConfig.FillTweenSeconds > 0 then
		binding.FillTween = TweenService:Create(
			binding.Widgets.Fill,
			TweenInfo.new(HealthbarConfig.FillTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = targetSize }
		)
		binding.FillTween:Play()
	else
		binding.Widgets.Fill.Size = targetSize
	end

	if binding.Widgets.Shadow then
		cancelTween(binding.ShadowTween)
		binding.ShadowTween = nil
		if animate and previous ~= nil and current < previous then
			binding.ShadowTween = TweenService:Create(
				binding.Widgets.Shadow,
				TweenInfo.new(HealthbarConfig.ShadowTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = healthSize(binding.FullShadowSize, ratio) }
			)
			binding.ShadowTween:Play()
		else
			binding.Widgets.Shadow.Size = healthSize(binding.FullShadowSize, ratio)
		end
	end

	if previous ~= nil and current < previous then
		binding.ShakeStartedAt = os.clock()
	end
end

local function currentVitals(binding)
	local player = binding.Player
	if not player or player.Parent ~= Players then
		return nil
	end
	return PetVitalsObserver.Read(player)[binding.PetSlot]
end

local function bindModel(model)
	if bindings[model] or not model:IsA("Model") then
		return
	end
	local ownerUserId = tonumber(model:GetAttribute("OwnerUserId"))
	local petSlot = tonumber(model:GetAttribute("PetSlot"))
	local petId = tostring(model:GetAttribute("PetId") or "")
	if not ownerUserId or not petSlot or petId == "" then
		return
	end
	petSlot = math.floor(petSlot)
	local player = Players:GetPlayerByUserId(ownerUserId)
	local root = resolveRoot(model)
	local template = resolveTemplate()
	if not player or not root or not template then
		return
	end

	local gui = template:Clone()
	gui.Name = HealthbarConfig.GuiName
	gui.Adornee = root
	gui.Enabled = false
	gui.Parent = root

	local widgets, reason = resolveWidgets(gui)
	if not widgets then
		gui:Destroy()
		warn(string.format("[Pawlands PetHealthbar] %s on %s.", tostring(reason), model:GetFullName()))
		return
	end

	local definition = Catalog.Pets[petId]
	if widgets.Icon and definition and type(definition.Icon) == "string" then
		widgets.Icon.Image = definition.Icon
	end

	local binding = {
		Model = model,
		Player = player,
		PetSlot = petSlot,
		Gui = gui,
		Widgets = widgets,
		FullFillSize = widgets.Fill.Size,
		FullShadowSize = widgets.Shadow and widgets.Shadow.Size or widgets.Fill.Size,
		BaseOffset = gui.StudsOffsetWorldSpace,
		LastHealth = nil,
		ShakeStartedAt = -math.huge,
		FillTween = nil,
		ShadowTween = nil,
		Connections = {},
		Released = false,
	}
	bindings[model] = binding

	table.insert(binding.Connections, model.Destroying:Connect(function()
		releaseModel(model)
	end))
	applyBinding(binding, currentVitals(binding), false)
end

local function refreshPlayer(player)
	for _, binding in pairs(bindings) do
		if binding.Player == player then
			applyBinding(binding, currentVitals(binding), true)
		end
	end
end

local function watchPlayer(player)
	if playerConnections[player] then
		return
	end
	playerConnections[player] = player:GetAttributeChangedSignal(VitalsConfig.AttributeName):Connect(function()
		refreshPlayer(player)
	end)
end

local function unwatchPlayer(player)
	local connection = playerConnections[player]
	if connection then
		connection:Disconnect()
		playerConnections[player] = nil
	end
end

local function bindFolder(folder)
	if activeFolder == folder then
		return
	end
	for _, connection in ipairs(folderConnections) do
		connection:Disconnect()
	end
	table.clear(folderConnections)
	if activeFolder then
		local models = {}
		for model in pairs(bindings) do
			table.insert(models, model)
		end
		for _, model in ipairs(models) do
			releaseModel(model)
		end
	end
	activeFolder = folder
	if not folder or not folder:IsA("Folder") then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		bindModel(child)
	end
	table.insert(folderConnections, folder.ChildAdded:Connect(bindModel))
	table.insert(folderConnections, folder.ChildRemoved:Connect(releaseModel))
end

function PetHealthbarController.Start()
	if stopCurrent then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	local playerAdded = Players.PlayerAdded:Connect(watchPlayer)
	local playerRemoving = Players.PlayerRemoving:Connect(unwatchPlayer)

	local existing = Workspace:FindFirstChild(FollowConfig.VisualFolderName)
	if existing and existing:IsA("Folder") then
		bindFolder(existing)
	end
	local workspaceAdded = Workspace.ChildAdded:Connect(function(child)
		if child.Name == FollowConfig.VisualFolderName and child:IsA("Folder") then
			bindFolder(child)
		end
	end)
	local workspaceRemoved = Workspace.ChildRemoved:Connect(function(child)
		if child == activeFolder then
			bindFolder(nil)
		end
	end)

	local renderConnection = RunService.PreRender:Connect(function()
		local clock = os.clock()
		for model, binding in pairs(bindings) do
			if binding.Released or not model.Parent or not binding.Gui.Parent then
				releaseModel(model)
				continue
			end
			local age = clock - binding.ShakeStartedAt
			if age >= 0 and age <= HealthbarConfig.ShakeSeconds then
				local t = age / math.max(0.01, HealthbarConfig.ShakeSeconds)
				local envelope = 1 - t
				local wave = math.sin(t * math.pi * 6)
				binding.Gui.StudsOffsetWorldSpace = binding.BaseOffset
					+ Vector3.new(wave * envelope * HealthbarConfig.ShakeStuds, 0, 0)
			else
				binding.Gui.StudsOffsetWorldSpace = binding.BaseOffset
			end
		end
	end)

	stopCurrent = function()
		playerAdded:Disconnect()
		playerRemoving:Disconnect()
		workspaceAdded:Disconnect()
		workspaceRemoved:Disconnect()
		renderConnection:Disconnect()
		for _, connection in ipairs(folderConnections) do
			connection:Disconnect()
		end
		table.clear(folderConnections)
		local watchedPlayers = {}
		for player in pairs(playerConnections) do
			table.insert(watchedPlayers, player)
		end
		for _, player in ipairs(watchedPlayers) do
			unwatchPlayer(player)
		end
		local models = {}
		for model in pairs(bindings) do
			table.insert(models, model)
		end
		for _, model in ipairs(models) do
			releaseModel(model)
		end
		activeFolder = nil
		templateCache = nil
	end
end

function PetHealthbarController.Stop()
	if not stopCurrent then
		return
	end
	local stop = stopCurrent
	stopCurrent = nil
	stop()
end

return PetHealthbarController
