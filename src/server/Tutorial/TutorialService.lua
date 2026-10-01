local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local TutorialConfig = require(Shared.Config.Tutorial)
local SlimeMovementConfig = require(Shared.Config.SlimeMovement)

local TutorialService = {}
local started = false
local slimeMovementService = nil
local heartbeatConnection = nil
local playerAddedConnection = nil
local playerRemovingConnection = nil
local runtimeChildAddedConnection = nil
local watchedSlimes = {}
local accumulator = 0
local waveActive = false
local waveGoal = 0
local waveDefeated = 0

local function stageOf(player)
	local stage = player:GetAttribute(TutorialConfig.StageAttributeName)
	if type(stage) ~= "string" or TutorialConfig.Stages[stage] == nil then
		return TutorialConfig.Stages.NotStarted
	end
	return stage
end

local function setStage(player, stage)
	player:SetAttribute(TutorialConfig.StageAttributeName, stage)
	local combatEligible = stage == TutorialConfig.Stages.GoToZone
		or stage == TutorialConfig.Stages.InCombat
	player:SetAttribute(TutorialConfig.CombatEligibleAttributeName, combatEligible)
end

local function setProgress(player, current, goal)
	player:SetAttribute(TutorialConfig.ProgressAttributeName, math.max(0, math.floor(current or 0)))
	player:SetAttribute(TutorialConfig.GoalAttributeName, math.max(0, math.floor(goal or 0)))
end

local function bindPlayer(player)
	if player:GetAttribute(TutorialConfig.StageAttributeName) == nil then
		setStage(player, TutorialConfig.Stages.NotStarted)
	else
		setStage(player, stageOf(player))
	end
	if player:GetAttribute(TutorialConfig.ProgressAttributeName) == nil then
		player:SetAttribute(TutorialConfig.ProgressAttributeName, 0)
	end
	if player:GetAttribute(TutorialConfig.GoalAttributeName) == nil then
		player:SetAttribute(TutorialConfig.GoalAttributeName, 0)
	end
end

local function activeParticipants()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if stageOf(player) == TutorialConfig.Stages.InCombat then
			count += 1
		end
	end
	return count
end

local function completeWave()
	if not waveActive then
		return
	end
	waveActive = false
	for _, player in ipairs(Players:GetPlayers()) do
		if stageOf(player) == TutorialConfig.Stages.InCombat then
			setProgress(player, waveGoal, waveGoal)
			setStage(player, TutorialConfig.Stages.ReturnToAlex)
		end
	end
end

local function onSlimeDefeated(model)
	if not waveActive or model:GetAttribute("TutorialDefeatCounted") == true then
		return
	end
	model:SetAttribute("TutorialDefeatCounted", true)
	waveDefeated = math.min(waveGoal, waveDefeated + 1)
	for _, player in ipairs(Players:GetPlayers()) do
		if stageOf(player) == TutorialConfig.Stages.InCombat then
			setProgress(player, waveDefeated, waveGoal)
		end
	end
	if waveGoal > 0 and waveDefeated >= waveGoal then
		completeWave()
	end
end

local function unwatchSlime(model)
	local record = watchedSlimes[model]
	if not record then
		return
	end
	if record.Defeated then
		record.Defeated:Disconnect()
	end
	if record.Ancestry then
		record.Ancestry:Disconnect()
	end
	watchedSlimes[model] = nil
end

local function watchSlime(model)
	if watchedSlimes[model] or not model:IsA("Model") then
		return
	end
	local record = {}
	record.Defeated = model:GetAttributeChangedSignal("Defeated"):Connect(function()
		if model:GetAttribute("Defeated") == true then
			onSlimeDefeated(model)
		end
	end)
	record.Ancestry = model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			unwatchSlime(model)
		end
	end)
	watchedSlimes[model] = record
	if model:GetAttribute("Defeated") == true then
		onSlimeDefeated(model)
	end
end

local function bindRuntimeFolder()
	local folder = Workspace:FindFirstChild(SlimeMovementConfig.RuntimeFolderName)
	if not folder or not folder:IsA("Folder") then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		watchSlime(child)
	end
	if runtimeChildAddedConnection then
		runtimeChildAddedConnection:Disconnect()
	end
	runtimeChildAddedConnection = folder.ChildAdded:Connect(watchSlime)
end

local function getAliveRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function beginWave()
	if waveActive then
		return true
	end
	local ok, spawnedOrReason = slimeMovementService.BeginTutorialEncounter()
	if not ok then
		return false, spawnedOrReason
	end
	waveActive = true
	waveGoal = math.max(1, tonumber(spawnedOrReason) or 0)
	waveDefeated = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if stageOf(player) == TutorialConfig.Stages.InCombat then
			setProgress(player, 0, waveGoal)
		end
	end
	return true
end

local function updateZoneEntries()
	for _, player in ipairs(Players:GetPlayers()) do
		if stageOf(player) == TutorialConfig.Stages.GoToZone then
			local root = getAliveRoot(player)
			if root and slimeMovementService.ContainsPosition(root.Position) then
				local ok = beginWave()
				if ok then
					setStage(player, TutorialConfig.Stages.InCombat)
					setProgress(player, waveDefeated, waveGoal)
				end
			end
		end
	end

	if waveActive and activeParticipants() <= 0 then
		waveActive = false
		waveGoal = 0
		waveDefeated = 0
		slimeMovementService.CancelTutorialEncounter()
	end
end

function TutorialService.HandleDialogueAction(player, action)
	if not started or not player or player.Parent ~= Players then
		return false
	end
	local stage = stageOf(player)
	if action == TutorialConfig.AcceptCombatAction then
		if stage == TutorialConfig.Stages.NotStarted then
			setProgress(player, 0, 0)
			setStage(player, TutorialConfig.Stages.GoToZone)
		end
		return stage == TutorialConfig.Stages.NotStarted
			or stage == TutorialConfig.Stages.GoToZone
			or stage == TutorialConfig.Stages.InCombat
	elseif action == TutorialConfig.CompleteCombatAction then
		if stage ~= TutorialConfig.Stages.ReturnToAlex then
			return false
		end
		setStage(player, TutorialConfig.Stages.Completed)
		setProgress(player, 0, 0)
		return true
	end
	return false
end

function TutorialService.Start(slimeService)
	if started then
		return
	end
	if not slimeService then
		error("TutorialService requires SlimeMovementService.")
	end
	started = true
	slimeMovementService = slimeService

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	playerAddedConnection = Players.PlayerAdded:Connect(bindPlayer)
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute(TutorialConfig.CombatEligibleAttributeName, false)
	end)

	slimeMovementService.SetPlayerEligibilityResolver(function(player)
		return player:GetAttribute(TutorialConfig.CombatEligibleAttributeName) == true
	end)
	bindRuntimeFolder()

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TutorialConfig.ZoneCheckSeconds then
			return
		end
		accumulator = 0
		updateZoneEntries()
	end)
end

function TutorialService.Stop()
	if not started then
		return
	end
	started = false
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	if runtimeChildAddedConnection then
		runtimeChildAddedConnection:Disconnect()
		runtimeChildAddedConnection = nil
	end
	for model in pairs(watchedSlimes) do
		unwatchSlime(model)
	end
	if slimeMovementService then
		slimeMovementService.SetPlayerEligibilityResolver(nil)
		slimeMovementService.CancelTutorialEncounter()
	end
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute(TutorialConfig.CombatEligibleAttributeName, false)
	end
	waveActive = false
	waveGoal = 0
	waveDefeated = 0
	accumulator = 0
	slimeMovementService = nil
end

return TutorialService
