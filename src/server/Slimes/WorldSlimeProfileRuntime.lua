local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local CombatBaseline = require(Shared.Config.SlimeCombat)
local Profiles = require(Shared.Config.WorldSlimeProfiles)

local WorldSlimeProfileRuntime = {}

local function cloneWithOverrides(base, overrides)
	local result = table.clone(base)
	for key, value in pairs(overrides or {}) do
		result[key] = value
	end
	return result
end

local function multipliedConfig(base, passive)
	local movement = table.clone(base.Movement)
	local combat = table.clone(base.Combat)

	local chaseMultiplier = tonumber(passive.ChaseSpeedMultiplier) or 1
	movement.ChaseSpeed *= chaseMultiplier
	movement.ChaseCatchupMaxSpeed *= chaseMultiplier

	local cadenceMultiplier = tonumber(passive.AttackIntervalMultiplier) or 1
	combat.AttackIntervalSeconds *= cadenceMultiplier
	combat.PlayerPressureCooldownSeconds *= cadenceMultiplier
	combat.PetPressureCooldownSeconds *= cadenceMultiplier

	return table.freeze(movement), table.freeze(combat)
end

function WorldSlimeProfileRuntime.Resolve(definition)
	local slimeId = definition and tostring(definition.Id or "") or ""
	return Profiles[slimeId]
end

function WorldSlimeProfileRuntime.BuildMovementConfig(baseMovementConfig, profile)
	if not profile then
		return baseMovementConfig
	end
	return table.freeze(cloneWithOverrides(baseMovementConfig, profile.Movement))
end

function WorldSlimeProfileRuntime.Attach(agent, profile)
	if not agent or not agent.Model or not profile then
		return false
	end

	local model = agent.Model
	local maximum = math.max(1, math.floor((tonumber(profile.MaxHealth) or CombatBaseline.MaxHealth) + 0.5))
	local baseCombat = cloneWithOverrides(CombatBaseline, profile.Combat)
	local baseMovement = agent.Config
	local frenzyMovement = nil
	local frenzyCombat = nil

	if profile.Passive and profile.Passive.Id == "Frenzy" then
		frenzyMovement, frenzyCombat = multipliedConfig({
			Movement = baseMovement,
			Combat = baseCombat,
		}, profile.Passive)
	end

	agent.WorldProfile = profile
	agent.WorldCombatConfig = table.freeze(baseCombat)
	agent.WorldFrenzyMovementConfig = frenzyMovement
	agent.WorldFrenzyCombatConfig = frenzyCombat
	agent.WorldPassiveActive = false

	model:SetAttribute("CombatRole", tostring(profile.Role or "Balanced"))
	model:SetAttribute("PassiveId", profile.Passive and tostring(profile.Passive.Id or "") or "")
	model:SetAttribute("PassiveActive", false)
	model:SetAttribute("MaxHealth", maximum)
	model:SetAttribute("Health", maximum)
	model:SetAttribute("AttackDamage", agent.WorldCombatConfig.AttackDamage)
	model:SetAttribute("AttackIntervalSeconds", agent.WorldCombatConfig.AttackIntervalSeconds)
	model:SetAttribute("AggroRange", baseMovement.AggroRange)
	model:SetAttribute("DisengageRange", baseMovement.DisengageRange)
	model:SetAttribute("ChaseSpeed", baseMovement.ChaseSpeed)
	return true
end

local function refreshPassive(agent)
	local profile = agent and agent.WorldProfile
	local passive = profile and profile.Passive
	if not passive or passive.Id ~= "Frenzy" then
		return false
	end

	local model = agent.Model
	local maximum = math.max(1, tonumber(model:GetAttribute("MaxHealth")) or profile.MaxHealth or 1)
	local health = math.max(0, tonumber(model:GetAttribute("Health")) or maximum)
	local threshold = math.clamp(tonumber(passive.HealthRatio) or 0.35, 0, 1)
	local active = health > 0 and (health / maximum) <= threshold

	if agent.WorldPassiveActive ~= active then
		agent.WorldPassiveActive = active
		model:SetAttribute("PassiveActive", active)
		local combat = active and agent.WorldFrenzyCombatConfig or agent.WorldCombatConfig
		local movement = active and agent.WorldFrenzyMovementConfig or agent.Config
		if combat then
			model:SetAttribute("AttackIntervalSeconds", combat.AttackIntervalSeconds)
		end
		if movement then
			model:SetAttribute("ChaseSpeed", movement.ChaseSpeed)
		end
	end
	return active
end

function WorldSlimeProfileRuntime.MovementConfigFor(agent)
	if not agent then
		return nil
	end
	if refreshPassive(agent) and agent.WorldFrenzyMovementConfig then
		return agent.WorldFrenzyMovementConfig
	end
	return agent.Config
end

function WorldSlimeProfileRuntime.CombatConfigFor(agent)
	if not agent then
		return CombatBaseline
	end
	if refreshPassive(agent) and agent.WorldFrenzyCombatConfig then
		return agent.WorldFrenzyCombatConfig
	end
	return agent.WorldCombatConfig or CombatBaseline
end

return WorldSlimeProfileRuntime
