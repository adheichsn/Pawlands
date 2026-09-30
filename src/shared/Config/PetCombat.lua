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

	-- Combat facing is state-aware: approach/retarget faces travel, settled pets
	-- face the slime, and return faces the owner formation. Degree caps avoid
	-- one-frame yaw snaps while keeping combat orientation responsive.
	CombatTurnSpeedDegreesPerSecond = 480,
	RetargetTurnSpeedDegreesPerSecond = 420,
	ReturnTurnSpeedDegreesPerSecond = 360,

	-- Pawtopia-inspired Pet damage presentation, adapted to Pawlands' single visual
	-- actor. These values never alter server damage, KO duration, target ownership,
	-- or combat positioning authority; they only add readable recoil/down/recovery.
	PetHitRecoilSeconds = 0.24,
	PetHitRecoilStuds = 0.68,
	-- Pawtopia-style hit readability: hold the pre-impact yaw briefly so a Pet
	-- reads as being struck instead of visually snapping toward a new facing goal.
	-- Replicated Health decrease is the canonical hit signal; the feedback remote
	-- remains an immediate server-confirmed timing/direction fallback.
	PetHitFacingHoldSeconds = 0.12,
	PetHitRemoteDedupSeconds = 0.18,
	PetKnockoutBackStuds = 1.0,
	PetKnockoutPushSeconds = 0.16,
	PetKnockoutPitchDegrees = -8,
	PetKnockoutRollDegrees = 68,
	PetRecoveryBounceSeconds = 0.34,
	PetRecoveryBounceStuds = 0.55,

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
	FeedbackRemoteName = "PetCombatFeedback",
})
