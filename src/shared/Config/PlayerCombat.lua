return table.freeze({
	Damage = 10,
	AttackRange = 7.0,
	AttackCooldown = 0.34,
	ComboResetSeconds = 0.80,

	-- Soft targeting keeps M1 free-form: the attack always plays, then the
	-- client selects the best visible slime in front of the player if one exists.
	TargetAcquisitionRange = 8.0,
	TargetHalfAngleDegrees = 78,
	TargetAngleWeight = 1.20,
	TargetDistanceWeight = 0.65,
	TargetCursorWeight = 0.85,
	DirectHoverBonus = 0.55,

	-- The server still owns hit validation. The aim allowance is deliberately
	-- broader than the client cone to absorb camera/character drift without
	-- permitting targets directly behind the player.
	ServerAimHalfAngleDegrees = 90,
	ServerRootHalfAngleDegrees = 135,

	RequireGrounded = true,
	RequireLineOfSight = true,

	AnimationFade = 0.03,
	AnimationPlaybackSpeed = 1.45,
	AnimationMaxSeconds = 0.52,
	RunningAnimationMaxSeconds = 0.58,
	AnimationPriority = Enum.AnimationPriority.Action2,
	RunningAttackMinHorizontalSpeed = 4.0,

	RemoteFolderName = "Remotes",
	AttackRemoteName = "PlayerBasicAttack",
})
