local CrowdSteering = {}

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function fallbackDirection(a, b)
	local low = math.min(a.Slot, b.Slot)
	local high = math.max(a.Slot, b.Slot)
	local seed = (low * 73 + high * 131) % 360
	local angle = math.rad(seed)
	local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
	return a.Slot < b.Slot and direction or -direction
end

local function clampMagnitude(vector, maximum)
	local magnitude = vector.Magnitude
	if magnitude <= maximum or magnitude <= 0 then
		return vector
	end
	return vector * (maximum / magnitude)
end

function CrowdSteering.Compute(agent, goal, speed, agents, config, dt)
	local toGoal = horizontal(goal - agent.Position)
	local desired = Vector3.zero
	if toGoal.Magnitude > config.ArrivalRadius and speed > 0 then
		desired = toGoal.Unit * speed
	end

	local predicted = agent.Position + horizontal(agent.Velocity) * config.SeparationLookahead
	local separation = Vector3.zero
	for _, other in ipairs(agents) do
		if other ~= agent then
			local otherPredicted = other.Position + horizontal(other.Velocity) * config.SeparationLookahead
			local away = horizontal(predicted - otherPredicted)
			local distance = away.Magnitude
			if distance < config.SeparationRadius then
				local direction = distance > 0.001 and away.Unit or fallbackDirection(agent, other)
				local normalized = 1 - math.clamp(distance / config.SeparationRadius, 0, 1)
				separation += direction * normalized * config.SeparationWeight
				if distance < config.HardSeparationRadius then
					local hard = 1 - math.clamp(distance / config.HardSeparationRadius, 0, 1)
					separation += direction * hard * config.HardSeparationWeight
				end
			end
		end
	end

	local targetVelocity = desired + separation
	local maxSpeed = math.max(speed, config.IdleSeparationSpeed)
	targetVelocity = clampMagnitude(targetVelocity, maxSpeed)

	local alpha = 1 - math.exp(-config.Acceleration * dt)
	local velocity = horizontal(agent.Velocity):Lerp(targetVelocity, alpha)
	if targetVelocity.Magnitude < 0.01 and velocity.Magnitude < 0.05 then
		velocity = Vector3.zero
	end
	return velocity
end

return CrowdSteering
