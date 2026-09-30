return table.freeze({
	AssignmentAttributeName = "PawlandsPetCombat",
	MaxAttackersPerNormalSlime = 2,
	SoftLeashStuds = 30,
	HardLeashStuds = 45,
	UpdateRate = 10,

	-- Keep pet attackers visibly outside the slime crowd instead of packing into
	-- the player-facing center.
	AttackRadiusStuds = 4.85,
	PairHalfAngleDegrees = 55,
	OuterDirectionMinStuds = 1.25,

	-- Cross-target spacing is presentation-only. It resolves close combat goals
	-- without changing server target ownership or the slime's gameplay position.
	MinCombatPetSpacingStuds = 4.75,
	CombatSpacingPasses = 2,
	CombatSpacingMaxCorrectionStuds = 1.35,

	-- Pet attack presentation combines two useful reference ideas:
	-- PS99: pets first settle into a stable target placement.
	-- Slime RNG: attacks are short, locked-direction lunges that return to origin.
	AttackReadyRadiusStuds = 0.95,
	AttackInitialDelaySeconds = 0.18,
	AttackCadenceSeconds = 1.25,
	AttackStaggerSeconds = 0.14,
	AttackDurationSeconds = 0.32,
	AttackLungeStuds = 3.0,
	GroundAttackHopStuds = 0.52,
	FlyingAttackHopStuds = 0.16,
})
