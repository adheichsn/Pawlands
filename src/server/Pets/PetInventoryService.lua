local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Catalog = require(Shared.Config.PetCatalog)
local InventoryConfig = require(Shared.Config.Inventory)
local Rules = require(Shared.Pets.PartyRules)

local PetInventoryService = {}
local inventories = {}
local profileService
local started = false

local function validPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function getState(player)
	local state = inventories[player]
	if state or not validPlayer(player) then
		return state
	end
	if not profileService then
		return nil
	end

	-- Hydrate lazily from the loaded canonical profile so dependent services do
	-- not rely on PlayerAdded callback ordering.
	local profile, reason = profileService.AwaitReady(player)
	if not profile then
		if player.Parent == Players then
			warn("[Pawlands Inventory] Profile unavailable for " .. player.Name .. ": " .. tostring(reason))
		end
		return nil
	end
	local saved = profileService.GetPetInventorySnapshot(player) or {}
	state = { Pets = {}, Order = {}, NextSequence = math.max(0, math.floor(tonumber(saved.NextSequence) or 0)) }
	local records = type(saved.Records) == "table" and saved.Records or {}
	for _, uid in ipairs(type(saved.Order) == "table" and saved.Order or {}) do
		local pet = records[uid]
		if type(uid) == "string" and type(pet) == "table" and Catalog.Pets[pet.PetId] then
			local copy = table.clone(pet)
			copy.Level = math.max(1, math.floor(tonumber(copy.Level) or 1))
			copy.Experience = math.max(0, math.floor((tonumber(copy.Experience) or 0) + 0.5))
			state.Pets[uid] = copy
			table.insert(state.Order, uid)
		end
	end
	inventories[player] = state
	return state
end

local function normalizeProgression(pet)
	if not pet then
		return nil
	end
	pet.Level = math.max(1, math.floor(tonumber(pet.Level) or 1))
	pet.Experience = math.max(0, math.floor((tonumber(pet.Experience) or 0) + 0.5))
	return pet
end

local function clonePet(pet)
	pet = normalizeProgression(pet)
	return pet and table.clone(pet) or nil
end

local function ownedPetCount(state)
	local count = 0
	for _, uid in ipairs(state.Order) do
		if state.Pets[uid] then
			count += 1
		end
	end
	return count
end

function PetInventoryService.GetPet(player, uid)
	local state = getState(player)
	return clonePet(state and state.Pets[uid])
end

function PetInventoryService.GetInventory(player)
	local state = getState(player)
	local result = {}
	if not state then
		return result
	end
	for _, uid in ipairs(state.Order) do
		local pet = state.Pets[uid]
		if pet then
			table.insert(result, clonePet(pet))
		end
	end
	return result
end

function PetInventoryService.Owns(player, uid)
	local state = getState(player)
	return state ~= nil and state.Pets[uid] ~= nil
end

function PetInventoryService.ToggleFavorite(player, uid)
	local state = getState(player)
	local pet = state and state.Pets[uid]
	if not pet then
		return nil, "Pet is not owned: " .. tostring(uid)
	end
	local nextFavorite = pet.Favorite ~= true
	local persisted, persistReason = profileService.SetPetFavorite(player, uid, nextFavorite)
	if not persisted then
		return nil, persistReason
	end
	pet.Favorite = nextFavorite
	return clonePet(pet), nil
end

-- Trusted server-only mutation point for progression services.
function PetInventoryService.SetProgressionState(player, uid, level, experience)
	local state = getState(player)
	local pet = state and state.Pets[uid]
	if not pet then
		return nil, "Pet is not owned: " .. tostring(uid)
	end
	local nextLevel = tonumber(level)
	local nextExperience = tonumber(experience)
	if not nextLevel or nextLevel ~= nextLevel or nextLevel == math.huge or nextLevel == -math.huge then
		return nil, "Pet level must be a finite number."
	end
	if not nextExperience
		or nextExperience ~= nextExperience
		or nextExperience == math.huge
		or nextExperience == -math.huge
		or nextExperience < 0
	then
		return nil, "Pet experience must be a finite non-negative number."
	end
	local normalizedLevel = math.max(1, math.floor(nextLevel))
	local normalizedExperience = math.max(0, math.floor(nextExperience + 0.5))
	local persisted, persistReason = profileService.SetPetProgression(player, uid, normalizedLevel, normalizedExperience)
	if not persisted then
		return nil, persistReason
	end
	pet.Level = normalizedLevel
	pet.Experience = normalizedExperience
	return clonePet(pet), nil
end

-- Trusted acquisition API. Every granted Pet is mirrored into the persistent exact-UID profile; hatch logic remains a later feature.
function PetInventoryService.Grant(player, requestedPet, variant)
	if not validPlayer(player) then
		return nil, "Player is not in this server."
	end
	local state = getState(player)
	if not state then
		return nil, "Pet inventory is not initialized."
	end
	local petId = Rules.resolve(requestedPet, Catalog)
	local definition = petId and Catalog.Pets[petId]
	if not definition then
		return nil, "Unknown pet: " .. tostring(requestedPet)
	end
	if ownedPetCount(state) >= InventoryConfig.PetCapacity then
		return nil, string.format("Pet inventory is full (%d/%d).", InventoryConfig.PetCapacity, InventoryConfig.PetCapacity)
	end
	repeat
		state.NextSequence += 1
	until state.Pets["p" .. tostring(state.NextSequence)] == nil
	local uid = "p" .. tostring(state.NextSequence)
	local pet = {
		Uid = uid,
		PetId = petId,
		SpeciesId = definition.SpeciesId,
		Variant = variant or "Normal",
		Favorite = false,
		Level = 1,
		Experience = 0,
	}
	local persisted, persistReason = profileService.AddPet(player, pet, state.NextSequence)
	if not persisted then
		state.NextSequence -= 1
		return nil, persistReason
	end
	state.Pets[uid] = pet
	table.insert(state.Order, uid)
	return clonePet(pet), nil
end

-- Studio testing support. Callers must unequip before clearing ownership.
function PetInventoryService.Clear(player)
	local state = getState(player)
	if not state then
		return false, "Pet inventory is not initialized."
	end
	local persisted, persistReason = profileService.ClearPets(player)
	if not persisted then
		return false, persistReason
	end
	table.clear(state.Pets)
	table.clear(state.Order)
	return true, nil
end

function PetInventoryService.Start(playerProfileService)
	if started then
		return
	end
	if not playerProfileService then
		error("PetInventoryService requires PlayerProfileService.")
	end
	profileService = playerProfileService
	started = true
	local function added(player)
		getState(player)
	end
	Players.PlayerAdded:Connect(added)
	Players.PlayerRemoving:Connect(function(player)
		inventories[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		added(player)
	end
end

return PetInventoryService
