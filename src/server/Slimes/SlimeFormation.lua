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

-- The combat square keeps the heading captured at engagement. Player velocity
-- no longer rotates the formation every frame, which previously made slimes
-- orbit and cross through one another when the Player simply moved forward.
function SlimeFormation.ResolveHeading(root, previousHeading)
	if previousHeading and previousHeading.Magnitude > 0.001 then
		return horizontal(previousHeading).Unit
	end
	return fallbackForward(root)
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
	local anchor = root.Position
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

-- Groups are tiny (maximum four), so exhaustive assignment is cheap. Assignment
-- is only repeated when membership/target changes; active combat does not churn
-- slots every few tenths of a second.
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
