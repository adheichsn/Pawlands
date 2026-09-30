return table.freeze({
	AssignmentAttributeName = "PawlandsPetCombat",
	MaxAttackersPerNormalSlime = 2,
	SoftLeashStuds = 30,
	HardLeashStuds = 45,
	UpdateRate = 10,

	-- Keep pet attackers visibly outside the slime crowd instead of packing into
	-- the player-facing center. Actual attack lunges will be layered on later.
	AttackRadiusStuds = 4.85,
	PairHalfAngleDegrees = 55,
	OuterDirectionMinStuds = 1.25,

	-- Cross-target spacing is presentation-only. It resolves close combat goals
	-- without changing server target ownership or the slime's gameplay position.
	MinCombatPetSpacingStuds = 4.75,
	CombatSpacingPasses = 2,
	CombatSpacingMaxCorrectionStuds = 1.35,
})
