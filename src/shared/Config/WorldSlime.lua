-- Stonewood's live world-combat population.
-- Tutorial combat remains authored and controlled separately by TutorialService.
local populationTiers = {
	{ MaxPlayers = 1, Population = 8 },
	{ MaxPlayers = 3, Population = 10 },
	{ MaxPlayers = 6, Population = 12 },
	{ MaxPlayers = 10, Population = 14 },
	{ MaxPlayers = 16, Population = 16 },
}
for _, tier in ipairs(populationTiers) do
	table.freeze(tier)
end

return table.freeze({
	Enabled = true,

	-- Prefer the clean authoring path when it exists, but keep the legacy wrapper
	-- valid for older Studio snapshots.
	RegionRootPaths = table.freeze({
		table.freeze({ "StonewoodIsland", "Combat", "Regions" }),
		table.freeze({ "StonewoodIsland", "Combat", "Zones", "Zones" }),
	}),
	RegionNames = table.freeze({ "Region01", "Region02", "Region03" }),
	SpawnPointName = "Points",

	-- 0-1 active Stonewood player keeps the authored island warm at 8 Slimes.
	-- Scaling is intentionally light for the compact island and caps at 16.
	Population = 8,
	MaxPopulation = 16,
	PopulationTiers = table.freeze(populationTiers),
	PopulationRefreshSeconds = 1.0,
	PopulationFillIntervalSeconds = 0.75,
	SlotBase = 100,

	-- Stable weighted composition for world population slots. Smooth weighted
	-- round-robin resolves the slot sequence, so respawns keep their species.
	SpeciesOrder = table.freeze({ "goopy", "fin", "sunset", "derpy" }),
	SpeciesWeights = table.freeze({
		goopy = 45,
		fin = 25,
		sunset = 20,
		derpy = 10,
	}),

	-- New population and respawns must find grounded authored samples that are
	-- clear of Players, existing Slimes, and active fights. If no candidate is
	-- safe, the slot waits and retries rather than popping into combat.
	SpawnCandidateCount = 8,
	SpawnPlayerClearanceStuds = 24.0,
	SpawnSlimeClearanceStuds = 8.0,
	SpawnCombatClearanceStuds = 18.0,
	RespawnDeathClearanceStuds = 6.0,
	RespawnDelayMinSeconds = 4.0,
	RespawnDelayMaxSeconds = 7.0,
	RespawnRetrySeconds = 1.0,

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
