local CrowdSteering = require(script.Parent.CrowdSteering)
local SlimeNavigation = require(script.Parent.SlimeNavigation)

local SlimeAgent = {}
SlimeAgent.__index = SlimeAgent

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalDistance(a, b)
	return horizontal(a - b).Magnitude
end

local function yawFromDirection(direction)
	direction = horizontal(direction)
	if direction.Magnitude <= 0.001 then
		return nil
	end
	direction = direction.Unit
	return math.atan2(-direction.X, -direction.Z)
end

local function directionFromYaw(yaw)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

local function boundedTurn(current, desired, maxDegreesPerSecond, dt)
	local currentYaw = yawFromDirection(current)
	local targetYaw = yawFromDirection(desired)
	if not targetYaw then
		return current
	end
	if not currentYaw then
		return desired.Unit
	end
	local delta = (targetYaw - currentYaw + math.pi) % (2 * math.pi) - math.pi
	local maxTurn = math.rad(math.max(0, maxDegreesPerSecond or 0)) * dt
	if maxTurn <= 0 then
		return desired.Unit
	end
	return directionFromYaw(currentYaw + math.clamp(delta, -maxTurn, maxTurn))
end

local function isCombatState(state)
	return state == "Notice" or state == "Chase" or state == "Engage" or state == "Attack"
end

function SlimeAgent.new(slot, definition, visual, spawnPosition, config)
	visual.Model:SetAttribute("AttackTurnActive", false)
	visual.Model:SetAttribute("AttackQueued", false)
	visual.Model:SetAttribute("TargetType", "None")
	visual.Model:SetAttribute("TargetPetSlot", 0)
	visual.Model:SetAttribute("TargetPetUid", "")
	local self = setmetatable({
		Slot = slot,
		Definition = definition,
		Visual = visual,
		Model = visual.Model,
		Config = config,
		Position = spawnPosition,
		Velocity = Vector3.zero,
		Facing = Vector3.new(0, 0, 1),
		State = "Idle",
		TargetPlayer = nil,
		TargetKind = nil,
		TargetKey = nil,
		TargetPetSlot = nil,
		TargetPetUid = nil,
		NextTargetReviewAt = 0,
		TargetPlayerHitSerialAtAcquire = 0,
		WanderTarget = nil,
		HomePosition = spawnPosition,
		IdleUntil = 0,
		NoticeUntil = 0,
		NextAttackAt = 0,
		Strike = nil,
		FormationSlot = nil,
		CombatReady = false,
		MoveTravel = 0,
		IdleClock = (slot * 0.37) % 1,
		Navigation = {
			BlockedSince = nil,
			AvoidSide = nil,
			AvoidUntil = 0,
			RepathAt = 0,
			Waypoints = nil,
			WaypointIndex = 0,
			PathGoal = nil,
		},
	}, SlimeAgent)
	return self
end

function SlimeAgent:SetCombatReady(ready)
	ready = ready == true
	if self.CombatReady == ready then
		return
	end
	self.CombatReady = ready
	self.Model:SetAttribute("CombatReady", ready)
end

function SlimeAgent:SetState(state, targetPlayer)
	if self.State == state and self.TargetPlayer == targetPlayer then
		return
	end
	local targetChanged = self.TargetPlayer ~= targetPlayer
	self.State = state
	self.TargetPlayer = targetPlayer
	self.Model:SetAttribute("SlimeState", state)
	self.Model:SetAttribute("TargetUserId", targetPlayer and targetPlayer.UserId or 0)

	if isCombatState(state) then
		self.WanderTarget = nil
	else
		self.FormationSlot = nil
		self:SetCombatReady(false)
		self.TargetKind = nil
		self.TargetKey = nil
		self.TargetPetSlot = nil
		self.TargetPetUid = nil
		self.NextTargetReviewAt = 0
		self.TargetPlayerHitSerialAtAcquire = 0
		self.Model:SetAttribute("TargetType", "None")
		self.Model:SetAttribute("TargetPetSlot", 0)
		self.Model:SetAttribute("TargetPetUid", "")
	end
	if targetChanged then
		-- A new target gets a fresh stable staging assignment. Keeping the old
		-- slot across targets can force a cross-player orbit on the first frame.
		self.FormationSlot = nil
		SlimeNavigation.Reset(self)
	end
end

function SlimeAgent:EnterIdle(now, randomObject)
	self.WanderTarget = nil
	self.Strike = nil
	self:SetState("Idle", nil)
	SlimeNavigation.Reset(self)
	self.IdleUntil = now + randomObject:NextNumber(self.Config.IdleMinSeconds, self.Config.IdleMaxSeconds)
end

function SlimeAgent:EnterWander(worldPosition)
	self.WanderTarget = worldPosition
	self:SetState("Wander", nil)
end

function SlimeAgent:EnterReturn()
	self.WanderTarget = nil
	self.Strike = nil
	self:SetState("Return", nil)
end

function SlimeAgent:EnterNotice(player, now, combatConfig)
	self.Strike = nil
	self:SetCombatReady(false)
	self:SetState("Notice", player)
	self.NoticeUntil = now + combatConfig.NoticeSeconds
	self.NextAttackAt = math.max(self.NextAttackAt, self.NoticeUntil + combatConfig.InitialAttackDelaySeconds
		+ ((self.Slot - 1) * combatConfig.AttackStaggerSeconds))
end

function SlimeAgent:DistanceTo(worldPosition)
	return horizontalDistance(self.Position, worldPosition)
end

