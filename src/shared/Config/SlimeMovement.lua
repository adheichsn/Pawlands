return table.freeze({
	Enabled = true,
	RuntimeFolderName = "PawlandsSlimes",
	SpawnCount = 4,

	ZonePath = table.freeze({ "StarterStoneIsland", "Tutorial", "Zones", "CombatZone" }),
	SpawnPointName = "Points",
	ZonePadding = 1.5,

	-- Studio-authored Points describe the outer combat boundary. Runtime spawn
	-- positions are lerped toward the boundary center so slimes begin inside the
	-- arena instead of sitting directly on the authored edge attachments.
	SpawnBoundaryInsetAlpha = 0.55,

	WanderSpeed = 2.8,
	ChaseSpeed = 9.8,
	ChaseCatchupMaxSpeed = 11.5,
	ChaseCatchupStartDistance = 10,
	ChaseCatchupFullDistance = 24,
	EngageRepositionSpeed = 6.0,
	ReturnSpeed = 8.8,
	IdleSeparationSpeed = 2.25,
	Acceleration = 11,
	TurnSpeed = 12,
	ArrivalRadius = 1.15,

	IdleMinSeconds = 2.5,
	IdleMaxSeconds = 5.0,

	-- Normal wandering stays local to each slime's own spawn/home position.
	WanderRadius = 4.4,
	WanderMinRadiusScale = 0.35,
	ReturnHomeDistance = 2.5,

	AggroRange = 34,
	DisengageRange = 44,

	-- Four engaged slimes use a stable square footprint around the player:
	-- front / right / back / left. A slime becomes combat-ready from range +
	-- line-of-sight; it never has to finish walking to its exact slot first.
	EngageRadius = 7.0,
	EngageInnerDistance = 5.25,
	EngageReadyDistance = 8.75,
	FormationPredictionSeconds = 0.16,
	FormationVelocityThreshold = 1.5,
	FormationHeadingSmoothing = 5.5,
	FormationReassignSeconds = 0.30,
	FormationSwitchPenalty = 3.0,
	FormationSlotTolerance = 1.35,

	-- Crowd steering is independent from physical collision. Runtime slime parts
	-- stay non-collidable while these logical radii prevent visual stacking.
	SeparationRadius = 6.5,
	HardSeparationRadius = 4.0,
	SeparationWeight = 10,
	HardSeparationWeight = 22,
	SeparationLookahead = 0.25,

	-- Local obstacle avoidance runs every movement step. It first steers around a
	-- blocking surface and only asks PathfindingService for waypoints after the
	-- direct route remains blocked long enough to justify the extra work.
	ObstacleProbeHeight = 1.45,
	ObstacleProbeSize = Vector3.new(3.4, 2.6, 1.2),
	ObstacleProbeDistance = 7.0,
	ObstacleSideStep = 4.75,
	ObstacleForwardBias = 2.25,
	ObstacleNormalClearance = 1.0,
	ObstacleAvoidanceHoldSeconds = 0.50,
	ObstacleSideSwitchPenalty = 2.0,
	ObstacleSkin = 0.20,
	PathfindAfterBlockedSeconds = 0.65,
	PathfindCooldownSeconds = 0.90,
	PathGoalRefreshDistance = 5.0,
	PathWaypointArrivalRadius = 1.35,
	PathAgentRadius = 2.0,
	PathAgentHeight = 4.0,
	PathWaypointSpacing = 3.0,

	-- Moving slimes get a stride-driven hop instead of sliding flat. The tiny
	-- idle bob remains as a fallback when no Studio-authored loop is available.
	MoveHopHeight = 0.62,
	MoveHopStrideStuds = 2.55,
	IdleBobHeight = 0.12,
	IdleBobCyclesPerSecond = 0.65,

	GroundRayHeight = 18,
	GroundRayDistance = 80,
	MinGroundNormalY = 0.35,

	UpdateRate = 30,
	MaxStep = 0.08,
	YawOffset = 180,
})
