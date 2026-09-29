return table.freeze({
	-- Keep the defeated model visible briefly so the final hit has readable impact.
	-- No authored defeat animation is required yet; the existing model simply holds
	-- its last pose before the runtime clone is destroyed.
	DefeatPresentationSeconds = 0.50,

	-- Tutorial respawn timing begins after the defeated model has despawned.
	RespawnDelaySeconds = 5.00,
	RespawnRetrySeconds = 1.00,

	-- Respawns reuse the authored CombatZone boundary points, but choose a safe
	-- inset candidate instead of recreating the slime at its death position.
	RespawnCandidateCount = 8,
	RespawnPlayerClearanceStuds = 8.0,
	RespawnSlimeClearanceStuds = 6.0,
	RespawnDeathClearanceStuds = 4.0,
})
