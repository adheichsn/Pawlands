local PathfindingService = game:GetService("PathfindingService")

local SlimeNavigation = {}

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalDistance(a, b)
	return horizontal(a - b).Magnitude
end

local function clearPath(nav)
	nav.Waypoints = nil
	nav.WaypointIndex = 0
	nav.PathGoal = nil
end

local function getPathWaypoint(agent, config)
	local nav = agent.Navigation
	local waypoints = nav.Waypoints
	if not waypoints then
		return nil
	end

	while nav.WaypointIndex <= #waypoints do
		local waypoint = waypoints[nav.WaypointIndex]
		if horizontalDistance(agent.Position, waypoint) <= config.PathWaypointArrivalRadius then
			nav.WaypointIndex += 1
		else
			return waypoint
		end
	end
	clearPath(nav)
	return nil
end

local function buildPath(agent, desiredGoal, zone, config, now)
	local nav = agent.Navigation
	nav.RepathAt = now + config.PathfindCooldownSeconds

	local path = PathfindingService:CreatePath({
		AgentRadius = config.PathAgentRadius,
		AgentHeight = config.PathAgentHeight,
		AgentCanJump = false,
		WaypointSpacing = config.PathWaypointSpacing,
	})
	local ok = pcall(function()
		path:ComputeAsync(agent.Position, desiredGoal)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		clearPath(nav)
		return false
	end

	local raw = path:GetWaypoints()
	local points = {}
	for index = 2, #raw do
		local point = zone:GroundPoint(raw[index].Position)
		if point then
			table.insert(points, point)
		end
	end
	if #points == 0 then
		clearPath(nav)
		return false
	end

	nav.Waypoints = points
	nav.WaypointIndex = 1
	nav.PathGoal = desiredGoal
	return true
end

local function localAvoidanceCandidate(agent, desiredGoal, hit, zone, config, now)
	local nav = agent.Navigation
	local toGoal = horizontal(desiredGoal - agent.Position)
	if toGoal.Magnitude <= 0.001 then
		return nil
	end
	local forward = toGoal.Unit
	local normal = horizontal(hit.Normal)
	if normal.Magnitude <= 0.001 then
		normal = -forward
	else
		normal = normal.Unit
	end
	local tangent = Vector3.new(-normal.Z, 0, normal.X)
	if tangent.Magnitude <= 0.001 then
		tangent = Vector3.new(-forward.Z, 0, forward.X)
	else
		tangent = tangent.Unit
	end

	local base = hit.Position
		+ normal * config.ObstacleNormalClearance
		+ forward * config.ObstacleForwardBias

	local preferredSide = nav.AvoidSide
	if now >= (nav.AvoidUntil or 0) then
		preferredSide = nil
	end

	local best, bestSide, bestScore = nil, nil, math.huge
	for _, side in ipairs({ -1, 1 }) do
		local raw = base + tangent * config.ObstacleSideStep * side
		local candidate = zone:GroundPoint(raw)
		if candidate then
			local routeDistance = horizontalDistance(agent.Position, candidate)
			local clear = zone:HasClearRoute(agent.Position, candidate, routeDistance)
			local score = horizontalDistance(candidate, desiredGoal)
			if not clear then
				score += 1000
			end
			if preferredSide and preferredSide ~= side then
				score += config.ObstacleSideSwitchPenalty
			end
			if score < bestScore then
				best = candidate
				bestSide = side
				bestScore = score
			end
		end
	end

	if best then
		nav.AvoidSide = bestSide
		nav.AvoidUntil = now + config.ObstacleAvoidanceHoldSeconds
	end
	return best
end

function SlimeNavigation.HasLineOfSight(agent, targetPosition, zone)
	local distance = horizontalDistance(agent.Position, targetPosition)
	if distance <= 0.05 then
		return true
	end
	return zone:HasClearRoute(agent.Position, targetPosition, distance)
end

function SlimeNavigation.ResolveGoal(agent, desiredGoal, zone, config, now)
	local groundedGoal = zone:GroundPoint(desiredGoal)
	if groundedGoal then
		desiredGoal = groundedGoal
	else
		desiredGoal = zone:ClampXZ(desiredGoal)
	end

	local nav = agent.Navigation
	local distance = horizontalDistance(agent.Position, desiredGoal)
	local hit = zone:ProbeObstacle(agent.Position, desiredGoal, math.min(distance, config.ObstacleProbeDistance))
	if not hit then
		nav.BlockedSince = nil
		nav.AvoidSide = nil
		nav.AvoidUntil = 0
		clearPath(nav)
		return desiredGoal
	end

	if not nav.BlockedSince then
		nav.BlockedSince = now
	end

	local waypoint = getPathWaypoint(agent, config)
	if waypoint then
		-- If the player/goal moved a long way while this route was active, wait for
		-- the repath cooldown before replacing it. This avoids path churn every tick.
		if nav.PathGoal
			and horizontalDistance(nav.PathGoal, desiredGoal) > config.PathGoalRefreshDistance
			and now >= (nav.RepathAt or 0) then
			buildPath(agent, desiredGoal, zone, config, now)
			waypoint = getPathWaypoint(agent, config) or waypoint
		end
		return waypoint
	end

	if now - nav.BlockedSince >= config.PathfindAfterBlockedSeconds
		and now >= (nav.RepathAt or 0)
		and buildPath(agent, desiredGoal, zone, config, now) then
		return getPathWaypoint(agent, config) or desiredGoal
	end

	return localAvoidanceCandidate(agent, desiredGoal, hit, zone, config, now) or agent.Position
end

function SlimeNavigation.Reset(agent)
	local nav = agent.Navigation
	if not nav then
		return
	end
	nav.BlockedSince = nil
	nav.AvoidSide = nil
	nav.AvoidUntil = 0
	nav.RepathAt = 0
	clearPath(nav)
end

return SlimeNavigation
