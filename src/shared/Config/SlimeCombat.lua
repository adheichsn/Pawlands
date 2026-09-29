return table.freeze({
	MaxHealth = 100,

	-- Pawtopia-derived readable pressure loop. Damage stays deliberately light for
	-- this foundation pass; defeat/reward balancing remains a later stage.
	AttackDamage = 10,
	NoticeSeconds = 0.26,
	InitialAttackDelaySeconds = 0.25,
	AttackIntervalSeconds = 1.30,
	AttackStaggerSeconds = 0.08,
	AttackWindupSeconds = 0.12,
	AttackImpactSeconds = 0.18,
	AttackStrikeSeconds = 0.36,
	AttackLungeDistance = 3.70,
	AttackHopHeight = 0.92,
	AttackDamageRange = 5.25,
})
