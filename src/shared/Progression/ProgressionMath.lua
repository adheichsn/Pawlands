local ProgressionMath = {}

local function finiteNumber(value, fallback)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function maxLevel(config)
	return math.max(1, math.floor(finiteNumber(config and config.MaxLevel, 1)))
end

local function initialLevel(config)
	return math.clamp(
		math.floor(finiteNumber(config and config.InitialLevel, 1)),
		1,
		maxLevel(config)
	)
end

function ProgressionMath.ExperienceForNextLevel(level, config)
	local cap = maxLevel(config)
	level = math.clamp(math.floor(finiteNumber(level, initialLevel(config))), 1, cap)
	if level >= cap then
		return 0
	end

	local curve = config and config.ExperienceCurve or nil
	local index = level - 1
	local base = finiteNumber(curve and curve.Base, 1)
	local linear = finiteNumber(curve and curve.Linear, 0)
	local quadratic = finiteNumber(curve and curve.Quadratic, 0)
	return math.max(1, math.floor(base + linear * index + quadratic * index * index + 0.5))
end

function ProgressionMath.TotalExperienceForLevel(level, config)
	local cap = maxLevel(config)
	level = math.clamp(math.floor(finiteNumber(level, initialLevel(config))), 1, cap)
	local total = 0
	for currentLevel = 1, level - 1 do
		total += ProgressionMath.ExperienceForNextLevel(currentLevel, config)
	end
	return total
end

function ProgressionMath.MaxTotalExperience(config)
	return ProgressionMath.TotalExperienceForLevel(maxLevel(config), config)
end

function ProgressionMath.Resolve(totalExperience, config)
	local cap = maxLevel(config)
	local minimum = initialLevel(config)
	local maximumExperience = ProgressionMath.MaxTotalExperience(config)
	local total = math.clamp(
		math.floor(finiteNumber(totalExperience, 0) + 0.5),
		0,
		maximumExperience
	)

	local level = 1
	local remaining = total
	while level < cap do
		local required = ProgressionMath.ExperienceForNextLevel(level, config)
		if remaining < required then
			break
		end
		remaining -= required
		level += 1
	end
	level = math.max(level, minimum)

	local toNext = level < cap and ProgressionMath.ExperienceForNextLevel(level, config) or 0
	return {
		Level = level,
		MaxLevel = cap,
		TotalExperience = total,
		ExperienceIntoLevel = level < cap and remaining or 0,
		ExperienceToNextLevel = toNext,
		MaxTotalExperience = maximumExperience,
		IsMaxLevel = level >= cap,
	}
end

function ProgressionMath.GrowthMultiplier(growthPerLevel, level, config)
	local cap = maxLevel(config)
	level = math.clamp(math.floor(finiteNumber(level, initialLevel(config))), 1, cap)
	local growth = math.max(0, finiteNumber(growthPerLevel, 0))
	return 1 + growth * math.max(0, level - 1)
end

function ProgressionMath.ApplyBaseGrowth(baseValue, growthPerLevel, level, config)
	local base = math.max(0, finiteNumber(baseValue, 0))
	return base * ProgressionMath.GrowthMultiplier(growthPerLevel, level, config)
end

return table.freeze(ProgressionMath)