function SlimeAgent:_applyPose(basePosition, verticalOffset, lookDirection)
	local pivotPosition = basePosition + Vector3.new(0, self.Visual.GroundOffset + (verticalOffset or 0), 0)
	local look = horizontal(lookDirection or self.Facing)
	if look.Magnitude <= 0.001 then
		look = self.Facing.Magnitude > 0.001 and self.Facing or Vector3.new(0, 0, 1)
	else
		look = look.Unit
		self.Facing = look
	end
	local frame = CFrame.lookAt(pivotPosition, pivotPosition + look)
		* CFrame.Angles(0, math.rad(self.Config.YawOffset), 0)
	self.Model:PivotTo(frame)
end

function SlimeAgent:SetAttackPose(basePosition, verticalOffset, targetPosition)
	local grounded = Vector3.new(basePosition.X, self.Position.Y, basePosition.Z)
	local direction = horizontal(targetPosition - grounded)
	self:_applyPose(grounded, verticalOffset, direction)
end

function SlimeAgent:RestoreGroundPose(targetPosition)
	local direction = targetPosition and horizontal(targetPosition - self.Position) or self.Facing
	self:_applyPose(self.Position, 0, direction)
end

function SlimeAgent:Step(goal, speed, agents, zone, dt, faceTargetPosition)
	local requestedVelocity = CrowdSteering.Compute(self, goal, speed, agents, self.Config, dt)
	local requestedPosition = self.Position + requestedVelocity * dt
	requestedPosition = zone:ClampXZ(requestedPosition)
	local resolvedPosition = zone:ResolveMotion(self.Position, requestedPosition)
	resolvedPosition = zone:ClampXZ(resolvedPosition)

	local groundY = zone:GroundAt(resolvedPosition)
	if groundY then
		resolvedPosition = Vector3.new(resolvedPosition.X, groundY, resolvedPosition.Z)
	else
		resolvedPosition = self.Position
	end

	local previous = self.Position
	self.Position = resolvedPosition
	local actualHorizontal = horizontal(self.Position - previous)
	local actualVelocity = dt > 0 and actualHorizontal / dt or Vector3.zero
	self.Velocity = actualVelocity

	local moving = actualHorizontal.Magnitude > 0.002
	local horizontalVelocity = horizontal(actualVelocity)
	local verticalOffset = 0
	if moving and horizontalVelocity.Magnitude > 0.08 then
		self.MoveTravel += actualHorizontal.Magnitude
		local stride = math.max(0.1, self.Config.MoveHopStrideStuds)
		local phase = (self.MoveTravel / stride) * math.pi
		verticalOffset = math.abs(math.sin(phase)) * self.Config.MoveHopHeight

		local desired
		if faceTargetPosition then
			desired = horizontal(faceTargetPosition - self.Position)
			if desired.Magnitude <= self.Config.CombatFacingDeadzone then
				desired = nil
			end
		end
		if not desired or desired.Magnitude <= 0.001 then
			desired = horizontalVelocity
		end
		if desired.Magnitude > 0.001 then
			desired = desired.Unit
			if faceTargetPosition then
				self.Facing = boundedTurn(
					self.Facing,
					desired,
					self.Config.CombatTurnSpeedDegreesPerSecond,
					dt
				)
			else
				local alpha = 1 - math.exp(-self.Config.TurnSpeed * dt)
				local facing = self.Facing:Lerp(desired, alpha)
				if facing.Magnitude > 0.001 then
					self.Facing = facing.Unit
				end
			end
		end
	else
		self.MoveTravel = 0
		self.IdleClock += dt
		local phase = self.IdleClock * self.Config.IdleBobCyclesPerSecond * math.pi * 2
		verticalOffset = (0.5 + 0.5 * math.sin(phase)) * self.Config.IdleBobHeight
		if faceTargetPosition then
			local desired = horizontal(faceTargetPosition - self.Position)
			if desired.Magnitude > self.Config.CombatFacingDeadzone then
				self.Facing = boundedTurn(
					self.Facing,
					desired.Unit,
					self.Config.CombatTurnSpeedDegreesPerSecond,
					dt
				)
			end
		end
	end

	if self.Visual.Animation then
		self.Visual.Animation:SetMoving(moving)
	end
	self:_applyPose(self.Position, verticalOffset, self.Facing)
end

function SlimeAgent:FaceToward(worldPosition, dt)
	local desired = horizontal(worldPosition - self.Position)
	if desired.Magnitude <= self.Config.CombatFacingDeadzone then
		return
	end
	self.Facing = boundedTurn(
		self.Facing,
		desired.Unit,
		self.Config.CombatTurnSpeedDegreesPerSecond,
		dt
	)
	self:_applyPose(self.Position, 0, self.Facing)
end

function SlimeAgent:IsFacing(worldPosition, toleranceDegrees)
	local desired = horizontal(worldPosition - self.Position)
	if desired.Magnitude <= self.Config.CombatFacingDeadzone then
		return true
	end
	local current = horizontal(self.Facing)
	if current.Magnitude <= 0.001 then
		return false
	end
	local dot = math.clamp(current.Unit:Dot(desired.Unit), -1, 1)
	local tolerance = math.rad(math.max(0, toleranceDegrees or 0))
	return dot >= math.cos(tolerance)
end

function SlimeAgent:Destroy()
	self.TargetPlayer = nil
	self.TargetKind = nil
	self.TargetKey = nil
	self.TargetPetSlot = nil
	self.TargetPetUid = nil
	self.NextTargetReviewAt = 0
	self.TargetPlayerHitSerialAtAcquire = 0
	self.WanderTarget = nil
	self.FormationSlot = nil
	self.Strike = nil
	self:SetCombatReady(false)
	if self.Model then
		self.Model:SetAttribute("TargetType", "None")
		self.Model:SetAttribute("TargetPetSlot", 0)
		self.Model:SetAttribute("TargetPetUid", "")
	end
	SlimeNavigation.Reset(self)
end

return SlimeAgent
