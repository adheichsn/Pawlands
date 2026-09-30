local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local FeedbackConfig = require(Shared.Config.SlimeFeedback)
local MovementConfig = require(Shared.Config.SlimeMovement)
local CombatEffects = require(script.Parent.Parent.Combat.CombatEffects)

local SlimeFeedbackController = {}
local stopCurrent

local records = {}
local activeFolder = nil
local folderConnections = {}
local renderConnection = nil

local function disconnectConnections(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function safeScale(model, scale)
	if not model.Parent then
		return
	end
	pcall(function()
		model:ScaleTo(math.max(0.01, scale))
	end)
end

local function safePivot(model, frame)
	if not model.Parent then
		return
	end
	pcall(function()
		model:PivotTo(frame)
	end)
end

local function resolveBodyMotor(record)
	local motor = record.BodyMotor
	if motor and motor.Parent and motor:IsA("Motor6D") then
		return motor
	end

	motor = record.Model:FindFirstChild(FeedbackConfig.BodyMotorName, true)
	if not motor or not motor:IsA("Motor6D") then
		return nil
	end

	-- Only offset the authored body motor when its Part0 is the runtime RootPart.
	-- This keeps the reaction additive and prevents a malformed asset from moving
	-- the authoritative root through an unexpected joint layout.
	local part0 = motor.Part0
	if not part0 or part0.Name ~= FeedbackConfig.RootPartName then
		return nil
	end

	record.BodyMotor = motor
	record.BaseMotorC0 = motor.C0
	return motor
end

local function restoreHitPose(record)
	local motor = record.BodyMotor
	if motor and motor.Parent and record.BaseMotorC0 then
		motor.C0 = record.BaseMotorC0
	end
	record.HitStartedAt = nil
end

local function resolveBaseScale(model)
	local ok, scale = pcall(function()
		return model:GetScale()
	end)
	if ok and type(scale) == "number" and scale > 0 then
		return scale
	end
	return 1
end

local function setHealthbarEnabled(model, enabled)
	local root = model:FindFirstChild(FeedbackConfig.RootPartName, true)
	local gui = root and root:FindFirstChild(FeedbackConfig.HealthbarGuiName)
	if gui and gui:IsA("BillboardGui") then
		gui.Enabled = enabled
	end
end

local function beginHit(record)
	if record.DefeatStartedAt or record.Model:GetAttribute("Defeated") == true then
		return
	end

	local tier = record.Model:GetAttribute("LastHitFeedbackTier")
	if tier ~= FeedbackConfig.FeedbackTiers.Finisher then
		tier = FeedbackConfig.FeedbackTiers.Light
	end

	local direction = record.Model:GetAttribute("LastHitDirection")
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.001 then
		direction = record.Model:GetPivot().LookVector
	else
		direction = direction.Unit
	end

	restoreHitPose(record)
	resolveBodyMotor(record)
	if record.Model:GetAttribute("LastHitSourceType") == "Pet" then
		CombatEffects.PlayPetHitSlime(record.Model)
	else
		CombatEffects.PlayPlayerHitSlime(record.Model, record.Model:GetAttribute("HitSerial"))
	end
	record.HitTier = tier
	record.HitDirection = direction
	record.HitStartedAt = os.clock()
end

local function beginDefeat(record)
	if record.DefeatStartedAt then
		return
	end

	restoreHitPose(record)
	CombatEffects.PlaySlimeDefeat(record.Model)
	local defeatedAt = tonumber(record.Model:GetAttribute("DefeatedAt"))
	record.DefeatStartedAt = defeatedAt and defeatedAt > 0
		and defeatedAt
		or Workspace:GetServerTimeNow()
	record.DefeatBasePivot = record.Model:GetPivot()
	record.DefeatBaseScale = record.BaseScale
end

local function updateHit(record, now)
	local startedAt = record.HitStartedAt
	if not startedAt then
		return
	end

	local finisher = record.HitTier == FeedbackConfig.FeedbackTiers.Finisher
	local duration = finisher
		and FeedbackConfig.Hit.FinisherDurationSeconds
		or FeedbackConfig.Hit.LightDurationSeconds
	local elapsed = now - startedAt
	if elapsed >= duration then
		restoreHitPose(record)
		return
	end

	local motor = resolveBodyMotor(record)
	if not motor or not record.BaseMotorC0 or not motor.Part0 then
		return
	end

	local alpha = math.clamp(elapsed / math.max(0.001, duration), 0, 1)
	local pulse = math.sin(alpha * math.pi)
	local recoil = finisher
		and FeedbackConfig.Hit.FinisherRecoilStuds
		or FeedbackConfig.Hit.LightRecoilStuds
	local dip = finisher
		and FeedbackConfig.Hit.FinisherDipStuds
		or FeedbackConfig.Hit.LightDipStuds

	local direction = record.HitDirection or record.Model:GetPivot().LookVector
	local localDirection = motor.Part0.CFrame:VectorToObjectSpace(direction)
	local localOffset = (localDirection * (recoil * pulse))
		+ Vector3.new(0, -(dip * pulse), 0)
	motor.C0 = CFrame.new(localOffset) * record.BaseMotorC0
end

local function easeOutQuad(alpha)
	alpha = math.clamp(alpha, 0, 1)
	return 1 - ((1 - alpha) * (1 - alpha))
end

local function lerp(a, b, alpha)
	return a + (b - a) * alpha
end

local function updateDefeat(record, now)
	local startedAt = record.DefeatStartedAt
	if not startedAt then
		return
	end

	local config = FeedbackConfig.Defeat
	local elapsed = now - startedAt
	local scaleFactor = 1
	local hop = 0

	if elapsed < config.PauseSeconds then
		scaleFactor = 1
	elseif elapsed < config.SquashEndSeconds then
		local alpha = (elapsed - config.PauseSeconds)
			/ math.max(0.001, config.SquashEndSeconds - config.PauseSeconds)
		scaleFactor = lerp(1, config.SquashScale, easeOutQuad(alpha))
	elseif elapsed < config.PopEndSeconds then
		local alpha = (elapsed - config.SquashEndSeconds)
			/ math.max(0.001, config.PopEndSeconds - config.SquashEndSeconds)
		local eased = easeOutQuad(alpha)
		scaleFactor = lerp(config.SquashScale, config.PopScale, eased)
		hop = config.HopHeightStuds * 0.55 * eased
	else
		local alpha = (elapsed - config.PopEndSeconds)
			/ math.max(0.001, config.EndSeconds - config.PopEndSeconds)
		local eased = easeOutQuad(alpha)
		scaleFactor = lerp(config.PopScale, config.EndScale, eased)
		hop = lerp(config.HopHeightStuds * 0.55, config.HopHeightStuds, eased)
	end

	if elapsed >= config.HideHealthbarAtSeconds then
		setHealthbarEnabled(record.Model, false)
	end

	safeScale(record.Model, (record.DefeatBaseScale or record.BaseScale) * scaleFactor)
	if record.DefeatBasePivot then
		safePivot(record.Model, record.DefeatBasePivot + Vector3.new(0, hop, 0))
	end
end

local function releaseModel(model)
	local record = records[model]
	if not record then
		return
	end
	records[model] = nil
	disconnectConnections(record.Connections)

	if model.Parent and not record.DefeatStartedAt then
		restoreHitPose(record)
		safeScale(model, record.BaseScale)
	end
end

local function watchModel(model)
	if not model:IsA("Model") or records[model] then
		return
	end

	local record = {
		Model = model,
		BaseScale = resolveBaseScale(model),
		LastHitSerial = tonumber(model:GetAttribute("HitSerial")) or 0,
		BodyMotor = nil,
		BaseMotorC0 = nil,
		HitStartedAt = nil,
		HitTier = FeedbackConfig.FeedbackTiers.Light,
		HitDirection = Vector3.zero,
		DefeatStartedAt = nil,
		DefeatBasePivot = nil,
		DefeatBaseScale = nil,
		Connections = {},
	}
	records[model] = record
	resolveBodyMotor(record)

	table.insert(record.Connections, model:GetAttributeChangedSignal("HitSerial"):Connect(function()
		local serial = tonumber(model:GetAttribute("HitSerial")) or 0
		if serial <= record.LastHitSerial then
			record.LastHitSerial = serial
			return
		end
		record.LastHitSerial = serial
		task.defer(function()
			if records[model] == record and model.Parent then
				beginHit(record)
			end
		end)
	end))

	table.insert(record.Connections, model:GetAttributeChangedSignal("Defeated"):Connect(function()
		if model:GetAttribute("Defeated") == true then
			task.defer(function()
				if records[model] == record and model.Parent then
					beginDefeat(record)
				end
			end)
		end
	end))

	table.insert(record.Connections, model.DescendantAdded:Connect(function(descendant)
		if descendant.Name == FeedbackConfig.BodyMotorName and descendant:IsA("Motor6D") then
			record.BodyMotor = nil
			record.BaseMotorC0 = nil
			resolveBodyMotor(record)
		end
	end))

	table.insert(record.Connections, model.Destroying:Connect(function()
		releaseModel(model)
	end))

	if model:GetAttribute("Defeated") == true then
		beginDefeat(record)
	end
end

local function releaseAllModels()
	local models = {}
	for model in pairs(records) do
		table.insert(models, model)
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

function SlimeFeedbackController.Start()
	if stopCurrent then
		return
	end

	local existing = Workspace:FindFirstChild(MovementConfig.RuntimeFolderName)
	if existing then
		bindFolder(existing)
	end

	local addedConnection = Workspace.ChildAdded:Connect(function(child)
		if child.Name == MovementConfig.RuntimeFolderName and child:IsA("Folder") then
			bindFolder(child)
		end
	end)
	local removedConnection = Workspace.ChildRemoved:Connect(function(child)
		if child == activeFolder then
			unbindFolder()
		end
	end)

	renderConnection = RunService.RenderStepped:Connect(function()
		local localNow = os.clock()
		local serverNow = Workspace:GetServerTimeNow()
		for model, record in pairs(records) do
			if not model.Parent then
				releaseModel(model)
			elseif record.DefeatStartedAt then
				updateDefeat(record, serverNow)
			elseif record.HitStartedAt then
				updateHit(record, localNow)
			end
		end
	end)

	stopCurrent = function()
		addedConnection:Disconnect()
		removedConnection:Disconnect()
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
		unbindFolder()
	end
end

function SlimeFeedbackController.Stop()
	if not stopCurrent then
		return
	end
	local stop = stopCurrent
	stopCurrent = nil
	stop()
end

return SlimeFeedbackController
