local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local InventoryConfig = require(Shared.Config.Inventory)
local TutorialConfig = require(Shared.Config.Tutorial)

local PetInventoryRemoteService = {}
local started = false
local remote = nil
local playerRemovingConnection = nil
local requestInFlight = {}
local inventoryService = nil
local partyService = nil
local tutorialService = nil
local partyMutationGuard = nil

local function ensureRemote()
	local pawlands = ReplicatedStorage:WaitForChild("Pawlands")
	local folder = pawlands:FindFirstChild(InventoryConfig.RemoteFolderName)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = InventoryConfig.RemoteFolderName
		folder.Parent = pawlands
	end

	local functionRemote = folder:FindFirstChild(InventoryConfig.RemoteFunctionName)
	if functionRemote and not functionRemote:IsA("RemoteFunction") then
		functionRemote:Destroy()
		functionRemote = nil
	end
	if not functionRemote then
		functionRemote = Instance.new("RemoteFunction")
		functionRemote.Name = InventoryConfig.RemoteFunctionName
		functionRemote.Parent = folder
	end
	return functionRemote
end

local function validPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function cleanPet(pet)
	return {
		Uid = pet.Uid,
		PetId = pet.PetId,
		SpeciesId = pet.SpeciesId,
		Variant = pet.Variant,
		Favorite = pet.Favorite == true,
	}
end

local function snapshot(player, success, reason)
	local pets = {}
	for _, pet in ipairs(inventoryService.GetInventory(player)) do
		table.insert(pets, cleanPet(pet))
	end
	local mutationLocked = partyMutationGuard and partyMutationGuard.IsLocked(player) or false
	return {
		Success = success ~= false,
		Reason = reason or "",
		Pets = pets,
		Party = partyService.GetParty(player),
		PartyMutationLocked = mutationLocked,
	}
end

local function tryCompleteStarterEquip(player)
	if player:GetAttribute(TutorialConfig.StageAttributeName) ~= TutorialConfig.Stages.EquipStarterPet then
		return
	end
	local starterUid = player:GetAttribute(TutorialConfig.StarterPetUidAttributeName)
	if type(starterUid) ~= "string" or starterUid == "" then
		return
	end
	if partyService.IsEquipped(player, starterUid) then
		tutorialService.CompleteStarterPetEquip(player, starterUid)
	end
end

local function validUid(uid)
	return type(uid) == "string" and uid ~= "" and #uid <= 64
end

local function handleRequest(player, action, uid)
	if not started or not validPlayer(player) or type(action) ~= "string" then
		return nil
	end

	if action == InventoryConfig.Actions.Snapshot then
		tryCompleteStarterEquip(player)
		return snapshot(player, true)
	end

	if not validUid(uid) then
		return snapshot(player, false, "Invalid Pet id.")
	end
	if requestInFlight[player] then
		return snapshot(player, false, "Another Inventory action is already being processed.")
	end
	if action == InventoryConfig.Actions.ToggleEquip
		and partyMutationGuard
		and partyMutationGuard.IsLocked(player)
	then
		return snapshot(player, false, InventoryConfig.PartyMutationLockedReason)
	end
	requestInFlight[player] = true

	local success, reason
	if action == InventoryConfig.Actions.ToggleEquip then
		if partyService.IsEquipped(player, uid) then
			success, reason = partyService.Unequip(player, uid)
		else
			success, reason = partyService.Equip(player, uid)
		end
		if success then
			tryCompleteStarterEquip(player)
		end
	elseif action == InventoryConfig.Actions.ToggleFavorite then
		local pet
		pet, reason = inventoryService.ToggleFavorite(player, uid)
		success = pet ~= nil
	else
		success = false
		reason = "Unknown Inventory action."
	end

	requestInFlight[player] = nil
	return snapshot(player, success, reason)
end

function PetInventoryRemoteService.Start(petInventoryService, petPartyService, tutorialProgressionService, petPartyMutationGuard)
	if started then
		return
	end
	if not petInventoryService or not petPartyService or not tutorialProgressionService or not petPartyMutationGuard then
		error("PetInventoryRemoteService requires PetInventoryService, PetPartyService, TutorialService, and PetPartyMutationGuard.")
	end
	started = true
	inventoryService = petInventoryService
	partyService = petPartyService
	tutorialService = tutorialProgressionService
	partyMutationGuard = petPartyMutationGuard
	remote = ensureRemote()
	remote.OnServerInvoke = handleRequest
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		requestInFlight[player] = nil
	end)
end

function PetInventoryRemoteService.Stop()
	if not started then
		return
	end
	started = false
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	if remote then
		remote.OnServerInvoke = nil
	end
	table.clear(requestInFlight)
	remote = nil
	inventoryService = nil
	partyService = nil
	tutorialService = nil
	partyMutationGuard = nil
end

return PetInventoryRemoteService
