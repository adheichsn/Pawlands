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
	EngageRepositionSpeed = 5.4,
	ReturnSpeed = 8.8,
	IdleSeparationSpeed = 2.8,
	Acceleration = 11,
	TurnSpeed = 10,
	-- Combat target-facing uses a bounded yaw rate instead of vector lerp so
	-- 180-degree opponent handoffs rotate predictably rather than snapping.
	CombatTurnSpeedDegreesPerSecond = 420,
	ArrivalRadius = 1.15,

	IdleMinSeconds = 2.5,
	IdleMaxSeconds = 5.0,

	-- Normal wandering stays local to each slime's own spawn/home position.
	WanderRadius = 4.4,
	WanderMinRadiusScale = 0.35,
	ReturnHomeDistance = 2.5,

	-- Tutorial actors may pursue anywhere inside the authored CombatZone. Arena
	-- containment, rather than a small aggro circle, owns tutorial targeting.
	AggroRange = math.huge,
	DisengageRange = math.huge,

	-- Four engaged slimes keep a stable square staging footprint. The square
	-- translates with the Player but does not rotate from Player velocity every
	-- frame. It is a soft staging guide, not a hard orbit that forces backpedaling.
	EngageRadius = 7.0,
	EngageInnerDistance = 5.25,
	EngageReadyDistance = 8.5,
	SoftStageReleaseDistance = 8.25,
	SoftStageMaxDrift = 3.35,
	FormationSwitchPenalty = 3.0,
	FormationSlotTolerance = 1.35,
	CombatFacingDeadzone = 0.28,

	-- Pawtopia-style bounded separation: keep visible spacing without letting
	-- crowd correction drag a slime far away from its intended combat position.
	SeparationRadius = 5.35,
	SeparationCorrectionStrength = 0.95,
	SeparationMaxCorrectionStuds = 2.10,
	SeparationRepositionThreshold = 0.22,

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
