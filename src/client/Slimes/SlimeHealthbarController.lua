local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local HealthbarConfig = require(Shared.Config.SlimeHealthbar)
local SlimeMovementConfig = require(Shared.Config.SlimeMovement)

local SlimeHealthbarController = {}
local stopCurrent

local bindings = {}
local pending = {}
local activeFolder = nil
local folderConnections = {}
local warnedMissing = {}
local healthbarTemplate = nil

local function disconnectConnections(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

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

local function warnMissingOnce(model, detail)
	local modelWarnings = warnedMissing[model]
	if not modelWarnings then
		modelWarnings = {}
		warnedMissing[model] = modelWarnings
	end
	if modelWarnings[detail] then
		return
	end
	modelWarnings[detail] = true
	warn(string.format(
		"[Pawlands SlimeHealthbar] %s on %s after %.1fs replication grace.",
		detail,
		model:GetFullName(),
		HealthbarConfig.ReplicationGraceSeconds
	))
end

local function resolveTemplate()
	if healthbarTemplate and healthbarTemplate.Parent then
		return healthbarTemplate
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local misc = assets and assets:FindFirstChild(HealthbarConfig.TemplateFolderName)
	local template = misc and misc:FindFirstChild(HealthbarConfig.GuiName)
	if template and template:IsA("BillboardGui") then
		healthbarTemplate = template
		return template
	end

	return nil
end

local function resolveGuiParts(gui)
	local progress = gui:FindFirstChild(HealthbarConfig.ProgressName)
	local fill = progress and progress:FindFirstChild(HealthbarConfig.FillName)
	local text = progress and progress:FindFirstChild(HealthbarConfig.TextName)
	if not progress or not progress:IsA("Frame") then
		return nil, nil, "template missing SlimeHealthbar > Progress Frame"
	end
	if not fill or not fill:IsA("Frame") then
		return nil, nil, "template missing SlimeHealthbar > Progress > Health Frame"
	end
	if not text or not text:IsA("TextLabel") then
		return nil, nil, "template missing SlimeHealthbar > Progress > ProgressText TextLabel"
	end
	return fill, text, nil
end

local function releaseBinding(model)
	local binding = bindings[model]
	if not binding then
		return
	end
	bindings[model] = nil
	binding.Released = true
	if binding.Tween then
		binding.Tween:Cancel()
		binding.Tween = nil
	end
	disconnectConnections(binding.Connections)
	if binding.OwnsGui and binding.Gui and binding.Gui.Parent then
		binding.Gui:Destroy()
	end
end

local function releasePending(model)
	local record = pending[model]
	if not record then
		return
	end
	pending[model] = nil
	record.Released = true
	disconnectConnections(record.Connections)
end

local function releaseModel(model)
	releasePending(model)
	releaseBinding(model)
	warnedMissing[model] = nil
end

local function shouldShow(model, health, maxHealth)
	if maxHealth <= 0 or health <= 0 or model:GetAttribute("Defeated") == true then
		return false
	end

	-- Combat ownership, not missing HP, owns visibility. A Slime that has returned
	-- to Idle/Wander keeps its authoritative Health but no longer leaves a stale
	-- world-space bar floating over a non-combat actor.
	return HealthbarConfig.VisibleStates[model:GetAttribute("SlimeState")] == true
end

local function createRuntimeGui(root)
	local existing = root:FindFirstChild(HealthbarConfig.GuiName)
	if existing and existing:IsA("BillboardGui") then
		return existing, false, nil
	end

	local template = resolveTemplate()
	if not template then
		return nil, false, "missing ReplicatedStorage > Assets > Misc > SlimeHealthbar template"
	end

	local gui = template:Clone()
	gui.Name = HealthbarConfig.GuiName
	gui.Enabled = false
	gui.Adornee = root
	gui.Parent = root
	return gui, true, nil
end

local function bindReadyModel(model, root, gui, ownsGui, fill, progressText)
	if bindings[model] then
		return
	end

	releasePending(model)

	local binding = {
		Gui = gui,
		OwnsGui = ownsGui,
		Fill = fill,
		Text = progressText,
		FullSize = fill.Size,
		Connections = {},
		Tween = nil,
		Released = false,
	}
	bindings[model] = binding

	gui.Adornee = root

	local function apply(animate)
		if binding.Released or bindings[model] ~= binding or not model.Parent then
			return
		end

		local maxHealth = math.max(0, tonumber(model:GetAttribute("MaxHealth")) or 0)
		local health = math.clamp(tonumber(model:GetAttribute("Health")) or maxHealth, 0, maxHealth)
		local ratio = maxHealth > 0 and health / maxHealth or 0
		local targetSize = healthSize(binding.FullSize, ratio)

		if binding.Tween then
			binding.Tween:Cancel()
			binding.Tween = nil
		end
		if animate and HealthbarConfig.TweenSeconds > 0 and fill.Parent then
			binding.Tween = TweenService:Create(
				fill,
				TweenInfo.new(HealthbarConfig.TweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = targetSize }
			)
			binding.Tween:Play()
		else
			fill.Size = targetSize
		end

		progressText.Text = string.format("%d / %d", roundHealth(health), roundHealth(maxHealth))
		gui.Enabled = shouldShow(model, health, maxHealth)
	end

	table.insert(binding.Connections, model:GetAttributeChangedSignal("Health"):Connect(function()
		apply(true)
	end))
	table.insert(binding.Connections, model:GetAttributeChangedSignal("MaxHealth"):Connect(function()
		apply(false)
	end))
	table.insert(binding.Connections, model:GetAttributeChangedSignal("Defeated"):Connect(function()
		apply(false)
	end))
	table.insert(binding.Connections, model:GetAttributeChangedSignal("SlimeState"):Connect(function()
		apply(false)
	end))
	table.insert(binding.Connections, model.Destroying:Connect(function()
		releaseModel(model)
	end))

	apply(false)
end

local function tryBindModel(model)
	if bindings[model] or not model.Parent or not model:IsA("Model") then
		return bindings[model] ~= nil
	end
	if model:GetAttribute("SlimeId") == nil then
		return false
	end

	local root = model:FindFirstChild(HealthbarConfig.RootPartName, true)
	if not root or not root:IsA("BasePart") then
		return false
	end

	local gui, ownsGui, createReason = createRuntimeGui(root)
	if not gui then
		if createReason then
			warnMissingOnce(model, createReason)
		end
		return false
	end

	local fill, progressText, partsReason = resolveGuiParts(gui)
	if not fill then
		if ownsGui and gui.Parent then
			gui:Destroy()
		end
		if partsReason then
			warnMissingOnce(model, partsReason)
		end
		return false
	end

	bindReadyModel(model, root, gui, ownsGui, fill, progressText)
	return true
end

local function reportPendingFailure(model)
	local record = pending[model]
	if not record or record.Released or bindings[model] or not model.Parent then
		return
	end

	-- Runtime slime models may be visible to the client before attributes or the
	-- authored RootPart have replicated/streamed in. Those are transient client
	-- states, not malformed slime assets: keep the model pending and let the
	-- existing attribute/DescendantAdded listeners retry when replication catches
	-- up. The server-side SlimeFactory already rejects templates without RootPart.
	if model:GetAttribute("SlimeId") == nil then
		return
	end

	local root = model:FindFirstChild(HealthbarConfig.RootPartName, true)
	if not root or not root:IsA("BasePart") then
		return
	end

	-- Once the replicated model itself is bind-ready, configuration/template
	-- failures are actionable and should still remain visible in Studio logs.
	if not resolveTemplate() and not root:FindFirstChild(HealthbarConfig.GuiName) then
		warnMissingOnce(model, "missing ReplicatedStorage > Assets > Misc > SlimeHealthbar template")
	end
end

local function watchModel(model)
	if not model:IsA("Model") or bindings[model] or pending[model] then
		return
	end

	local record = {
		Connections = {},
		Released = false,
	}
	pending[model] = record

	local function retry()
		if record.Released or pending[model] ~= record then
			return
		end
		tryBindModel(model)
	end

	-- Runtime slime models can replicate to the client before RootPart/attributes.
	-- The healthbar itself is cloned locally from the single Studio-authored master
	-- template as soon as the slime is ready to bind.
	table.insert(record.Connections, model.DescendantAdded:Connect(retry))
	table.insert(record.Connections, model:GetAttributeChangedSignal("SlimeId"):Connect(retry))
	table.insert(record.Connections, model.Destroying:Connect(function()
		releaseModel(model)
	end))

	retry()

	task.delay(HealthbarConfig.ReplicationGraceSeconds, function()
		if pending[model] == record and not record.Released then
			retry()
			reportPendingFailure(model)
		end
	end)
end

local function releaseAllModels()
	local models = {}
	for model in pairs(bindings) do
		table.insert(models, model)
	end
	for model in pairs(pending) do
		if not bindings[model] then
			table.insert(models, model)
		end
	end
	for _, model in ipairs(models) do
		releaseModel(model)
	end
end

local function unbindFolder()
	disconnectConnections(folderConnections)
	releaseAllModels()
	activeFolder = nil
end

local function bindFolder(folder)
	if activeFolder == folder then
		return
	end
	unbindFolder()
	if not folder or not folder:IsA("Folder") then
		return
	end

	activeFolder = folder
	for _, child in ipairs(folder:GetChildren()) do
		watchModel(child)
	end

	table.insert(folderConnections, folder.ChildAdded:Connect(watchModel))
	table.insert(folderConnections, folder.ChildRemoved:Connect(releaseModel))
end

function SlimeHealthbarController.Start()
	if stopCurrent then
		return
	end

	local existing = Workspace:FindFirstChild(SlimeMovementConfig.RuntimeFolderName)
	if existing then
		bindFolder(existing)
	end

	local addedConnection = Workspace.ChildAdded:Connect(function(child)
		if child.Name == SlimeMovementConfig.RuntimeFolderName and child:IsA("Folder") then
			bindFolder(child)
		end
	end)
	local removedConnection = Workspace.ChildRemoved:Connect(function(child)
		if child == activeFolder then
			unbindFolder()
		end
	end)

	stopCurrent = function()
		addedConnection:Disconnect()
		removedConnection:Disconnect()
		unbindFolder()
		table.clear(warnedMissing)
		healthbarTemplate = nil
	end
end

function SlimeHealthbarController.Stop()
	if not stopCurrent then
		return
	end
	local stop = stopCurrent
	stopCurrent = nil
	stop()
end

return SlimeHealthbarController
