local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.SlimeCombat)

local SlimeHealth = {}

function SlimeHealth.Initialize(model)
	model:SetAttribute("MaxHealth", Config.MaxHealth)
	model:SetAttribute("Health", Config.MaxHealth)
	model:SetAttribute("Defeated", false)
	model:SetAttribute("LastHitUserId", 0)
end

function SlimeHealth.IsAlive(model)
	return model
		and model:GetAttribute("Defeated") ~= true
		and (model:GetAttribute("Health") or 0) > 0
end

function SlimeHealth.ApplyDamage(model, amount, player)
	if not SlimeHealth.IsAlive(model) then
		return false, 0
	end
	local current = model:GetAttribute("Health") or Config.MaxHealth
	local nextHealth = math.max(0, current - math.max(0, amount))
	model:SetAttribute("Health", nextHealth)
	model:SetAttribute("LastHitUserId", player and player.UserId or 0)
	if nextHealth <= 0 then
		model:SetAttribute("Defeated", true)
		model:SetAttribute("CombatReady", false)
		model:SetAttribute("AttackQueued", false)
		model:SetAttribute("AttackTurnActive", false)
		model:SetAttribute("TargetUserId", 0)
		model:SetAttribute("SlimeState", "Defeated")
	end
	return true, nextHealth
end

return SlimeHealth
