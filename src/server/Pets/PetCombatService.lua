local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Pawlands = ReplicatedStorage:WaitForChild("Pawlands")
local Shared = Pawlands:WaitForChild("Shared")
local Catalog = require(Shared.Config.PetCatalog)
local Config = require(Shared.Config.PetCombat)
local WorldConfig = require(Shared.Config.WorldPetCombat)
local SlimeMovementConfig = require(Shared.Config.SlimeMovement)
local Codec = require(Shared.Pets.PetCombatCodec)
local CombatFormation = require(Shared.Pets.PetCombatFormation)
local SlimeHealth = require(script.Parent.Parent.Slimes.SlimeHealth)
local PetStrikeAuthority = require(script.Parent.PetStrikeAuthority)

local PetCombatService = {}
local started = false
local heartbeatConnection
local impactConnection
local addedConnection
local removingConnection
local partyService
local vitalsService
local inventoryService
local stateByPlayer = {}
local accumulator = 0
local warnedMissingDamage = {}

local COMBAT_STATES = table.freeze({
	Notice = true,
	Chase = true,
	Engage = true,
	Attack = true,
})

local function isWorldTarget(model)
	return model and model:GetAttribute("WorldCombat") == true
end

local function acquisitionRange(model)
	if isWorldTarget(model) then
		return WorldConfig.CombatRadiusStuds
	end
	return Config.SoftLeashStuds
end

local function retentionRange(model)
	if isWorldTarget(model) then
		return WorldConfig.DisengageDistanceStuds
	end
	return Config.HardLeashStuds
end

local function recentPlayerAssist(model, player, now)
	if not isWorldTarget(model) then
		return false
	end
	if tonumber(model:GetAttribute("LastPlayerHitUserId")) ~= player.UserId
		or tostring(model:GetAttribute("LastPlayerHitActionType") or "") ~= "M1"
	then
		return false
	end
	local hitAt = tonumber(model:GetAttribute("LastPlayerHitAt")) or -math.huge
	return now - hitAt <= WorldConfig.PlayerAssistBiasSeconds
end

local function worldReturnMaxSpeed(distance)
	if distance >= WorldConfig.ReturnFarDistanceStuds then
		return WorldConfig.ReturnVeryFarMaxSpeedStuds
	elseif distance >= WorldConfig.ReturnMediumDistanceStuds then
		return WorldConfig.ReturnFarMaxSpeedStuds
	elseif distance >= WorldConfig.ReturnNearDistanceStuds then
		return WorldConfig.ReturnMediumMaxSpeedStuds
	end
	return WorldConfig.ReturnNearMaxSpeedStuds
end

local function worldReturnLockDuration(distance, root)
	local ownerSpeed = 0
	if root then
		local velocity = root.AssemblyLinearVelocity
		ownerSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	end
	local relativeCatchUp = math.max(
		WorldConfig.ReturnMinimumRelativeCatchUpSpeedStuds,
		worldReturnMaxSpeed(distance) - ownerSpeed
	)
	local travel = math.max(0, distance - WorldConfig.ReturnRegroupBufferStuds) / relativeCatchUp
	return math.clamp(
		travel + WorldConfig.ReturnLockPaddingSeconds,
		WorldConfig.ReturnAcquireLockMinSeconds,
		WorldConfig.ReturnAcquireLockMaxSeconds
	)
end

local function beginWorldReturn(state, petSlot, uid, model, root, now)
	if not state
		or not isWorldTarget(model)
		or not model:IsDescendantOf(Workspace)
		or not SlimeHealth.IsAlive(model)
	then
		return
	end
	local distance = root and (model:GetPivot().Position - root.Position).Magnitude or WorldConfig.DisengageDistanceStuds
	local previous = state.WorldReturns[petSlot]
	local untilAt = now + worldReturnLockDuration(distance, root)
	if previous and previous.Uid == uid then
		untilAt = math.max(previous.UntilAt or 0, untilAt)
	end
	state.WorldReturns[petSlot] = {
		Uid = uid,
		UntilAt = untilAt,
	}
end

local function isWorldReturnLocked(state, petSlot, uid, now)
	local returnState = state.WorldReturns[petSlot]
	if not returnState then
		return false
	end
	if returnState.Uid ~= uid or now >= (returnState.UntilAt or 0) then
		state.WorldReturns[petSlot] = nil
		return false
	end
	return true
end

local function ensureImpactRemote()
	local folder = Pawlands:FindFirstChild(Config.RemoteFolderName)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Config.RemoteFolderName
		folder.Parent = Pawlands
	end

	local remote = folder:FindFirstChild(Config.AttackImpactRemoteName)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = Config.AttackImpactRemoteName
		remote.Parent = folder
	end
	return remote
end

