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
local inputRemoteConnection = nil
local inputRemote = nil
local watchedSlimes = {}
local onboardingByPlayer = {}
local accumulator = 0
local waveActive = false
local waveGoal = 0
local waveDefeated = 0
local waveSpawned = 0
local waveExpanded = false
local waveExpansionStarted = false

local function stageOf(player)
	local stage = player:GetAttribute(TutorialConfig.StageAttributeName)
	if type(stage) ~= "string" or TutorialConfig.Stages[stage] == nil then
		return TutorialConfig.Stages.NotStarted
	end
	return stage
end

local function onboardingState(player)
	local state = onboardingByPlayer[player]
	if not state then
		state = {
			MoveOrigin = nil,
			SprintSeconds = 0,
			InputMode = nil,
			AttackLessonCompleted = false,
			OutsideCombatSeconds = 0,
			MissingCharacterSeconds = 0,
		}
		onboardingByPlayer[player] = state
	end
	return state
end

local function resetOnboardingProgress(player)
	local state = onboardingState(player)
	state.MoveOrigin = nil
	state.SprintSeconds = 0
	state.OutsideCombatSeconds = 0
	state.MissingCharacterSeconds = 0
end

local function setStage(player, stage)
	player:SetAttribute(TutorialConfig.StageAttributeName, stage)
	local combatEligible = stage == TutorialConfig.Stages.GoToZone
		or stage == TutorialConfig.Stages.LearnAttack
		or stage == TutorialConfig.Stages.InCombat
	player:SetAttribute(TutorialConfig.CombatEligibleAttributeName, combatEligible)
	resetOnboardingProgress(player)
end

local function setProgress(player, current, goal)
	player:SetAttribute(TutorialConfig.ProgressAttributeName, math.max(0, math.floor(current or 0)))
	player:SetAttribute(TutorialConfig.GoalAttributeName, math.max(0, math.floor(goal or 0)))
end

local function ensureInputRemote()
	local pawlands = ReplicatedStorage:WaitForChild("Pawlands")
	local folder = pawlands:FindFirstChild(TutorialConfig.RemoteFolderName)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = TutorialConfig.RemoteFolderName
		folder.Parent = pawlands
	end
	local remote = folder:FindFirstChild(TutorialConfig.InputModeRemoteName)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = TutorialConfig.InputModeRemoteName
		remote.Parent = folder
	end
	return remote
end

local function bindPlayer(player)
	local existingStage = stageOf(player)
	if player:GetAttribute(TutorialConfig.StageAttributeName) == nil
		or existingStage == TutorialConfig.Stages.NotStarted
	then
		setStage(player, TutorialConfig.Stages.LearnMove)
	else
		setStage(player, existingStage)
	end
	if player:GetAttribute(TutorialConfig.ProgressAttributeName) == nil then
		player:SetAttribute(TutorialConfig.ProgressAttributeName, 0)
	end
	if player:GetAttribute(TutorialConfig.GoalAttributeName) == nil then
		player:SetAttribute(TutorialConfig.GoalAttributeName, 0)
	end
	player:SetAttribute(TutorialConfig.InputModeAttributeName, "")
	local state = onboardingState(player)
	local stage = stageOf(player)
	state.AttackLessonCompleted = stage == TutorialConfig.Stages.InCombat
		or stage == TutorialConfig.Stages.ReturnToAlex
		or stage == TutorialConfig.Stages.SoloComplete
		or stage == TutorialConfig.Stages.ChooseStarterPet
		or stage == TutorialConfig.Stages.EquipStarterPet
		or stage == TutorialConfig.Stages.Completed
end

local function activeParticipants()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local stage = stageOf(player)
		if stage == TutorialConfig.Stages.LearnAttack or stage == TutorialConfig.Stages.InCombat then
			count += 1
		end
	end
	return count
end

local function clearWaveState(cancelRuntime)
	waveActive = false
	waveGoal = 0
	waveDefeated = 0
	waveSpawned = 0
	waveExpanded = false
	waveExpansionStarted = false
	if cancelRuntime and slimeMovementService then
		slimeMovementService.CancelTutorialEncounter()
	end
end

local function prepareCombatRetry(player, previousStage)
	local state = onboardingState(player)
	if previousStage == TutorialConfig.Stages.InCombat then
		state.AttackLessonCompleted = true
	end
	setProgress(player, 0, 0)
	setStage(player, TutorialConfig.Stages.GoToZone)
