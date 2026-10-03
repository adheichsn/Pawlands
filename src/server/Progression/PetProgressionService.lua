local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetProgression)
local ProgressionMath = require(Shared.Progression.ProgressionMath)

local PetProgressionService = {}
local started = false
local inventoryService = nil

local function validPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function finiteNonNegative(value)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return nil
	end
	return value
end

local function snapshotForPet(pet)
	if not pet then
		return nil
	end
	local resolved = ProgressionMath.Resolve(pet.Experience or 0, Config)
	return {
		Uid = pet.Uid,
		PetId = pet.PetId,
		Level = resolved.Level,
		MaxLevel = resolved.MaxLevel,
		Experience = resolved.TotalExperience,
		ExperienceIntoLevel = resolved.ExperienceIntoLevel,
		ExperienceToNextLevel = resolved.ExperienceToNextLevel,
		MaxTotalExperience = resolved.MaxTotalExperience,
		IsMaxLevel = resolved.IsMaxLevel,
	}
end

function PetProgressionService.GetSnapshot(player, uid)
	if not started or not inventoryService then
		return nil, "Pet progression service is unavailable."
	end
	local pet = inventoryService.GetPet(player, uid)
	if not pet then
		return nil, "Pet is not owned: " .. tostring(uid)
	end
	return snapshotForPet(pet), nil
end

function PetProgressionService.SetExperience(player, uid, totalExperience)
	if not started or not inventoryService then
		return nil, "Pet progression service is unavailable."
	end
	if not validPlayer(player) then
		return nil, "Player is not in this server."
	end
	local requested = finiteNonNegative(totalExperience)
	if not requested then
		return nil, "Pet experience must be a finite non-negative number."
	end
	local pet = inventoryService.GetPet(player, uid)
	if not pet then
		return nil, "Pet is not owned: " .. tostring(uid)
	end

	local resolved = ProgressionMath.Resolve(requested, Config)
	local updated, reason = inventoryService.SetProgressionState(
		player,
		uid,
		resolved.Level,
		resolved.TotalExperience
	)
	if not updated then
		return nil, reason
	end
	return snapshotForPet(updated), nil
end

function PetProgressionService.AddExperience(player, uid, amount)
	local gain = finiteNonNegative(amount)
	if not gain then
		return nil, 0, "Pet experience gain must be a finite non-negative number."
	end
	local before, reason = PetProgressionService.GetSnapshot(player, uid)
	if not before then
		return nil, 0, reason
	end
	if before.IsMaxLevel or gain <= 0 then
		return before, 0, nil
	end

	local after
	after, reason = PetProgressionService.SetExperience(player, uid, before.Experience + gain)
	if not after then
		return nil, 0, reason
	end
	return after, math.max(0, after.Level - before.Level), nil
end

function PetProgressionService.GetDamageMultiplier(player, uid)
	local snapshot = PetProgressionService.GetSnapshot(player, uid)
	if not snapshot then
		return 1
	end
	return ProgressionMath.GrowthMultiplier(Config.DamageGrowthPerLevel, snapshot.Level, Config)
end

function PetProgressionService.GetMaxHealthMultiplier(player, uid)
	local snapshot = PetProgressionService.GetSnapshot(player, uid)
	if not snapshot then
		return 1
	end
	return ProgressionMath.GrowthMultiplier(Config.MaxHealthGrowthPerLevel, snapshot.Level, Config)
end

function PetProgressionService.Start(petInventoryService)
	if started then
		return
	end
	if not petInventoryService then
		error("PetProgressionService requires PetInventoryService.")
	end
	inventoryService = petInventoryService
	started = true
end

function PetProgressionService.Stop()
	started = false
	inventoryService = nil
end

return PetProgressionService