local function getRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function runtimeFolder()
	local folder = Workspace:FindFirstChild(SlimeMovementConfig.RuntimeFolderName)
	return folder and folder:IsA("Folder") and folder or nil
end

local function damageForPet(player, uid)
	local pet = inventoryService and inventoryService.GetPet(player, uid)
	local petId = pet and tostring(pet.PetId or "") or ""
	local definition = petId ~= "" and Catalog.Pets[petId] or nil
	local configured = definition and tonumber(definition.BaseDamage)
	if configured and configured > 0 then
		return math.max(1, math.floor(configured + 0.5))
	end

	local warningKey = petId ~= "" and petId or tostring(uid or "<unknown>")
	if not warnedMissingDamage[warningKey] then
		warn(string.format(
			"[Pawlands PetCombat] Missing valid BaseDamage for %s; using safety fallback.",
			warningKey
		))
		warnedMissingDamage[warningKey] = true
	end
	return math.max(1, math.floor((tonumber(Config.FallbackDamage) or 1) + 0.5))
end

local function isActiveTarget(model, player)
	if not model or not model:IsA("Model") or not model:IsDescendantOf(Workspace) then
		return false
	end
	if model:GetAttribute("Defeated") == true then
		return false
	end
	if (tonumber(model:GetAttribute("Health")) or 0) <= 0 then
		return false
	end
	-- TargetUserId remains the owning player even when the slime's current focus
	-- is one of that player's pets. This keeps pet allocation stable and lets the
	-- slime/pet targeting layers share one encounter owner without circular state.
	if tonumber(model:GetAttribute("TargetUserId")) ~= player.UserId then
		return false
	end
	return COMBAT_STATES[tostring(model:GetAttribute("SlimeState"))] == true
end

local function collectTargets(player, root, assistNow)
	local folder = runtimeFolder()
	if not folder then
		return {}
	end
	local targets = {}
	for _, model in ipairs(folder:GetChildren()) do
		if isActiveTarget(model, player) then
			local slimeSlot = tonumber(model:GetAttribute("SlimeSlot"))
			if slimeSlot then
				local distance = (model:GetPivot().Position - root.Position).Magnitude
				if distance <= retentionRange(model) then
					table.insert(targets, {
						Model = model,
						Slot = math.floor(slimeSlot),
						Distance = distance,
						Assisted = recentPlayerAssist(model, player, assistNow),
					})
				end
			end
		end
	end
	table.sort(targets, function(a, b)
		if math.abs(a.Distance - b.Distance) > 0.01 then
			return a.Distance < b.Distance
		end
		return a.Slot < b.Slot
	end)
	return targets
end

local function clearPlayer(player)
	if vitalsService then
		vitalsService.ReleaseCombat(player)
	end
	stateByPlayer[player] = nil
	if player.Parent == Players then
		player:SetAttribute(Config.AssignmentAttributeName, "")
	end
end

local function publish(player, assignments, previous)
	local encoded = Codec.encode(assignments)
	if encoded ~= previous then
		player:SetAttribute(Config.AssignmentAttributeName, encoded)
	end
	return encoded
end

local function buildCombatTargets(player, party, assignments, state, root)
	local serializable = {}
	local targetPositions = {}
	for petSlot, model in pairs(assignments) do
		local slimeSlot = tonumber(model:GetAttribute("SlimeSlot"))
		if slimeSlot then
			slimeSlot = math.floor(slimeSlot)
			serializable[petSlot] = slimeSlot
			targetPositions[slimeSlot] = model:GetPivot().Position
		end
	end

	local combatCenter = CombatFormation.combatCenter(serializable, targetPositions)
	local activeAnchors = {}
	local rawGoals = {}
	local targetPositionsByPet = {}

	for petSlot, slimeSlot in pairs(serializable) do
		local model = assignments[petSlot]
		local slimePosition = targetPositions[slimeSlot]
		if model and slimePosition then
			local anchor = state.CombatAnchors[slimeSlot]
			if not anchor then
				anchor = {
					Direction = CombatFormation.outerDirection(slimePosition, root.Position, combatCenter),
				}
				state.CombatAnchors[slimeSlot] = anchor
			end
			activeAnchors[slimeSlot] = true
			local attackers = CombatFormation.attackersForTarget(serializable, slimeSlot)
			rawGoals[petSlot] = CombatFormation.goal(petSlot, attackers, slimePosition, anchor.Direction)
			targetPositionsByPet[petSlot] = slimePosition
		end
	end

	for slimeSlot in pairs(state.CombatAnchors) do
		if not activeAnchors[slimeSlot] then
			state.CombatAnchors[slimeSlot] = nil
		end
	end

	local goals = CombatFormation.resolveSpacing(rawGoals, targetPositionsByPet)
	local combatTargets = {}
	for petSlot, goal in pairs(goals) do
		local uid = party[petSlot]
		local model = assignments[petSlot]
		local slimeSlot = serializable[petSlot]
		if uid and model and slimeSlot then
			combatTargets[petSlot] = {
				Slot = petSlot,
				Uid = uid,
				SlimeSlot = slimeSlot,
				SlimeModel = model,
				Position = goal,
			}
		end
	end
	state.CombatTargets = combatTargets
	return serializable
