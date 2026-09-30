local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetCombat)

local Formation = {}

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function rotateY(vector, radians)
	local c, s = math.cos(radians), math.sin(radians)
	return Vector3.new(vector.X * c - vector.Z * s, 0, vector.X * s + vector.Z * c)
end

local function sortedSlots(values)
	local slots = {}
	for slot in pairs(values or {}) do
		table.insert(slots, slot)
	end
	table.sort(slots)
	return slots
end

function Formation.attackersForTarget(assignments, slimeSlot)
	local slots = {}
	for petSlot, assignedSlimeSlot in pairs(assignments or {}) do
		if assignedSlimeSlot == slimeSlot then
			table.insert(slots, petSlot)
		end
	end
	table.sort(slots)
	return slots
end

function Formation.combatCenter(assignments, targetPositions)
	local seen = {}
	local sum = Vector3.zero
	local count = 0
	for _, slimeSlot in pairs(assignments or {}) do
		local position = targetPositions and targetPositions[slimeSlot]
		if position and not seen[slimeSlot] then
			seen[slimeSlot] = true
			sum += position
			count += 1
		end
	end
	if count <= 1 then
		return nil
	end
	return sum / count
end

function Formation.baseDirection(slimePosition, playerPosition)
	local direction = horizontal(playerPosition - slimePosition)
	if direction.Magnitude <= 0.001 then
		return Vector3.new(0, 0, 1)
	end
	return direction.Unit
end

function Formation.outerDirection(slimePosition, playerPosition, combatCenter)
	if combatCenter then
		local outward = horizontal(slimePosition - combatCenter)
		if outward.Magnitude >= Config.OuterDirectionMinStuds then
			return outward.Unit
		end
	end
	return Formation.baseDirection(slimePosition, playerPosition)
end

local function attackerAngle(index, count)
	if count <= 1 then
		return 0
	end
	if count == 2 then
		return math.rad(index == 1 and -Config.PairHalfAngleDegrees or Config.PairHalfAngleDegrees)
	end
	if count == 3 then
		local angles = { -90, 0, 90 }
		return math.rad(angles[index] or 0)
	end
	if count == 4 then
		-- Four-way focus fire surrounds the last slime without placing a pet
		-- directly on the Player/slime center line.
		local angles = { -135, -45, 45, 135 }
		return math.rad(angles[index] or 0)
	end

	-- Future-proof fallback if party limits ever grow beyond four.
	return ((index - 0.5) / count) * (math.pi * 2) - math.pi
end

function Formation.goal(petSlot, attackerSlots, slimePosition, baseDirection)
	local direction = baseDirection
	if not direction or direction.Magnitude <= 0.001 then
		direction = Vector3.new(0, 0, 1)
	else
		direction = direction.Unit
	end

	local index = table.find(attackerSlots, petSlot) or 1
	direction = rotateY(direction, attackerAngle(index, math.max(1, #attackerSlots)))
	return slimePosition + direction * Config.AttackRadiusStuds
end

function Formation.resolveSpacing(goals, targetPositionsByPet)
	local resolved = {}
	local original = {}
	for slot, goal in pairs(goals or {}) do
		resolved[slot] = goal
		original[slot] = goal
	end

	local slots = sortedSlots(resolved)
	for _ = 1, Config.CombatSpacingPasses do
		for firstIndex = 1, #slots - 1 do
			local firstSlot = slots[firstIndex]
			for secondIndex = firstIndex + 1, #slots do
				local secondSlot = slots[secondIndex]
				local delta = horizontal(resolved[firstSlot] - resolved[secondSlot])
				local distance = delta.Magnitude
				if distance < Config.MinCombatPetSpacingStuds then
					local direction
					if distance > 0.001 then
						direction = delta.Unit
					else
						local sign = ((firstSlot + secondSlot) % 2 == 0) and 1 or -1
						direction = Vector3.new(sign, 0, 0)
					end
					local correction = (Config.MinCombatPetSpacingStuds - distance) * 0.5
					resolved[firstSlot] += direction * correction
					resolved[secondSlot] -= direction * correction
				end
			end
		end
	end

	for _, slot in ipairs(slots) do
		local raw = original[slot]
		local offset = horizontal(resolved[slot] - raw)
		if offset.Magnitude > Config.CombatSpacingMaxCorrectionStuds then
			resolved[slot] = raw + offset.Unit * Config.CombatSpacingMaxCorrectionStuds
		end

		local targetPosition = targetPositionsByPet and targetPositionsByPet[slot]
		if targetPosition then
			local radial = horizontal(resolved[slot] - targetPosition)
			if radial.Magnitude < Config.AttackRadiusStuds then
				local fallback = horizontal(raw - targetPosition)
				local direction = radial.Magnitude > 0.001 and radial.Unit
					or (fallback.Magnitude > 0.001 and fallback.Unit)
					or Vector3.new(0, 0, 1)
				resolved[slot] = targetPosition + direction * Config.AttackRadiusStuds
			end
		end
	end

	return resolved
end

function Formation.directionYaw(direction)
	direction = horizontal(direction)
	if direction.Magnitude <= 0.001 then
		return nil
	end
	direction = direction.Unit
	return math.atan2(-direction.X, -direction.Z)
end

function Formation.facingYaw(fromPosition, targetPosition)
	return Formation.directionYaw(targetPosition - fromPosition)
end

return Formation
