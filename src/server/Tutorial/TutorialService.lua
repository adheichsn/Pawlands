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
local petPartyService = nil
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
local waveMode = nil
local wavePlannedCount = 0
local waveStartInProgress = false
local waveGenerationCounter = 0
local activeWaveGeneration = nil

local WAVE_MODES = table.freeze({
	Player = "Player",
	Pet = "Pet",
})

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
	local combatEligible = stage == TutorialConfig.Stages.LearnAttack
		or stage == TutorialConfig.Stages.InCombat
		or stage == TutorialConfig.Stages.LearnPetCombat
		or stage == TutorialConfig.Stages.PetInCombat
	player:SetAttribute(TutorialConfig.CombatEligibleAttributeName, combatEligible)
	resetOnboardingProgress(player)
end

local function setProgress(player, current, goal)
	player:SetAttribute(TutorialConfig.ProgressAttributeName, math.max(0, math.floor(current or 0)))
	player:SetAttribute(TutorialConfig.GoalAttributeName, math.max(0, math.floor(goal or 0)))
end

local function starterPetHitConfirmed(player)
	return player:GetAttribute(TutorialConfig.StarterPetHitConfirmedAttributeName) == true
end

local function setStarterPetHitConfirmed(player, confirmed)
	player:SetAttribute(TutorialConfig.StarterPetHitConfirmedAttributeName, confirmed == true)
end

local function starterPetIsEquipped(player)
	local starterUid = player:GetAttribute(TutorialConfig.StarterPetUidAttributeName)
	if type(starterUid) ~= "string" or starterUid == "" or not petPartyService then
		return false
	end
	return petPartyService.IsEquipped(player, starterUid) == true
end

local function reconcileStarterPetEquip(player)
	if stageOf(player) ~= TutorialConfig.Stages.EquipStarterPet then
		return false
	end
	if player:GetAttribute(TutorialConfig.StarterPetGrantedAttributeName) ~= true then
		return false
	end
	if not starterPetIsEquipped(player) then
		return false
	end
	setStarterPetHitConfirmed(player, false)
	setProgress(player, 0, 0)
	setStage(player, TutorialConfig.Stages.PetCombatReady)
	return true
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
	local state = onboardingState(player)
	state.AttackLessonCompleted = existingStage == TutorialConfig.Stages.InCombat
		or existingStage == TutorialConfig.Stages.ReturnToAlex
		or existingStage == TutorialConfig.Stages.SoloComplete
		or existingStage == TutorialConfig.Stages.ChooseStarterPet
		or existingStage == TutorialConfig.Stages.EquipStarterPet
		or existingStage == TutorialConfig.Stages.PetCombatReady
		or existingStage == TutorialConfig.Stages.LearnPetCombat
		or existingStage == TutorialConfig.Stages.PetInCombat
		or existingStage == TutorialConfig.Stages.Completed

	if player:GetAttribute(TutorialConfig.ProgressAttributeName) == nil then
		player:SetAttribute(TutorialConfig.ProgressAttributeName, 0)
	end
	if player:GetAttribute(TutorialConfig.GoalAttributeName) == nil then
		player:SetAttribute(TutorialConfig.GoalAttributeName, 0)
	end
	player:SetAttribute(TutorialConfig.InputModeAttributeName, "")

	local petHitAttribute = player:GetAttribute(TutorialConfig.StarterPetHitConfirmedAttributeName)
	if existingStage == TutorialConfig.Stages.PetInCombat
		or existingStage == TutorialConfig.Stages.Completed
	then
		setStarterPetHitConfirmed(player, true)
	elseif existingStage == TutorialConfig.Stages.ChooseStarterPet
		or existingStage == TutorialConfig.Stages.EquipStarterPet
		or existingStage == TutorialConfig.Stages.LearnPetCombat
	then
		-- These stages are still before the automatic Pet-combat gate. A stale true
		-- checkpoint here would incorrectly skip the exact starter-Pet hit lesson.
		setStarterPetHitConfirmed(player, false)
	elseif petHitAttribute == nil then
		setStarterPetHitConfirmed(player, false)
	end

	if player:GetAttribute(TutorialConfig.StageAttributeName) == nil
		or existingStage == TutorialConfig.Stages.NotStarted
	then
		setStage(player, TutorialConfig.Stages.LearnMove)
	elseif existingStage == TutorialConfig.Stages.LearnAttack then
		-- Active encounter state is runtime-only. Re-enter through the travel stage
		-- so a service/script restart cannot strand the Player without a wave.
		state.AttackLessonCompleted = false
		setProgress(player, 0, 0)
		setStage(player, TutorialConfig.Stages.GoToZone)
	elseif existingStage == TutorialConfig.Stages.InCombat then
		state.AttackLessonCompleted = true
		setProgress(player, 0, 0)
		setStage(player, TutorialConfig.Stages.GoToZone)
	elseif existingStage == TutorialConfig.Stages.LearnPetCombat then
		setStarterPetHitConfirmed(player, false)
		setProgress(player, 0, 0)
		setStage(player, TutorialConfig.Stages.PetCombatReady)
	elseif existingStage == TutorialConfig.Stages.PetInCombat then
		setStarterPetHitConfirmed(player, true)
		setProgress(player, 0, 0)
		setStage(player, TutorialConfig.Stages.PetCombatReady)
	else
		setStage(player, existingStage)
	end
	reconcileStarterPetEquip(player)
