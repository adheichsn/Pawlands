local SlimeFormation = {}

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalDistance(a, b)
	return horizontal(a - b).Magnitude
end

local function fallbackForward(root)
	local look = horizontal(root.CFrame.LookVector)
	if look.Magnitude > 0.001 then
		return look.Unit
	end
	return Vector3.new(0, 0, -1)
end

function SlimeFormation.ResolveHeading(root, previousHeading, dt, config)
	local velocity = horizontal(root.AssemblyLinearVelocity)
	local desired = nil
	if velocity.Magnitude >= config.FormationVelocityThreshold then
		desired = velocity.Unit
	elseif previousHeading and previousHeading.Magnitude > 0.001 then
		-- Keep the previous combat heading while the player is stationary. This
		-- prevents the whole square from orbiting just because the avatar rotates.
		return previousHeading.Unit
	else
		desired = fallbackForward(root)
	end

	if not previousHeading or previousHeading.Magnitude <= 0.001 then
		return desired
	end
	local alpha = 1 - math.exp(-config.FormationHeadingSmoothing * math.max(0, dt))
	local blended = previousHeading:Lerp(desired, alpha)
	return blended.Magnitude > 0.001 and blended.Unit or desired
end

local function getDirections(count, forward, right)
	if count <= 1 then
		return { forward }
	end
	if count == 2 then
		return { right, -right }
	end
	if count == 3 then
		local backRight = (-forward + right).Unit
		local backLeft = (-forward - right).Unit
		return { forward, backRight, backLeft }
	end
	-- Four slimes form the requested square footprint around the player. Viewed
	-- from above, the points are front/right/back/left (a rotated square).
	return { forward, right, -forward, -right }
end

function SlimeFormation.BuildSlots(root, count, zone, config, heading)
	local forward = heading and horizontal(heading) or fallbackForward(root)
	if forward.Magnitude <= 0.001 then
		forward = fallbackForward(root)
	else
		forward = forward.Unit
	end
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local velocity = horizontal(root.AssemblyLinearVelocity)
	local anchor = root.Position + velocity * config.FormationPredictionSeconds
	local directions = getDirections(count, forward, right)
	local slots = table.create(#directions)

	for index, direction in ipairs(directions) do
		local ideal = anchor + direction * config.EngageRadius
		local grounded = zone:GroundPoint(ideal)
		slots[index] = grounded or zone:ClampXZ(ideal)
	end
	return slots
end

local function assignmentCost(agent, slotIndex, slotPosition, config)
	local cost = horizontalDistance(agent.Position, slotPosition)
	if agent.FormationSlot and agent.FormationSlot ~= slotIndex then
		cost += config.FormationSwitchPenalty
	end
	return cost
end

-- Groups are intentionally tiny (maximum four), so evaluating every slot
-- permutation is cheap and avoids the visible crossing that a greedy assignment
-- can produce when slimes approach the player from opposite sides.
function SlimeFormation.Assign(group, slots, config)
	local count = math.min(#group, #slots)
	if count <= 0 then
		return {}
	end

	table.sort(group, function(a, b)
		return a.Slot < b.Slot
	end)

	local bestCost = math.huge
	local bestAssignment = nil
	local used = table.create(count, false)
	local current = table.create(count)

	local function search(agentIndex, runningCost)
		if runningCost >= bestCost then
			return
		end
		if agentIndex > count then
			bestCost = runningCost
			bestAssignment = table.clone(current)
			return
		end

		local agent = group[agentIndex]
		for slotIndex = 1, count do
			if not used[slotIndex] then
				used[slotIndex] = true
				current[agentIndex] = slotIndex
				search(
					agentIndex + 1,
					runningCost + assignmentCost(agent, slotIndex, slots[slotIndex], config)
				)
				used[slotIndex] = false
			end
		end
	end

	search(1, 0)
	local goals = {}
	if not bestAssignment then
		return goals
	end

	for agentIndex, slotIndex in ipairs(bestAssignment) do
		local agent = group[agentIndex]
		agent.FormationSlot = slotIndex
		goals[agent] = slots[slotIndex]
	end
	return goals
end

return SlimeFormation