end

local function resetActiveCombatForRecovery()
	local recovered = false
	for _, player in ipairs(Players:GetPlayers()) do
		local stage = stageOf(player)
		if stage == TutorialConfig.Stages.LearnAttack or stage == TutorialConfig.Stages.InCombat then
			prepareCombatRetry(player, stage)
			recovered = true
		end
	end
	clearWaveState(true)
	return recovered
end

local function completeWave()
	if not waveActive then
		return
	end
	waveActive = false
	for _, player in ipairs(Players:GetPlayers()) do
		local stage = stageOf(player)
		if stage == TutorialConfig.Stages.LearnAttack or stage == TutorialConfig.Stages.InCombat then
			onboardingState(player).AttackLessonCompleted = true
			setProgress(player, waveGoal, waveGoal)
			setStage(player, TutorialConfig.Stages.ReturnToAlex)
		end
	end
end

local function updateCombatProgress()
	for _, player in ipairs(Players:GetPlayers()) do
		local stage = stageOf(player)
		if stage == TutorialConfig.Stages.LearnAttack or stage == TutorialConfig.Stages.InCombat then
			setProgress(player, waveDefeated, waveGoal)
		end
	end
end

local function expandCombatWave()
	if not waveActive or waveExpanded or waveExpansionStarted then
		return
	end
	waveExpansionStarted = true
	local remaining = math.max(0, TutorialConfig.SoloCombatSlimeCount - waveSpawned)
	if remaining <= 0 then
		waveExpanded = true
		waveExpansionStarted = false
		return
	end

	local ok, addedOrReason = slimeMovementService.AddTutorialSlimes(remaining)
	local added = math.max(0, tonumber(addedOrReason) or 0)
	waveSpawned += added
	if not ok then
		warn("[Pawlands Tutorial] Could not expand guided combat wave: " .. tostring(addedOrReason))
	end
	-- Use the number that actually spawned as the authoritative clear goal. This
	-- keeps the tutorial completable if an authored Slime asset is temporarily bad.
	waveGoal = math.max(waveDefeated, waveSpawned)
	waveExpanded = true
	waveExpansionStarted = false
	updateCombatProgress()
	if waveGoal > 0 and waveDefeated >= waveGoal then
		completeWave()
	end
end

local function onConfirmedPlayerHit(model)
	if not waveActive or model:GetAttribute("TutorialEncounter") ~= true then
		return
	end
	if tostring(model:GetAttribute("LastPlayerHitActionType") or "") ~= TutorialConfig.RequiredAttackActionType then
		return
	end
	local userId = tonumber(model:GetAttribute("LastPlayerHitUserId")) or 0
	local player = userId > 0 and Players:GetPlayerByUserId(userId) or nil
	if not player or stageOf(player) ~= TutorialConfig.Stages.LearnAttack then
		return
	end

	onboardingState(player).AttackLessonCompleted = true
	setStage(player, TutorialConfig.Stages.InCombat)
	setProgress(player, waveDefeated, waveGoal)
	expandCombatWave()
end

local function onSlimeDefeated(model)
	if not waveActive or model:GetAttribute("TutorialDefeatCounted") == true then
		return
	end
	model:SetAttribute("TutorialDefeatCounted", true)
	waveDefeated = math.min(waveGoal, waveDefeated + 1)
	updateCombatProgress()
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
	if record.PlayerHit then
		record.PlayerHit:Disconnect()
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
	record.PlayerHit = model:GetAttributeChangedSignal("PlayerHitSerial"):Connect(function()
		onConfirmedPlayerHit(model)
	end)
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
		return nil, nil
	end
	return root, humanoid
end

local function horizontalDistance(a, b)
	local delta = a - b
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

