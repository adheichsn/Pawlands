return table.freeze({
	AssignmentAttributeName = "PawlandsPetCombat",
	-- Adaptive focus fire keeps pets spread while multiple slimes are alive, then
	-- lets the whole party collapse onto the last available target.
	MaxAttackersPerNormalSlime = 4,
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

	-- Target handoff presentation. Retarget/return movement is capped so a dead
	-- target cannot make a pet visually snap or "whoosh" across the arena.
	RetargetRecoverSeconds = 0.24,
	ReturnRecoverSeconds = 0.30,
	TransitionStaggerSeconds = 0.045,
	TransitionSettleRadiusStuds = 1.20,
	CombatApproachFollowSpeed = 6.0,
	CombatApproachMaxSpeedStuds = 18.0,
	RetargetMaxSpeedStuds = 15.5,
	ReturnFollowSpeed = 4.8,
	ReturnMaxSpeedStuds = 12.5,

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

	-- The client reports only the authored visual impact beat. The server owns
	-- assignment validation, KO/leash checks, cadence, target resolution, and
	-- damage, so a client cannot choose a victim or damage amount.
	AttackImpactAlpha = 0.50,
	DefaultDamage = 12,
	ServerImpactCadenceToleranceSeconds = 0.12,
	ServerImpactLeashPaddingStuds = 2.0,
	RemoteFolderName = "Remotes",
	AttackImpactRemoteName = "PetAttackImpact",
})