end

local function horizontalDirection(fromPosition, toPosition)
	local direction = Vector3.new(
		toPosition.X - fromPosition.X,
		0,
		toPosition.Z - fromPosition.Z
	)
	if direction.Magnitude <= 0.001 then
		return Vector3.zero
	end
	return direction.Unit
end

local function processImpact(player, petSlot, slimeSlot)
	if not started or player.Parent ~= Players then
		return
	end
	if type(petSlot) ~= "number" or type(slimeSlot) ~= "number" then
		return
	end
	petSlot = math.floor(petSlot)
	slimeSlot = math.floor(slimeSlot)
	if petSlot < 1 or slimeSlot < 1 then
		return
	end

	local state = stateByPlayer[player]
	local entry = state and state.CombatTargets and state.CombatTargets[petSlot]
	local guard = state and state.AttackGuards and state.AttackGuards[petSlot]
	if not entry or not guard then
		return
	end
	if entry.SlimeSlot ~= slimeSlot
		or guard.SlimeSlot ~= slimeSlot
		or guard.SlimeModel ~= entry.SlimeModel
		or guard.Uid ~= entry.Uid
	then
		return
	end

	local root = getRoot(player)
	if not root or not isActiveTarget(entry.SlimeModel, player) then
		return
	end
	local slimePosition = entry.SlimeModel:GetPivot().Position
	if (slimePosition - root.Position).Magnitude
		> retentionRange(entry.SlimeModel) + Config.ServerImpactLeashPaddingStuds
	then
		return
	end
	if not vitalsService or not vitalsService.CanCombat(player, entry.Uid) then
		return
	end

	local clock = os.clock()
	local validImpact = PetStrikeAuthority.ValidateImpact(guard, entry, slimePosition, clock)
	if not validImpact then
		return
	end
	PetStrikeAuthority.CommitImpact(guard, slimePosition, clock)

	local damage = damageForPet(player, entry.Uid)
	local hitDirection = horizontalDirection(entry.Position, slimePosition)
	local applied, health = SlimeHealth.ApplyDamage(entry.SlimeModel, damage, player, {
		Tier = "Light",
		Direction = hitDirection,
		SourceType = "Pet",
		SourceUid = entry.Uid,
	})
	if applied and RunService:IsStudio() then
		print(string.format(
			"[Pawlands PetCombat] %s pet %s hit %s for %d damage (%d/%d HP).",
			player.Name,
			tostring(entry.Uid),
			tostring(entry.SlimeModel:GetAttribute("SlimeId") or entry.SlimeModel.Name),
			damage,
			health,
			entry.SlimeModel:GetAttribute("MaxHealth") or health
		))
	end
end

