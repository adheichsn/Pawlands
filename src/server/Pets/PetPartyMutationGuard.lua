local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local InventoryConfig = require(Shared.Config.Inventory)
local SlimeMovementConfig = require(Shared.Config.SlimeMovement)

local PetPartyMutationGuard = {}
local started = false
local heartbeatConnection = nil
local addedConnection = nil
local removingConnection = nil
local lastCombatAt = {}
local publishedLocked = {}
local accumulator = 0

local COMBAT_STATES = table.freeze({
	Notice = true,
	Chase = true,
	Engage = true,
	Attack = true,
})

local function validPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function runtimeFolder()
	local folder = Workspace:FindFirstChild(SlimeMovementConfig.RuntimeFolderName)
	return folder and folder:IsA("Folder") and folder or nil
end

local function isLiveCombatSlime(model, player)
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

local function hasActiveCombat(player)
	local folder = runtimeFolder()
	if not folder then
		return false
	end
	for _, model in ipairs(folder:GetChildren()) do
		if isLiveCombatSlime(model, player) then
			return true
		end
	end
	return false
end

local function computeLocked(player, now)
	if hasActiveCombat(player) then
		lastCombatAt[player] = now
		return true
	end
	local last = lastCombatAt[player]
	if not last then
		return false
	end
	return now - last < math.max(0, tonumber(InventoryConfig.PartyMutationExitGraceSeconds) or 0)
end

local function publish(player, locked)
	locked = locked == true
	if publishedLocked[player] == locked
		and player:GetAttribute(InventoryConfig.PartyMutationLockedAttributeName) == locked
	then
		return
	end
	publishedLocked[player] = locked
	player:SetAttribute(InventoryConfig.PartyMutationLockedAttributeName, locked)
end

local function updatePlayer(player, now)
	if not validPlayer(player) then
		return false
	end
	local locked = computeLocked(player, now)
	publish(player, locked)
	return locked
end

function PetPartyMutationGuard.IsLocked(player)
	if not started or not validPlayer(player) then
		return false
	end
	return updatePlayer(player, os.clock())
end

function PetPartyMutationGuard.Start()
	if started then
		return
	end
	started = true
	local function added(player)
		lastCombatAt[player] = nil
		publishedLocked[player] = nil
		publish(player, false)
	end
	addedConnection = Players.PlayerAdded:Connect(added)
	removingConnection = Players.PlayerRemoving:Connect(function(player)
		lastCombatAt[player] = nil
		publishedLocked[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		added(player)
	end

	local interval = math.max(0.05, tonumber(InventoryConfig.PartyMutationPollIntervalSeconds) or 0.1)
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += math.min(dt, 0.25)
		if accumulator < interval then
			return
		end
		accumulator = accumulator % interval
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			updatePlayer(player, now)
		end
	end)
end

function PetPartyMutationGuard.Stop()
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
		if player:GetAttribute(InventoryConfig.PartyMutationLockedAttributeName) ~= nil then
			player:SetAttribute(InventoryConfig.PartyMutationLockedAttributeName, false)
		end
	end
	table.clear(lastCombatAt)
	table.clear(publishedLocked)
	accumulator = 0
end

return PetPartyMutationGuard
