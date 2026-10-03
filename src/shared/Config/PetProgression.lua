return table.freeze({
	InitialLevel = 1,
	MaxLevel = 50,
	RevisionAttributeName = "PawlandsPetProgressionRevision",

	-- Permanent level growth is additive against the authored species base stat.
	-- Lv1 therefore preserves the current combat baseline exactly.
	DamageGrowthPerLevel = 0.032,
	MaxHealthGrowthPerLevel = 0.024,

	-- Required EXP from level L to L+1:
	-- round(Base + Linear*(L-1) + Quadratic*(L-1)^2)
	-- Total Lv1 -> Lv50 = 71,258 EXP.
	ExperienceCurve = table.freeze({
		Base = 50,
		Linear = 10,
		Quadratic = 1.5,
	}),
})
