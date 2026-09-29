return table.freeze({
	Enabled = true,
	RuntimeFolderName = "PawlandsSlimes",
	SpawnCount = 4,

	ZonePath = table.freeze({ "StarterStoneIsland", "Tutorial", "Zones", "CombatZone" }),
	SpawnPointName = "Points",
	ZonePadding = 1.5,

	WanderSpeed = 4.5,
	ChaseSpeed = 8,
	IdleSeparationSpeed = 2.25,
	Acceleration = 9,
	TurnSpeed = 10,
	ArrivalRadius = 1.25,

	IdleMinSeconds = 2.5,
	IdleMaxSeconds = 5.0,

	AggroRange = 34,
	DisengageRange = 44,
	ChaseRingRadius = 8.0,
	ChaseRingSpacingBoost = 0.45,

	-- Crowd steering is independent from physical collision. Slime BaseParts are
	-- non-collidable, while this logical radius prevents visual stacking.
	SeparationRadius = 6.5,
	HardSeparationRadius = 4.0,
	SeparationWeight = 10,
	HardSeparationWeight = 22,
	SeparationLookahead = 0.25,

	GroundRayHeight = 18,
	GroundRayDistance = 80,
	MinGroundNormalY = 0.35,

	UpdateRate = 30,
	MaxStep = 0.08,
	YawOffset = 180,
})
