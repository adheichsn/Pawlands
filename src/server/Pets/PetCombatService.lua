local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetCombat)
local SlimeMovementConfig = require(Shared.Config.SlimeMovement)
local Codec = require(Shared.Pets.PetCombatCodec)

local PetCombatService = {}
local started = false
local heartbeatConnection
local addedConnection
local removingConnection
local partyService
local vitalsService
local stateByPlayer = {}
local accumulator = 0

local COMBAT_STATES = table.freeze({
	Notice = true,
	Chase = true,
	Engage = true,
	Attack = true,
})

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
	if tonumber(model:GetAttribute("TargetUserId")) ~= player.UserId then
		return false
	end
	return COMBAT_STATES[tostring(model:GetAttribute("SlimeState"))] == true
end

local function collectTargets(player, root)
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
				if distance <= Config.HardLeashStuds then
					table.insert(targets, {
						Model = model,
						Slot = math.floor(slimeSlot),
						Distance = distance,
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

local function stepPlayer(player)
	local root = getRoot(player)
	local party = partyService.GetParty(player)
	if not root or #party == 0 then
		clearPlayer(player)
		return
	end

	local state = stateByPlayer[player]
	if not state then
		state = { Assignments = {}, Published = nil }
		stateByPlayer[player] = state
	end

	local targets = collectTargets(player, root)
	local byModel = {}
	for _, target in ipairs(targets) do
		byModel[target.Model] = target
	end

	local nextAssignments = {}
	local counts = {}
	for petSlot = 1, #party do
		local uid = party[petSlot]
		local canCombat = not vitalsService or vitalsService.CanCombat(player, uid)
		local targetModel = canCombat and state.Assignments[petSlot] or nil
		local target = targetModel and byModel[targetModel]
		if target and target.Distance <= Config.HardLeashStuds then
			local count = counts[target.Model] or 0
			if count < Config.MaxAttackersPerNormalSlime then
				nextAssignments[petSlot] = target.Model
				counts[target.Model] = count + 1
			end
		end
	end

	local function chooseTarget()
		local best
		for _, target in ipairs(targets) do
			if target.Distance <= Config.SoftLeashStuds then
				local count = counts[target.Model] or 0
				if count < Config.MaxAttackersPerNormalSlime then
					local bestCount = best and (counts[best.Model] or 0) or math.huge
					if not best
						or count < bestCount
						or (count == bestCount and target.Distance < best.Distance)
						or (count == bestCount and math.abs(target.Distance - best.Distance) <= 0.01 and target.Slot < best.Slot)
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
		if canCombat and not nextAssignments[petSlot] then
			local target = chooseTarget()
			if not target then
				break
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
	local serializable = {}
	for petSlot, model in pairs(nextAssignments) do
		serializable[petSlot] = tonumber(model:GetAttribute("SlimeSlot"))
	end
	state.Published = publish(player, serializable, state.Published)
end

local function initializePlayer(player)
	player:SetAttribute(Config.AssignmentAttributeName, "")
end

function PetCombatService.Start(petPartyService, petVitalsService)
	if started then
		return
	end
	partyService = petPartyService
	vitalsService = petVitalsService
	if not partyService or not vitalsService then
		error("PetCombatService requires PetPartyService and PetVitalsService.")
	end
	started = true
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
			stepPlayer(player)
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
	accumulator = 0
end

return PetCombatService
