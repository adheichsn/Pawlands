return table.freeze({
	Enabled = true,
	TrackWorldCombatOnly = true,
	WorldCombatAttributeName = "WorldCombat",

	-- Normal Stonewood mobs currently treat any positive authoritative damage as
	-- meaningful participation. Elite/Boss runtimes can override these per model
	-- later without changing the contribution service.
	MinimumDamage = 1,
	MinimumShare = 0,
	MinimumDamageAttributeName = "ContributionMinDamage",
	MinimumShareAttributeName = "ContributionMinShare",

	FinalizedAttributeName = "ContributionFinalized",
	ParticipantCountAttributeName = "ContributionParticipantCount",
	EligibleCountAttributeName = "ContributionEligibleCount",
	EncounterSerialAttributeName = "ContributionEncounterSerial",

	StudioLogFinalized = true,
})
