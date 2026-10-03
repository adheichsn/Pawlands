return table.freeze({
	InitialLevel = 1,
	MaxLevel = 50,

	-- Handler growth is intentionally light. These values are foundation data;
	-- Player combat/health application is deferred to the Handler runtime stage.
	DamageGrowthPerLevel = 0.005,
	MaxHealthGrowthPerLevel = 0.0075,

	-- Required EXP from level L to L+1:
	-- round(Base + Linear*(L-1) + Quadratic*(L-1)^2)
	-- Total Lv1 -> Lv50 = 232,750 EXP.
	ExperienceCurve = table.freeze({
		Base = 150,
		Linear = 30,
		Quadratic = 5,
	}),

	LevelAttributeName = "PawlandsHandlerLevel",
	ExperienceAttributeName = "PawlandsHandlerExperience",
	ExperienceIntoLevelAttributeName = "PawlandsHandlerExperienceIntoLevel",
	ExperienceToNextLevelAttributeName = "PawlandsHandlerExperienceToNextLevel",
})