end

local function modeForActiveStage(stage)
	if stage == TutorialConfig.Stages.LearnAttack or stage == TutorialConfig.Stages.InCombat then
		return WAVE_MODES.Player
	end
	if stage == TutorialConfig.Stages.LearnPetCombat or stage == TutorialConfig.Stages.PetInCombat then
		return WAVE_MODES.Pet
	end
	return nil
end

local function activeParticipants(mode)
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local playerMode = modeForActiveStage(stageOf(player))
		if playerMode and (mode == nil or playerMode == mode) then
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
	waveMode = nil
	wavePlannedCount = 0
	waveStartInProgress = false
	activeWaveGeneration = nil
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

local function preparePetCombatRetry(player, previousStage)
	if previousStage == TutorialConfig.Stages.PetInCombat then
		setStarterPetHitConfirmed(player, true)
	elseif previousStage == TutorialConfig.Stages.LearnPetCombat then
		setStarterPetHitConfirmed(player, false)
	end
	setProgress(player, 0, 0)
	setStage(player, TutorialConfig.Stages.PetCombatReady)
end

local function resetActiveCombatForRecovery()
	local recovered = false
	local recoveringMode = waveMode
	for _, player in ipairs(Players:GetPlayers()) do
		local stage = stageOf(player)
		local playerMode = modeForActiveStage(stage)
		if playerMode == recoveringMode then
			if playerMode == WAVE_MODES.Pet then
				preparePetCombatRetry(player, stage)
			else
				prepareCombatRetry(player, stage)
			end
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
	local completingMode = waveMode
	waveActive = false
	waveMode = nil
	wavePlannedCount = 0
	waveExpanded = false
	waveExpansionStarted = false
	waveStartInProgress = false
	activeWaveGeneration = nil
	for _, player in ipairs(Players:GetPlayers()) do
		local stage = stageOf(player)
		if completingMode == WAVE_MODES.Player
			and (stage == TutorialConfig.Stages.LearnAttack or stage == TutorialConfig.Stages.InCombat)
		then
			onboardingState(player).AttackLessonCompleted = true
			setProgress(player, waveGoal, waveGoal)
			setStage(player, TutorialConfig.Stages.ReturnToAlex)
		elseif completingMode == WAVE_MODES.Pet then
			if stage == TutorialConfig.Stages.PetInCombat then
				setProgress(player, waveGoal, waveGoal)
				setStage(player, TutorialConfig.Stages.Completed)
			elseif stage == TutorialConfig.Stages.LearnPetCombat then
				-- Shared tutorial encounters must never let another Player's Pet satisfy
				-- this Player's exact starter-Pet hit requirement. Retry only the
				-- participants who never produced their own confirmed starter hit.
				preparePetCombatRetry(player, stage)
			end
		end
	end
end

local function updateCombatProgress()
	for _, player in ipairs(Players:GetPlayers()) do
		local stage = stageOf(player)
		if waveMode == WAVE_MODES.Player
			and (stage == TutorialConfig.Stages.LearnAttack or stage == TutorialConfig.Stages.InCombat)
		then
			setProgress(player, waveDefeated, waveGoal)
		elseif waveMode == WAVE_MODES.Pet and stage == TutorialConfig.Stages.PetInCombat then
			setProgress(player, waveDefeated, waveGoal)
		end
	end
end

local function expandCombatWave()
	if not waveActive or waveExpanded or waveExpansionStarted then
		return
	end
	waveExpansionStarted = true
	local remaining = math.max(0, wavePlannedCount - waveSpawned)
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

local function isCurrentWaveModel(model)
	local record = watchedSlimes[model]
	return waveActive
		and activeWaveGeneration ~= nil
		and record ~= nil
		and record.WaveGeneration == activeWaveGeneration
		and model:GetAttribute("TutorialEncounter") == true
end

local function onConfirmedPlayerHit(model)
	if waveMode ~= WAVE_MODES.Player or not isCurrentWaveModel(model) then
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

