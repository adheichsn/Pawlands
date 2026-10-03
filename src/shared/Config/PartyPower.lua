return table.freeze({
	-- Canonical permanent build-strength summary for the currently equipped party.
	-- This value is descriptive only; combat never derives damage from Party Power.
	AttributeName = "PawlandsPartyPower",
	LeaderstatsFolderName = "leaderstats",
	LeaderstatName = "Power",

	-- Power is derived from the same rounded permanent stats used by combat:
	-- DPS contributes offense, while MaxHealth contributes survivability.
	DpsWeight = 30,
	MaxHealthWeight = 2,
})
