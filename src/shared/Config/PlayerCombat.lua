local PlayerCombat = {
	Damage = 10,

	ActionTypes = table.freeze({
		M1 = "M1",
		RunningAttack = "RunningAttack",
	}),

	ComboResetSeconds = 1.20,
	InputBufferSeconds = 0.20,
	RequestRateLimitSeconds = 0.10,
	CadenceToleranceSeconds = 0.03,
	AnimationFadeSeconds = 0.08,
	AnimationPriority = Enum.AnimationPriority.Action,

	HitReaction = table.freeze({
		FadeSeconds = 0.05,
		PlaybackSpeed = 1.08,
		MaxVisibleSeconds = 0.42,
		RetriggerCooldownSeconds = 0.18,
		AnimationPriority = Enum.AnimationPriority.Action2,
	}),

	RequireGrounded = true,
	RequireLineOfSight = true,

	-- Client targeting is presentation preference only. A committed attack always
	-- reaches the server, which resolves the actual victim from a forward volume.
	TargetAcquisitionRange = 9.0,
	TargetHalfAngleDegrees = 72,
	TargetAngleWeight = 1.20,
	TargetDistanceWeight = 0.65,
	TargetCursorWeight = 0.70,
	DirectHoverBonus = 0.45,

	-- Keep client camera/facing suggestions bounded against the actual R6 root so
	-- a forged request cannot rotate the authoritative hit volume behind the player.
	ServerAimRootMaxDegrees = 95,

	-- Pets now occupy the immediate melee lane around a slime. Keep the player
	-- fist server-authoritative and directional, but give the handler enough
	-- reach/width to assist from just behind or beside an attacking pet instead
	-- of requiring character-body overlap with the target.
	Hitbox = table.freeze({
		ForwardReachStuds = 6.25,
		HalfWidthStuds = 2.90,
		RearToleranceStuds = 0.45,
		MinimumAimMagnitude = 0.05,
	}),

	Contact = table.freeze({
		PlayerRadiusStuds = 1.45,
		GapStuds = 0.30,
		SoftSeparationMaxStuds = 1.15,
		RaycastPaddingStuds = 0.15,
		FacingAssistMaxDistanceStuds = 18.0,
		MinSlimeRadiusStuds = 1.10,
		MaxSlimeRadiusStuds = 3.00,
	}),

	-- Timings are derived from the same authored 1.0-second fist clips used by the
	-- Pawtopia reference. The first three remain brisk while M4 keeps more weight.
	Combo = table.freeze({
		table.freeze({
			Name = "M1_1",
			AuthoredDurationSeconds = 1.0,
			AuthoredHitTimeSeconds = 0.4833333194,
			TargetDurationSeconds = 0.74,
			CadenceSeconds = 0.55,
			DamageMultiplier = 1.00,
		}),
		table.freeze({
			Name = "M1_2",
			AuthoredDurationSeconds = 1.0,
			AuthoredHitTimeSeconds = 0.4833333194,
			TargetDurationSeconds = 0.74,
			CadenceSeconds = 0.55,
			DamageMultiplier = 1.05,
		}),
		table.freeze({
			Name = "M1_3",
			AuthoredDurationSeconds = 1.0,
			AuthoredHitTimeSeconds = 0.4833333194,
			TargetDurationSeconds = 0.74,
			CadenceSeconds = 0.55,
			DamageMultiplier = 1.10,
		}),
		table.freeze({
			Name = "M1_4",
			AuthoredDurationSeconds = 1.0,
			AuthoredHitTimeSeconds = 0.4666666687,
			TargetDurationSeconds = 0.80,
			CadenceSeconds = 0.70,
			DamageMultiplier = 1.35,
		}),
	}),

	RunningAttack = table.freeze({
		Name = "RunningAttack",
		AuthoredDurationSeconds = 0.6000000238,
		AuthoredHitTimeSeconds = 0.3333333433,
		TargetDurationSeconds = 0.60,
		CadenceSeconds = 0.60,
		DamageMultiplier = 1.25,
		ClientMinimumHorizontalSpeedStuds = 11.0,
		ServerMinimumHorizontalSpeedStuds = 10.5,
	}),

	RemoteFolderName = "Remotes",
	AttackRemoteName = "PlayerBasicAttack",
}

function PlayerCombat.GetComboDefinition(comboIndex)
	return PlayerCombat.Combo[comboIndex]
end

function PlayerCombat.GetComboPlaybackSpeed(comboIndex, loadedTrackLength)
	local definition = PlayerCombat.GetComboDefinition(comboIndex)
	if not definition then
		return 1
	end
	local sourceLength = tonumber(loadedTrackLength)
	if not sourceLength or sourceLength <= 0 then
		sourceLength = definition.AuthoredDurationSeconds
	end
	return math.clamp(sourceLength / math.max(0.001, definition.TargetDurationSeconds), 0.1, 3)
end

function PlayerCombat.GetComboImpactDelay(comboIndex)
	local definition = PlayerCombat.GetComboDefinition(comboIndex)
	if not definition then
		return 0
	end
	local ratio = math.clamp(
		definition.AuthoredHitTimeSeconds / math.max(0.001, definition.AuthoredDurationSeconds),
		0,
		1
	)
	return definition.TargetDurationSeconds * ratio
end

function PlayerCombat.GetRunningPlaybackSpeed(loadedTrackLength)
	local definition = PlayerCombat.RunningAttack
	local sourceLength = tonumber(loadedTrackLength)
	if not sourceLength or sourceLength <= 0 then
		sourceLength = definition.AuthoredDurationSeconds
	end
	return math.clamp(sourceLength / math.max(0.001, definition.TargetDurationSeconds), 0.1, 3)
end

function PlayerCombat.GetRunningImpactDelay()
	local definition = PlayerCombat.RunningAttack
	local ratio = math.clamp(
		definition.AuthoredHitTimeSeconds / math.max(0.001, definition.AuthoredDurationSeconds),
		0,
		1
	)
	return definition.TargetDurationSeconds * ratio
end

return table.freeze(PlayerCombat)