local function horizontalSpeed(root)
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function updateOnboarding(player, dt)
	local stage = stageOf(player)
	if stage ~= TutorialConfig.Stages.LearnMove and stage ~= TutorialConfig.Stages.LearnSprint then
		return
	end
	local root, humanoid = getAliveRoot(player)
	if not root or not humanoid then
		return
	end
	local state = onboardingState(player)
	if stage == TutorialConfig.Stages.LearnMove then
		if not state.MoveOrigin then
			state.MoveOrigin = root.Position
			return
		end
		if horizontalDistance(root.Position, state.MoveOrigin) >= TutorialConfig.MoveLessonDistanceStuds then
			if state.InputMode == TutorialConfig.InputModes.Touch then
				setStage(player, TutorialConfig.Stages.MeetAlex)
			else
				setStage(player, TutorialConfig.Stages.LearnSprint)
			end
		end
		return
	end

	if state.InputMode == TutorialConfig.InputModes.Touch then
		setStage(player, TutorialConfig.Stages.MeetAlex)
		return
	end
	if horizontalSpeed(root) >= TutorialConfig.SprintLessonMinSpeedStuds then
		state.SprintSeconds += dt
	else
		state.SprintSeconds = math.max(0, state.SprintSeconds - dt * 0.5)
	end
	if state.SprintSeconds >= TutorialConfig.SprintLessonRequiredSeconds then
		setStage(player, TutorialConfig.Stages.MeetAlex)
	end
end

local function beginWave(initialCount)
	if waveActive then
		return true
	end
	local requestedInitial = math.clamp(
		math.floor(tonumber(initialCount) or TutorialConfig.AttackLessonInitialSlimeCount),
		1,
		TutorialConfig.SoloCombatSlimeCount
	)
	local ok, spawnedOrReason = slimeMovementService.BeginTutorialEncounter(
		requestedInitial,
		TutorialConfig.SoloCombatSlimeCount
	)
	if not ok then
		return false, spawnedOrReason
	end
	waveActive = true
	waveSpawned = math.max(1, tonumber(spawnedOrReason) or 0)
	waveDefeated = 0
	waveExpanded = requestedInitial >= TutorialConfig.SoloCombatSlimeCount
	waveGoal = waveExpanded and waveSpawned or TutorialConfig.SoloCombatSlimeCount
	waveExpansionStarted = false
	updateCombatProgress()
	return true
end

