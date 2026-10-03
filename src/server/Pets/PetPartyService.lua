local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetParty)
local Catalog = require(Shared.Config.PetCatalog)
local Rules = require(Shared.Pets.PartyRules)
local Codec = require(Shared.Pets.PartyCodec)
local Assets = require(Shared.Pets.PetAssets)

local PetPartyService = {}
local parties = {}
local inventoryService
local profileService
local started = false

local function validPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function publish(player, party)
	local visualParty = {}
	for _, uid in ipairs(party) do
		local pet = inventoryService.GetPet(player, uid)
		if pet then
			table.insert(visualParty, pet.PetId)
		end
	end
	player:SetAttribute(Config.AttributeName, Codec.encode(visualParty))
end

function PetPartyService.GetParty(player)
	return table.clone(parties[player] or {})
end

function PetPartyService.GetDisplayParty(player)
	local result = {}
	for _, uid in ipairs(parties[player] or {}) do
		local pet = inventoryService and inventoryService.GetPet(player, uid)
		if pet then
			table.insert(result, pet.PetId)
		end
	end
	return result
end

function PetPartyService.IsEquipped(player, uid)
	for _, equippedUid in ipairs(parties[player] or {}) do
		if equippedUid == uid then
			return true
		end
	end
	return false
end

-- Trusted server API. requested contains owned pet instance ids, not species/model names.
function PetPartyService.SetParty(player, requested)
	if not validPlayer(player) then
		return false, "Player is not in this server."
	end
	if not inventoryService then
		return false, "Pet inventory service is unavailable."
	end
	local party, reason = Rules.validateOwned(requested, function(uid)
		return inventoryService.GetPet(player, uid)
	end, Catalog, Config.MaxSize)
	if not party then
		return false, reason
	end
	for _, uid in ipairs(party) do
		local pet = inventoryService.GetPet(player, uid)
		local model, assetReason = Assets.find(Catalog.Pets[pet.PetId], Config.AssetPath)
		if not model then
			return false, assetReason
		end
	end
	local persisted, persistReason = profileService.SetParty(player, party)
	if not persisted then
		return false, persistReason
	end
	parties[player] = party
	publish(player, party)
	return true, nil
end

function PetPartyService.Equip(player, uid)
	if not validPlayer(player) then
		return false, "Player is not in this server."
	end
	if not inventoryService or not inventoryService.Owns(player, uid) then
		return false, "Pet is not owned: " .. tostring(uid)
	end
	if PetPartyService.IsEquipped(player, uid) then
		return true, nil
	end
	local requested = PetPartyService.GetParty(player)
	table.insert(requested, uid)
	return PetPartyService.SetParty(player, requested)
end

function PetPartyService.Unequip(player, uid)
	if not validPlayer(player) then
		return false, "Player is not in this server."
	end
	if not inventoryService or not inventoryService.Owns(player, uid) then
		return false, "Pet is not owned: " .. tostring(uid)
	end
	local requested = PetPartyService.GetParty(player)
	for index, equippedUid in ipairs(requested) do
		if equippedUid == uid then
			table.remove(requested, index)
			return PetPartyService.SetParty(player, requested)
		end
	end
	return false, "Pet is not equipped: " .. tostring(uid)
end

function PetPartyService.Start(petInventoryService, playerProfileService)
	if started then
		return
	end
	inventoryService = petInventoryService
	profileService = playerProfileService
	if not inventoryService or not profileService then
		error("PetPartyService requires PetInventoryService and PlayerProfileService.")
	end
	started = true
	local function added(player)
		local profile = profileService.AwaitReady(player)
		if not profile or player.Parent ~= Players then
			return
		end
		local savedParty = profileService.GetPartySnapshot(player)
		local ok, reason = PetPartyService.SetParty(player, savedParty)
		if not ok then
			warn("[Pawlands Party] Persisted party could not be restored for " .. player.Name .. ": " .. tostring(reason))
			parties[player] = {}
			profileService.SetParty(player, {})
			publish(player, {})
		end
	end
	Players.PlayerAdded:Connect(added)
	Players.PlayerRemoving:Connect(function(player)
		parties[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		added(player)
	end
end

return PetPartyService
