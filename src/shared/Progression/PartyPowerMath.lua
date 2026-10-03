local ProgressionMath = require(script.Parent.ProgressionMath)

local PartyPowerMath = {}

local function positiveNumber(value)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge or value <= 0 then
		return nil
	end
	return value
end

local function roundedCombatStat(baseValue, multiplier)
	return math.max(1, math.floor(baseValue * multiplier + 0.5))
end

function PartyPowerMath.ResolvePetStats(definition, level, progressionConfig)
	if type(definition) ~= "table" or type(progressionConfig) ~= "table" then
		return nil
	end
	local baseDamage = positiveNumber(definition.BaseDamage)
	local baseMaxHealth = positiveNumber(definition.BaseMaxHealth)
	if not baseDamage or not baseMaxHealth then
		return nil
	end

	local damageMultiplier = ProgressionMath.GrowthMultiplier(
		progressionConfig.DamageGrowthPerLevel,
		level,
		progressionConfig
	)
	local maxHealthMultiplier = ProgressionMath.GrowthMultiplier(
		progressionConfig.MaxHealthGrowthPerLevel,
		level,
		progressionConfig
	)
	return roundedCombatStat(baseDamage, damageMultiplier), roundedCombatStat(baseMaxHealth, maxHealthMultiplier)
end

function PartyPowerMath.GetPetPower(definition, level, progressionConfig, attackCadenceSeconds, powerConfig)
	local damage, maxHealth = PartyPowerMath.ResolvePetStats(definition, level, progressionConfig)
	local cadence = positiveNumber(attackCadenceSeconds)
	if not damage or not maxHealth or not cadence or type(powerConfig) ~= "table" then
		return 0
	end
	local dpsWeight = math.max(0, tonumber(powerConfig.DpsWeight) or 0)
	local maxHealthWeight = math.max(0, tonumber(powerConfig.MaxHealthWeight) or 0)
	local dps = damage / cadence
	return math.max(0, math.floor(dps * dpsWeight + maxHealth * maxHealthWeight + 0.5))
end

return PartyPowerMath
