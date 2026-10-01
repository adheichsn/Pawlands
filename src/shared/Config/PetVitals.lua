local States = table.freeze({
	Idle = "Idle",
	Combat = "Combat",
	Recovering = "Recovering",
	KO = "KO",
})

return table.freeze({
	AttributeName = "PawlandsPetVitals",
	-- Safety only for malformed/missing catalog entries; normal Pets use PetCatalog.BaseMaxHealth.
	FallbackMaxHealth = 100,
	RecoverSeconds = 6,

	-- Pawtopia-inspired out-of-combat reset, adapted into a visible smooth fill for
	-- Pawlands. Damaged healthy Pets enter Recovering when combat ownership ends,
	-- wait briefly, then refill from their current HP to MaxHealth over this window.
	OutOfCombatRecoveryDelaySeconds = 0.35,
	OutOfCombatRecoverySeconds = 3.0,

	-- Recovery publishes often enough for the authored healthbar tween to read as
	-- a continuous refill without turning Pet vitals into a per-frame server loop.
	UpdateRate = 10,
	States = States,
})
