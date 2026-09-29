return table.freeze({
	Damage = 10,
	AttackRange = 7.0,

	-- Server-only anti-spam guard. Client combo cadence is intentionally slower;
	-- this value only protects authoritative damage from impossible request rates.
	AttackCooldown = 0.28,

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

	-- Combat presentation tuning. Responsiveness comes from buffered inputs and
	-- staged transitions instead of globally over-speeding the authored tracks.
	AnimationPlaybackSpeed = 1.22,
	AnimationTransitionFade = 0.07,
	AnimationExitFade = 0.12,
	LocomotionSuppressFade = 0.08,
	AnimationExitBlendLead = 0.10,
	AnimationPriority = Enum.AnimationPriority.Action2,
	RunningAttackMinHorizontalSpeed = 4.0,

	-- One early M1 press is remembered and consumed when the next combo window
	-- opens. The finisher only accepts a restart input near recovery end.
	FinisherRestartBufferSeconds = 0.20,

	-- Timing is deliberately asymmetric so the fourth hit carries more weight.
	-- Natural animation length is used when available, clamped by MinHold/MaxHold.
	ComboTiming = table.freeze({
		table.freeze({ NextAt = 0.40, MinHold = 0.50, MaxHold = 0.66 }),
		table.freeze({ NextAt = 0.40, MinHold = 0.50, MaxHold = 0.66 }),
		table.freeze({ NextAt = 0.43, MinHold = 0.54, MaxHold = 0.70 }),
		table.freeze({ NextAt = nil, MinHold = 0.68, MaxHold = 0.88 }),
	}),
	RunningTiming = table.freeze({ NextAt = 0.45, MinHold = 0.56, MaxHold = 0.74 }),

	RemoteFolderName = "Remotes",
	AttackRemoteName = "PlayerBasicAttack",
})
