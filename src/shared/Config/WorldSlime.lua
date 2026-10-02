-- Stonewood's first live world-combat population.
-- Tutorial combat remains authored and controlled separately by TutorialService.
return table.freeze({
	Enabled = true,

	-- Prefer the clean authoring path when it exists, but keep the current Studio
	-- hierarchy valid so Region01/02/03 do not need another map edit for this patch.
	RegionRootPaths = table.freeze({
		table.freeze({ "StonewoodIsland", "Combat", "Regions" }),
		table.freeze({ "StonewoodIsland", "Combat", "Zones", "Zones" }),
	}),
	RegionNames = table.freeze({ "Region01", "Region02", "Region03" }),
	SpawnPointName = "Points",

	-- Initial QA population for the compact Stonewood island. This is not final
	-- balance; later population scaling can build on this foundation.
	Population = 8,
	SlotBase = 100,

	-- World Slimes should not aggro the whole region the way tutorial actors do.
	-- All unspecified movement values continue using the frozen SlimeMovement
	-- baseline so Player/Pet combat parity is preserved.
	MovementOverrides = table.freeze({
		AggroRange = 24,
		DisengageRange = 36,
		WanderRadius = 5.5,
		ReturnHomeDistance = 8.0,
	}),
})