local function updateCombatPresence(dt)
	local resetAny = false
	for _, player in ipairs(Players:GetPlayers()) do
		local stage = stageOf(player)
		if stage ~= TutorialConfig.Stages.LearnAttack and stage ~= TutorialConfig.Stages.InCombat then
			continue
		end

		local state = onboardingState(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if humanoid and humanoid.Health <= 0 then
			prepareCombatRetry(player, stage)
			resetAny = true
			continue
		end

		if not root or not root:IsA("BasePart") then
			state.MissingCharacterSeconds += dt
			if state.MissingCharacterSeconds >= TutorialConfig.CombatMissingCharacterGraceSeconds then
				prepareCombatRetry(player, stage)
				resetAny = true
			end
			continue
		end

		state.MissingCharacterSeconds = 0
		local exitPadding = -math.max(0, TutorialConfig.CombatExitLeewayStuds or 0)
		if slimeMovementService.ContainsPosition(root.Position, exitPadding) then
			state.OutsideCombatSeconds = 0
		else
			state.OutsideCombatSeconds += dt
			if state.OutsideCombatSeconds >= TutorialConfig.CombatExitGraceSeconds then
				prepareCombatRetry(player, stage)
				resetAny = true
			end
		end
	end

	if resetAny and activeParticipants() <= 0 and waveActive then
		clearWaveState(true)
	end
end

local function reconcileWaveIntegrity()
	if not waveActive or not slimeMovementService.GetTutorialEncounterSnapshot then
		return
	end
	local snapshot = slimeMovementService.GetTutorialEncounterSnapshot()
	if type(snapshot) ~= "table" then
		return
	end
	local expectedLive = math.max(0, waveSpawned - waveDefeated)
	local liveCount = math.max(0, tonumber(snapshot.LiveCount) or 0)
	if snapshot.Active ~= true or liveCount ~= expectedLive then
		local recovered = resetActiveCombatForRecovery()
		if recovered and RunService:IsStudio() then
			print(string.format(
				"[Pawlands Tutorial] Recovered tutorial encounter integrity (%d expected live, %d found).",
				expectedLive,
				liveCount
			))
		end
	end
end

local function updateZoneEntries()
	for _, player in ipairs(Players:GetPlayers()) do
		if stageOf(player) == TutorialConfig.Stages.GoToZone then
			local root = getAliveRoot(player)
			if root and slimeMovementService.ContainsPosition(root.Position) then
				local state = onboardingState(player)
				local attackLessonCompleted = state.AttackLessonCompleted == true
				local initialCount = attackLessonCompleted
					and TutorialConfig.SoloCombatSlimeCount
					or TutorialConfig.AttackLessonInitialSlimeCount
				local ok = beginWave(initialCount)
				if ok then
					if attackLessonCompleted then
						setStage(player, TutorialConfig.Stages.InCombat)
						if not waveExpanded then
							expandCombatWave()
						end
					else
						-- Every first-time participant gets the contextual attack lesson. The
						-- shared encounter may already be expanded by another Player, but this
						-- Player's hint stays until their own confirmed direct M1 lands.
						setStage(player, TutorialConfig.Stages.LearnAttack)
					end
					setProgress(player, waveDefeated, waveGoal)
				end
			end
		end
	end

	if waveActive and activeParticipants() <= 0 then
		clearWaveState(true)
	end
end

local function handleInputMode(player, mode)
	if not started or player.Parent ~= Players or type(mode) ~= "string" then
		return
	end
	if mode ~= TutorialConfig.InputModes.Keyboard
		and mode ~= TutorialConfig.InputModes.Gamepad
		and mode ~= TutorialConfig.InputModes.Touch
	then
		return
	end
	local state = onboardingState(player)
	state.InputMode = mode
	player:SetAttribute(TutorialConfig.InputModeAttributeName, mode)
	if mode == TutorialConfig.InputModes.Touch and stageOf(player) == TutorialConfig.Stages.LearnSprint then
		setStage(player, TutorialConfig.Stages.MeetAlex)
	end
end

function TutorialService.HandleDialogueAction(player, action)
	if not started or not player or player.Parent ~= Players then
		return false
	end
	local stage = stageOf(player)
	if action == TutorialConfig.AcceptCombatAction then
		if stage == TutorialConfig.Stages.MeetAlex then
			onboardingState(player).AttackLessonCompleted = false
			setProgress(player, 0, 0)
			setStage(player, TutorialConfig.Stages.GoToZone)
			return true
		end
		return stage == TutorialConfig.Stages.GoToZone or stage == TutorialConfig.Stages.InCombat
	elseif action == TutorialConfig.CompleteSoloCombatAction
		or action == TutorialConfig.CompleteCombatAction
	then
		if stage ~= TutorialConfig.Stages.ReturnToAlex then
			return false
		end
		setStage(player, TutorialConfig.Stages.SoloComplete)
		setProgress(player, 0, 0)
		return true
	elseif action == TutorialConfig.BeginStarterPetChoiceAction then
		if stage ~= TutorialConfig.Stages.SoloComplete then
			return false
		end
		setStage(player, TutorialConfig.Stages.ChooseStarterPet)
		setProgress(player, 0, 0)
		return true
	end
	return false
end

function TutorialService.CanChooseStarterPet(player)
	return started
		and player ~= nil
		and player.Parent == Players
		and stageOf(player) == TutorialConfig.Stages.ChooseStarterPet
end

function TutorialService.CompleteStarterPetChoice(player)
	if not TutorialService.CanChooseStarterPet(player) then
		return false
	end
	setStage(player, TutorialConfig.Stages.EquipStarterPet)
	setProgress(player, 0, 0)
	return true
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
	inputRemote = ensureInputRemote()
	inputRemoteConnection = inputRemote.OnServerEvent:Connect(handleInputMode)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	playerAddedConnection = Players.PlayerAdded:Connect(bindPlayer)
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute(TutorialConfig.CombatEligibleAttributeName, false)
		onboardingByPlayer[player] = nil
		task.defer(function()
			if started and waveActive and activeParticipants() <= 0 then
				clearWaveState(true)
			end
		end)
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
		local stepDt = accumulator
		accumulator = 0
		for _, player in ipairs(Players:GetPlayers()) do
			updateOnboarding(player, stepDt)
		end
		updateCombatPresence(stepDt)
		reconcileWaveIntegrity()
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
	if inputRemoteConnection then
		inputRemoteConnection:Disconnect()
		inputRemoteConnection = nil
	end
	for model in pairs(watchedSlimes) do
		unwatchSlime(model)
	end
	if slimeMovementService then
		slimeMovementService.SetPlayerEligibilityResolver(nil)
		clearWaveState(true)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute(TutorialConfig.CombatEligibleAttributeName, false)
	end
	table.clear(onboardingByPlayer)
	accumulator = 0
	inputRemote = nil
	slimeMovementService = nil
end

return TutorialService
