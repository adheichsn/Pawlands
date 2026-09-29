local CrowdSteering = require(script.Parent.CrowdSteering)

local SlimeAgent = {}
SlimeAgent.__index = SlimeAgent

local function horizontalDistance(a, b)
	local delta = a - b
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

function SlimeAgent.new(slot, definition, visual, spawnPoint, config)
	local position = spawnPoint.WorldPosition
	local self = setmetatable({
		Slot = slot,
		Definition = definition,
		Visual = visual,
		Model = visual.Model,
		Config = config,
		Position = position,
		Velocity = Vector3.zero,
		Facing = Vector3.new(0, 0, 1),
		State = "Idle",
		TargetPlayer = nil,
		WanderPoint = nil,
		HomePoint = spawnPoint,
		IdleUntil = 0,
	}, SlimeAgent)
	return self
end

function SlimeAgent:SetState(state, targetPlayer)
	if self.State == state and self.TargetPlayer == targetPlayer then
		return
	end
	self.State = state
	self.TargetPlayer = targetPlayer
	self.Model:SetAttribute("SlimeState", state)
	self.Model:SetAttribute("TargetUserId", targetPlayer and targetPlayer.UserId or 0)
	if state == "Chase" then
		self.WanderPoint = nil
	end
end

function SlimeAgent:EnterIdle(now, randomObject)
	self.WanderPoint = nil
	self:SetState("Idle", nil)
	self.IdleUntil = now + randomObject:NextNumber(self.Config.IdleMinSeconds, self.Config.IdleMaxSeconds)
end

function SlimeAgent:EnterWander(point)
	self.WanderPoint = point
	self:SetState("Wander", nil)
end

function SlimeAgent:DistanceTo(worldPosition)
	return horizontalDistance(self.Position, worldPosition)
end

function SlimeAgent:Step(goal, speed, agents, zone, dt)
	local velocity = CrowdSteering.Compute(self, goal, speed, agents, self.Config, dt)
	local nextPosition = self.Position + velocity * dt
	nextPosition = zone:ClampXZ(nextPosition)
	local groundY = zone:GroundAt(nextPosition)
	if groundY then
		nextPosition = Vector3.new(nextPosition.X, groundY, nextPosition.Z)
	else
		nextPosition = self.Position
		velocity = Vector3.zero
	end

	self.Position = nextPosition
	self.Velocity = velocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	if horizontal.Magnitude > 0.08 then
		local desired = horizontal.Unit
		local alpha = 1 - math.exp(-self.Config.TurnSpeed * dt)
		local facing = self.Facing:Lerp(desired, alpha)
		if facing.Magnitude > 0.001 then
			self.Facing = facing.Unit
		end
	end

	local pivotPosition = self.Position + Vector3.new(0, self.Visual.GroundOffset, 0)
	local look = self.Facing.Magnitude > 0.001 and self.Facing or Vector3.new(0, 0, 1)
	local frame = CFrame.lookAt(pivotPosition, pivotPosition + look)
		* CFrame.Angles(0, math.rad(self.Config.YawOffset), 0)
	self.Model:PivotTo(frame)
end

function SlimeAgent:Destroy()
	self.TargetPlayer = nil
	self.WanderPoint = nil
end

return SlimeAgent
