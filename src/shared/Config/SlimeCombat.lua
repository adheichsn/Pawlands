return table.freeze({
	MaxHealth = 100,

	-- Pawtopia tutorial pressure profile. Pursuit is independent from attack
	-- ownership; only attack-ready slimes enter the FIFO turn queue.
	AttackDamage = 10,
	NoticeSeconds = 0.26,
	InitialAttackDelaySeconds = 0.25,
	AttackIntervalSeconds = 2.50,
	AttackStaggerSeconds = 0.00,
	PlayerPressureCooldownSeconds = 2.20,

	-- Pet-centric targeting: slimes prefer active combat pets while the Player
	-- remains a meaningful pressure target. The choice is sticky per target
	-- window rather than re-rolled every strike.
	PetTargetChance = 0.80,
	TargetStickMinSeconds = 2.50,
	TargetStickMaxSeconds = 3.50,
	MaxSlimesPerPet = 2,
	PetPressureCooldownSeconds = 2.20,
	AttackCancelGapSeconds = 0.00,
	MaxConcurrentAttackers = 1,
	AttackQueueRequestLifetimeSeconds = 1.00,

	-- Tutorial wind-up intentionally gives the Player a readable dodge window.
	-- Target position/direction are locked when the strike begins; the lunge does
	-- not home after the Player moves.
	AttackWindupSeconds = 0.75,
	AttackImpactSeconds = 0.18,
	AttackStrikeSeconds = 0.36,
	AttackLungeDistance = 3.70,
	AttackHopHeight = 0.92,
	AttackDodgeToleranceStuds = 2.75,
	AttackMaxImpactDistanceStuds = 9.50,
})
