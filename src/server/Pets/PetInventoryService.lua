local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Catalog = require(Shared.Config.PetCatalog)
local Rules = require(Shared.Pets.PartyRules)

local PetInventoryService = {}
local inventories = {}
local started = false

local function validPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function getState(player)
	local state = inventories[player]
	if state or not validPlayer(player) then
		return state
	end

	-- PlayerAdded listeners run in separate tasks, so dependent services must not
	-- assume this service's listener has initialized the session first.
	state = { Pets = {}, Order = {}, NextSequence = 0 }
	inventories[player] = state
	return state
end

local function clonePet(pet)
	return pet and table.clone(pet) or nil
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

-- Session-only grant API. Persistence and hatch acquisition are intentionally not part of this patch.
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
	state.NextSequence += 1
	local uid = "p" .. tostring(state.NextSequence)
	local pet = {
		Uid = uid,
		PetId = petId,
		SpeciesId = definition.SpeciesId,
		Variant = variant or "Normal",
	}
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
	table.clear(state.Pets)
	table.clear(state.Order)
	return true, nil
end

function PetInventoryService.Start()
	if started then
		return
	end
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