local function stepPlayer(player, dt)
	local root = getRoot(player)
	local party = partyService.GetParty(player)
	if not root or #party == 0 then
		clearPlayer(player)
		return
	end

	local state = stateByPlayer[player]
	if not state then
		state = {
			Assignments = {},
			Published = nil,
			CombatAnchors = {},
			CombatTargets = {},
			AttackGuards = {},
			WorldReturns = {},
		}
		stateByPlayer[player] = state
	end

	local clock = os.clock()
	local targets = collectTargets(player, root, time())
	local byModel = {}
	for _, target in ipairs(targets) do
		byModel[target.Model] = target
	end

	local activePetCount = 0
	for _, uid in ipairs(party) do
		if not vitalsService or vitalsService.CanCombat(player, uid) then
			activePetCount += 1
		end
	end

	-- Adaptive focus fire: spread healthy pets across available slimes first,
	-- then collapse remaining pets onto the same targets. With four healthy pets
	-- this naturally resolves as 1/1/1/1, 2/1/1, 2/2, then 4 on the last slime.
	local acquirableTargetCount = 0
	for _, target in ipairs(targets) do
		if target.Distance <= acquisitionRange(target.Model) then
			acquirableTargetCount += 1
		end
	end
	local attackerCapacity = 0
	if activePetCount > 0 and #targets > 0 then
		local distributionTargetCount = math.max(1, acquirableTargetCount)
		attackerCapacity = math.min(
			math.max(1, Config.MaxAttackersPerNormalSlime),
			math.max(1, math.ceil(activePetCount / distributionTargetCount))
		)
	end

	local nextAssignments = {}
	local counts = {}
	for petSlot = 1, #party do
		local uid = party[petSlot]
		local canCombat = not vitalsService or vitalsService.CanCombat(player, uid)
		local targetModel = canCombat and state.Assignments[petSlot] or nil
		local returning = isWorldReturnLocked(state, petSlot, uid, clock)
		local target = targetModel and byModel[targetModel]
		if not returning
			and target
			and target.Distance <= retentionRange(target.Model)
			and attackerCapacity > 0
		then
			local count = counts[target.Model] or 0
			if count < attackerCapacity then
				nextAssignments[petSlot] = target.Model
				counts[target.Model] = count + 1
			end
		elseif not returning and canCombat and targetModel and isWorldTarget(targetModel) then
			-- A living Stonewood target that leaves the owner's encounter causes an
			-- explicit regroup window. Defeated targets are exempt so normal grinding
			-- can immediately hand off to the next nearby Slime.
			beginWorldReturn(state, petSlot, uid, targetModel, root, clock)
		end
	end

	local function chooseTarget()
		local best
		for _, target in ipairs(targets) do
			if target.Distance <= acquisitionRange(target.Model) then
				local count = counts[target.Model] or 0
				if count < attackerCapacity then
					local bestCount = best and (counts[best.Model] or 0) or math.huge
					local assisted = target.Assisted == true
					local bestAssisted = best and best.Assisted == true or false
					if not best
						or count < bestCount
						or (count == bestCount and assisted and not bestAssisted)
						or (count == bestCount and assisted == bestAssisted and target.Distance < best.Distance)
						or (count == bestCount
						and assisted == bestAssisted
						and math.abs(target.Distance - best.Distance) <= 0.01
						and target.Slot < best.Slot)
					then
						best = target
					end
				end
			end
		end
		return best
	end

	for petSlot = 1, #party do
		local uid = party[petSlot]
		local canCombat = not vitalsService or vitalsService.CanCombat(player, uid)
		local returning = isWorldReturnLocked(state, petSlot, uid, clock)
		if canCombat and not returning and not nextAssignments[petSlot] then
			local target = chooseTarget()
			if not target then
				continue
			end
			nextAssignments[petSlot] = target.Model
			counts[target.Model] = (counts[target.Model] or 0) + 1
		end
	end

	if vitalsService then
		for petSlot, uid in ipairs(party) do
			vitalsService.SetCombatActive(player, uid, nextAssignments[petSlot] ~= nil)
		end
	end

	state.Assignments = nextAssignments
	local serializable = buildCombatTargets(player, party, nextAssignments, state, root)
	PetStrikeAuthority.Sync(
		state.AttackGuards,
		state.CombatTargets,
		root,
		#party,
		clock,
		dt or (1 / math.max(1, Config.UpdateRate))
	)
	state.Published = publish(player, serializable, state.Published)
end

local function initializePlayer(player)
	player:SetAttribute(Config.AssignmentAttributeName, "")
end

function PetCombatService.GetCombatTargets(player)
	local state = stateByPlayer[player]
	if not state then
		return {}
	end
	local result = {}
	for slot, entry in pairs(state.CombatTargets or {}) do
		result[slot] = {
			Slot = entry.Slot,
			Uid = entry.Uid,
			SlimeSlot = entry.SlimeSlot,
			SlimeModel = entry.SlimeModel,
			Position = entry.Position,
		}
	end
	return result
end

function PetCombatService.Start(petPartyService, petVitalsService, petInventoryService)
	if started then
		return
	end
	partyService = petPartyService
	vitalsService = petVitalsService
	inventoryService = petInventoryService
	if not partyService or not vitalsService or not inventoryService then
		error("PetCombatService requires PetPartyService, PetVitalsService, and PetInventoryService.")
	end
	started = true
	local impactRemote = ensureImpactRemote()
	impactConnection = impactRemote.OnServerEvent:Connect(processImpact)
	addedConnection = Players.PlayerAdded:Connect(initializePlayer)
	removingConnection = Players.PlayerRemoving:Connect(function(player)
		stateByPlayer[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		initializePlayer(player)
	end
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		local interval = 1 / math.max(1, Config.UpdateRate)
		if accumulator < interval then
			return
		end
		accumulator %= interval
		for _, player in ipairs(Players:GetPlayers()) do
			stepPlayer(player, interval)
		end
	end)
end

function PetCombatService.Stop()
	if not started then
		return
	end
	started = false
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if impactConnection then
		impactConnection:Disconnect()
		impactConnection = nil
	end
	if addedConnection then
		addedConnection:Disconnect()
		addedConnection = nil
	end
	if removingConnection then
		removingConnection:Disconnect()
		removingConnection = nil
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if vitalsService then
			vitalsService.ReleaseCombat(player)
		end
		player:SetAttribute(Config.AssignmentAttributeName, "")
	end
	table.clear(stateByPlayer)
	partyService = nil
	vitalsService = nil
	inventoryService = nil
	accumulator = 0
	table.clear(warnedMissingDamage)
end

return PetCombatService
