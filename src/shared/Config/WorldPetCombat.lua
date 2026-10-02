-- Stonewood-only Pet combat behavior. Tutorial Pet combat keeps the frozen
-- PetCombat/PetFollow baseline and does not consume these world-specific values.
return table.freeze({
	-- Owner-centric acquisition uses a smaller radius than disengage so a Pet
	-- does not immediately re-acquire the same encounter while the handler leaves.
	CombatRadiusStuds = 28,
	DisengageDistanceStuds = 36,

	-- A living world target that falls out of the owner's encounter starts a
	-- short authoritative regroup lock. The duration is estimated from how far
	-- the Pet was likely fighting from the owner, then bounded for responsiveness.
	ReturnAcquireLockMinSeconds = 1.10,
	ReturnAcquireLockMaxSeconds = 4.00,
	ReturnMinimumRelativeCatchUpSpeedStuds = 6,
	ReturnRegroupBufferStuds = 8,
	ReturnLockPaddingSeconds = 0.30,

	-- World return/catch-up must be able to overtake a running R6 handler. These
	-- are visual movement caps only; combat ownership/damage remain server-owned.
	ReturnFollowSpeed = 6.4,
	ReturnNearDistanceStuds = 12,
	ReturnMediumDistanceStuds = 24,
	ReturnFarDistanceStuds = 36,
	ReturnNearMaxSpeedStuds = 17.5,
	ReturnMediumMaxSpeedStuds = 20.5,
	ReturnFarMaxSpeedStuds = 23.5,
	ReturnVeryFarMaxSpeedStuds = 26,
	ReturnAccelerationStudsPerSecond2 = 62,
	ReturnTurnSpeedDegreesPerSecond = 420,
	ReturnSettleRadiusStuds = 1.75,
	ReturnRecoverSeconds = 0.14,

	-- Distance recall is deliberately much farther than normal combat leashes.
	-- A temporary terrain/path gap first stalls natural return; only a sustained
	-- failure may use the emergency recall fallback.
	EmergencyRecallDistanceStuds = 115,
	StuckRecallSeconds = 2.0,

	-- A recent confirmed Player hit biases only *new* Pet assignments. Existing
	-- sticky targets are preserved and adaptive attacker capacity still wins first.
	PlayerAssistBiasSeconds = 1.75,
})