local function onConfirmedPetHit(model)
	if waveMode ~= WAVE_MODES.Pet or not isCurrentWaveModel(model) then
		return
	end
	if tostring(model:GetAttribute("LastHitSourceType") or "") ~= "Pet" then
		return
	end

	local userId = tonumber(model:GetAttribute("LastHitUserId")) or 0
	local player = userId > 0 and Players:GetPlayerByUserId(userId) or nil
	if not player or stageOf(player) ~= TutorialConfig.Stages.LearnPetCombat then
		return
	end

	local starterUid = tostring(player:GetAttribute(TutorialConfig.StarterPetUidAttributeName) or "")
	local sourceUid = tostring(model:GetAttribute("LastHitSourceUid") or "")
	if starterUid == ""
		or sourceUid ~= starterUid
		or player:GetAttribute(TutorialConfig.StarterPetGrantedAttributeName) ~= true
	then
		return
	end

	-- HitSerial is published only after authoritative SlimeHealth damage metadata is
	-- committed, so this transition cannot be satisfied by a client-only attack cue.
	setStarterPetHitConfirmed(player, true)
	setStage(player, TutorialConfig.Stages.PetInCombat)
	setProgress(player, waveDefeated, waveGoal)
	expandCombatWave()
end

local function onSlimeDefeated(model)
	if not isCurrentWaveModel(model) or model:GetAttribute("TutorialDefeatCounted") == true then
		return
	end

	if waveMode == WAVE_MODES.Pet and not waveExpanded then
		-- The first Pet lesson Slime can still be damaged by the Player. If it dies
		-- before this Player's exact starter UID lands a valid Pet hit, restart the
		-- lesson instead of leaving a zero-target softlock.
		for _, player in ipairs(Players:GetPlayers()) do
			if stageOf(player) == TutorialConfig.Stages.LearnPetCombat then
				preparePetCombatRetry(player, TutorialConfig.Stages.LearnPetCombat)
			end
		end
		clearWaveState(true)
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
	if record.PetHit then
		record.PetHit:Disconnect()
	end
	if record.TutorialEncounter then
		record.TutorialEncounter:Disconnect()
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
	local record = {
		WaveGeneration = model:GetAttribute("TutorialEncounter") == true and activeWaveGeneration or nil,
	}
	watchedSlimes[model] = record

	record.TutorialEncounter = model:GetAttributeChangedSignal("TutorialEncounter"):Connect(function()
		if model:GetAttribute("TutorialEncounter") == true
			and record.WaveGeneration == nil
			and activeWaveGeneration ~= nil
		then
			record.WaveGeneration = activeWaveGeneration
		end
	end)
	record.PlayerHit = model:GetAttributeChangedSignal("PlayerHitSerial"):Connect(function()
		onConfirmedPlayerHit(model)
	end)
	record.PetHit = model:GetAttributeChangedSignal("HitSerial"):Connect(function()
		onConfirmedPetHit(model)
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

local function beginWave(initialCount, plannedCount, mode)
	if waveActive then
		if waveMode == mode then
			return true
		end
		return false, "Another tutorial combat lesson is active."
	end
	if waveStartInProgress then
		return false, "Tutorial encounter start is already in progress."
	end

	local planned = math.max(1, math.floor(tonumber(plannedCount) or 1))
	local requestedInitial = math.clamp(math.floor(tonumber(initialCount) or 1), 1, planned)
	waveStartInProgress = true
	waveGenerationCounter += 1
	activeWaveGeneration = waveGenerationCounter

	local ok, spawnedOrReason = slimeMovementService.BeginTutorialEncounter(requestedInitial, planned)
	if not ok then
		waveStartInProgress = false
		activeWaveGeneration = nil
		return false, spawnedOrReason
	end
	waveActive = true
	waveMode = mode
	wavePlannedCount = planned
	waveSpawned = math.max(1, tonumber(spawnedOrReason) or 0)
	waveDefeated = 0
	waveExpanded = requestedInitial >= planned
	waveGoal = waveExpanded and waveSpawned or planned
	waveExpansionStarted = false
	waveStartInProgress = false
	updateCombatProgress()
	return true
end

local function updateCombatPresence(dt)
	local resetAny = false
	for _, player in ipairs(Players:GetPlayers()) do
		local stage = stageOf(player)
		local playerMode = modeForActiveStage(stage)
		if not playerMode or (waveMode and playerMode ~= waveMode) then
			continue
		end

		local state = onboardingState(player)
		if playerMode == WAVE_MODES.Pet and not starterPetIsEquipped(player) then
			-- A tiny mutation race can exist before the combat roster guard observes the
			-- encounter. Never leave the Player inside an automatic-Pet lesson without
			-- the exact starter Pet that the lesson is teaching.
			setStarterPetHitConfirmed(player, false)
			setProgress(player, 0, 0)
			setStage(player, TutorialConfig.Stages.EquipStarterPet)
			resetAny = true
			continue
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")

		local function retry()
			if playerMode == WAVE_MODES.Pet then
				preparePetCombatRetry(player, stage)
			else
				prepareCombatRetry(player, stage)
			end
			resetAny = true
		end

		if humanoid and humanoid.Health <= 0 then
			retry()
			continue
		end

		if not root or not root:IsA("BasePart") then
			state.MissingCharacterSeconds += dt
			if state.MissingCharacterSeconds >= TutorialConfig.CombatMissingCharacterGraceSeconds then
				retry()
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
				retry()
			end
		end
	end

	if resetAny and waveActive and activeParticipants(waveMode) <= 0 then
		clearWaveState(true)
	end
end

local function reconcileWaveIntegrity()
	if not slimeMovementService.GetTutorialEncounterSnapshot then
		return
	end
	local snapshot = slimeMovementService.GetTutorialEncounterSnapshot()
	if type(snapshot) ~= "table" then
		return
	end

	if not waveActive then
		if snapshot.Active == true then
			-- Local tutorial state can be rebuilt after a script/service restart, but a
			-- leftover runtime encounter cannot safely be adopted because its stage/gate
			-- ownership is unknown. Clear it once, then let travel stages start cleanly.
			slimeMovementService.CancelTutorialEncounter()
			if RunService:IsStudio() then
				print("[Pawlands Tutorial] Cleared orphaned tutorial encounter runtime.")
			end
		end
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
		local stage = stageOf(player)
		local root = getAliveRoot(player)
		if not root or not slimeMovementService.ContainsPosition(root.Position) then
			continue
		end

		if stage == TutorialConfig.Stages.GoToZone
			and (not waveActive or waveMode == WAVE_MODES.Player)
		then
			local state = onboardingState(player)
			local attackLessonCompleted = state.AttackLessonCompleted == true
			local initialCount = attackLessonCompleted
				and TutorialConfig.SoloCombatSlimeCount
				or TutorialConfig.AttackLessonInitialSlimeCount
			local ok = beginWave(initialCount, TutorialConfig.SoloCombatSlimeCount, WAVE_MODES.Player)
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
		elseif stage == TutorialConfig.Stages.PetCombatReady
			and (not waveActive or waveMode == WAVE_MODES.Pet)
		then
			if not starterPetIsEquipped(player) then
				setStarterPetHitConfirmed(player, false)
				setProgress(player, 0, 0)
				setStage(player, TutorialConfig.Stages.EquipStarterPet)
				continue
			end
			local hitCheckpoint = starterPetHitConfirmed(player)
			local initialCount = hitCheckpoint
				and TutorialConfig.PetCombatSlimeCount
				or TutorialConfig.PetCombatInitialSlimeCount
			local ok = beginWave(initialCount, TutorialConfig.PetCombatSlimeCount, WAVE_MODES.Pet)
			if ok then
				if hitCheckpoint then
					setStage(player, TutorialConfig.Stages.PetInCombat)
					if not waveExpanded then
						expandCombatWave()
					end
					setProgress(player, waveDefeated, waveGoal)
				else
					setStage(player, TutorialConfig.Stages.LearnPetCombat)
					-- The visible 0/N kill counter starts only after this Player's exact
					-- starter UID lands a valid server-confirmed Pet hit.
					setProgress(player, 0, 0)
				end
			end
		end
	end

	if waveActive and activeParticipants(waveMode) <= 0 then
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

function TutorialService.CompleteStarterPetEquip(player, uid)
	if not started or not player or player.Parent ~= Players then
		return false
	end
	if stageOf(player) ~= TutorialConfig.Stages.EquipStarterPet then
		return false
	end
	local starterUid = player:GetAttribute(TutorialConfig.StarterPetUidAttributeName)
	if type(uid) ~= "string" or uid == "" or uid ~= starterUid then
		return false
	end
	return reconcileStarterPetEquip(player)
end

function TutorialService.Start(slimeService, partyService)
	if started then
		return
	end
	if not slimeService or not partyService then
		error("TutorialService requires SlimeMovementService and PetPartyService.")
	end
	started = true
	slimeMovementService = slimeService
	petPartyService = partyService
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
			if started and waveActive and activeParticipants(waveMode) <= 0 then
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
			reconcileStarterPetEquip(player)
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
	waveGenerationCounter = 0
	activeWaveGeneration = nil
	waveStartInProgress = false
	inputRemote = nil
	slimeMovementService = nil
	petPartyService = nil
end

return TutorialService
