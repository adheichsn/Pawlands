local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local PartyPowerConfig = require(Shared.Config.PartyPower)
local PetCatalog = require(Shared.Config.PetCatalog)
local PetCombatConfig = require(Shared.Config.PetCombat)
local PetPartyConfig = require(Shared.Config.PetParty)
local PetProgressionConfig = require(Shared.Config.PetProgression)
local PartyPowerMath = require(Shared.Progression.PartyPowerMath)

local PartyPowerService = {}
local started = false
local partyService = nil
local inventoryService = nil
local connections = {}
local warnedLeaderstats = {}
local playerAddedConnection = nil
local playerRemovingConnection = nil

local function disconnectPlayer(player)
	local list = connections[player]
	if list then
		for _, connection in ipairs(list) do
			connection:Disconnect()
		end
		connections[player] = nil
	end
	warnedLeaderstats[player] = nil
end

local function ensurePowerValue(player)
	local folder = player:FindFirstChild(PartyPowerConfig.LeaderstatsFolderName)
	if folder and not folder:IsA("Folder") then
		if not warnedLeaderstats[player] then
			warn(string.format(
				"[Pawlands Power] %s already has a non-Folder '%s'; publishing attribute only.",
				player.Name,
				PartyPowerConfig.LeaderstatsFolderName
			))
			warnedLeaderstats[player] = true
		end
		return nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PartyPowerConfig.LeaderstatsFolderName
		folder.Parent = player
	end

	local value = folder:FindFirstChild(PartyPowerConfig.LeaderstatName)
	if value and not value:IsA("IntValue") then
		if not warnedLeaderstats[player] then
			warn(string.format(
				"[Pawlands Power] %s already has a non-IntValue '%s'; publishing attribute only.",
				player.Name,
				PartyPowerConfig.LeaderstatName
			))
			warnedLeaderstats[player] = true
		end
		return nil
	end
	if not value then
		value = Instance.new("IntValue")
		value.Name = PartyPowerConfig.LeaderstatName
		value.Value = 0
		value.Parent = folder
	end
	return value
end

local function petPower(pet)
	if type(pet) ~= "table" then
		return 0
	end
	local definition = PetCatalog.Pets[pet.PetId]
	if not definition then
		return 0
	end
	return PartyPowerMath.GetPetPower(
		definition,
		pet.Level,
		PetProgressionConfig,
		PetCombatConfig.AttackCadenceSeconds,
		PartyPowerConfig
	)
end

function PartyPowerService.GetPower(player)
	if not started or not partyService or not inventoryService then
		return 0
	end
	local total = 0
	for _, uid in ipairs(partyService.GetParty(player)) do
		total += petPower(inventoryService.GetPet(player, uid))
	end
	return math.max(0, math.floor(total + 0.5))
end

function PartyPowerService.Refresh(player)
	if not started or typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return 0
	end
	local power = PartyPowerService.GetPower(player)
	player:SetAttribute(PartyPowerConfig.AttributeName, power)
	local value = ensurePowerValue(player)
	if value then
		value.Value = power
	end
	return power
end

local function bindPlayer(player)
	disconnectPlayer(player)
	ensurePowerValue(player)
	connections[player] = {
		player:GetAttributeChangedSignal(PetPartyConfig.AttributeName):Connect(function()
			PartyPowerService.Refresh(player)
		end),
		player:GetAttributeChangedSignal(PetProgressionConfig.RevisionAttributeName):Connect(function()
			PartyPowerService.Refresh(player)
		end),
	}
	task.defer(PartyPowerService.Refresh, player)
end

function PartyPowerService.Start(petPartyService, petInventoryService)
	if started then
		return
	end
	if not petPartyService or not petInventoryService then
		error("PartyPowerService requires PetPartyService and PetInventoryService.")
	end
	partyService = petPartyService
	inventoryService = petInventoryService
	started = true

	playerAddedConnection = Players.PlayerAdded:Connect(bindPlayer)
	playerRemovingConnection = Players.PlayerRemoving:Connect(disconnectPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
end

function PartyPowerService.Stop()
	if not started then
		return
	end
	started = false
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	while next(connections) do
		local player = next(connections)
		disconnectPlayer(player)
	end
	partyService = nil
	inventoryService = nil
end

return PartyPowerService
