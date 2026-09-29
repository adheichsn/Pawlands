return table.freeze({
	MaxHealth = 100,

	-- Tutorial combat profile: readable, one-at-a-time pressure with enough space
	-- for a new player to understand the slime's intent before impact.
	AttackDamage = 10,
	NoticeSeconds = 0.60,
	InitialAttackDelaySeconds = 0.75,
	AttackIntervalSeconds = 2.50,
	AttackStaggerSeconds = 0.00,
	AttackGlobalGapSeconds = 0.95,
	AttackCancelGapSeconds = 0.25,
	MaxConcurrentAttackers = 1,

	AttackWindupSeconds = 0.22,
	AttackImpactSeconds = 0.20,
	AttackStrikeSeconds = 0.46,
	AttackLungeDistance = 3.70,
	AttackHopHeight = 0.92,
	AttackDamageRange = 5.25,
})
