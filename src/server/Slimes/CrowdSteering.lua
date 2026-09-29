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

-- Pawtopia-style separation is a bounded destination correction, not an
-- unbounded velocity force. This keeps slimes apart without making a formation
-- member visibly flee or orbit just because several neighbors are nearby.
function CrowdSteering.ResolveGoal(agent, goal, agents, config)
	local correction = Vector3.zero
	for _, other in ipairs(agents) do
		if other ~= agent and other.Model.Parent then
			local delta = horizontal(goal - other.Position)
			local distance = delta.Magnitude
			local required = config.SeparationRadius
			if distance < required then
				local direction = distance > 0.001 and delta.Unit or fallbackDirection(agent, other)
				correction += direction * ((required - distance) * config.SeparationCorrectionStrength)
			end
		end
	end

	local magnitude = correction.Magnitude
	if magnitude <= 0.001 then
		return goal, 0
	end
	if magnitude > config.SeparationMaxCorrectionStuds then
		correction = correction.Unit * config.SeparationMaxCorrectionStuds
		magnitude = config.SeparationMaxCorrectionStuds
	end
	return goal + correction, magnitude
end

function CrowdSteering.Compute(agent, goal, speed, agents, config, dt)
	local correctedGoal, correction = CrowdSteering.ResolveGoal(agent, goal, agents, config)
	local toGoal = horizontal(correctedGoal - agent.Position)
	local desired = Vector3.zero
	if toGoal.Magnitude > config.ArrivalRadius and speed > 0 then
		desired = toGoal.Unit * speed
	elseif correction > config.SeparationRepositionThreshold then
		desired = toGoal.Magnitude > 0.001 and toGoal.Unit * config.IdleSeparationSpeed or Vector3.zero
	end

	local maxSpeed = math.max(speed, correction > config.SeparationRepositionThreshold and config.IdleSeparationSpeed or 0)
	desired = clampMagnitude(desired, maxSpeed)
	local alpha = 1 - math.exp(-config.Acceleration * dt)
	local velocity = horizontal(agent.Velocity):Lerp(desired, alpha)
	if desired.Magnitude < 0.01 and velocity.Magnitude < 0.05 then
		velocity = Vector3.zero
	end
	return velocity
end

return CrowdSteering
