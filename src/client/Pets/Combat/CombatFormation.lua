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

function Formation.baseDirection(slimePosition, playerPosition)
	local direction = horizontal(playerPosition - slimePosition)
	if direction.Magnitude <= 0.001 then
		return Vector3.new(0, 0, 1)
	end
	return direction.Unit
end

function Formation.goal(petSlot, attackerSlots, slimePosition, baseDirection)
	local direction = baseDirection
	if not direction or direction.Magnitude <= 0.001 then
		direction = Vector3.new(0, 0, 1)
	else
		direction = direction.Unit
	end

	local angle = 0
	if #attackerSlots >= 2 then
		local index = table.find(attackerSlots, petSlot) or 1
		angle = math.rad(index == 1 and -Config.PairHalfAngleDegrees or Config.PairHalfAngleDegrees)
	end
	direction = rotateY(direction, angle)
	return slimePosition + direction * Config.AttackRadiusStuds
end

function Formation.facingYaw(fromPosition, targetPosition)
	local direction = horizontal(targetPosition - fromPosition)
	if direction.Magnitude <= 0.001 then
		return nil
	end
	direction = direction.Unit
	return math.atan2(-direction.X, -direction.Z)
end

return Formation
