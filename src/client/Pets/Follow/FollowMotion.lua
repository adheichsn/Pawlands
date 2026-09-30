local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetFollow)

local FollowMotion = {}
local function alpha(speed, dt)
	return 1 - math.exp(-speed * dt)
end

function FollowMotion.step(visual, target, root, targetYaw, dt, clock, probe, recall, presentationOffset, motionProfile)
	local targetY = probe:Height(target.X, target.Z, root.Position.Y)
	if not targetY then
		-- Recover near the player at an edge or across an unloaded gap.
		target = root.Position
		targetY = probe:Height(target.X, target.Z, root.Position.Y)
		recall = true
	end
	if not targetY then
		return false
	end
	local flying = visual.Definition.Movement == "Flying"
	local height = visual.GroundOffset + Config.GroundClearance
	if flying then
		height += visual.Definition.HoverHeight or 2
	end
	local goal = Vector3.new(target.X, targetY + height, target.Z)
	local previous = visual.Position
	if not previous or recall or (previous - goal).Magnitude > Config.RecallDistance then
		previous = goal
		visual.Walk = 0
		visual.Yaw = nil
	end
	local followSpeed = motionProfile and motionProfile.FollowSpeed or Config.FollowSpeed
	local position = previous:Lerp(goal, alpha(followSpeed, dt))
	local maxHorizontalSpeed = motionProfile and motionProfile.MaxHorizontalSpeed
	if not recall and maxHorizontalSpeed ~= nil then
		local delta = Vector3.new(position.X - previous.X, 0, position.Z - previous.Z)
		local maxStep = math.max(0, maxHorizontalSpeed) * dt
		if delta.Magnitude > maxStep and delta.Magnitude > 0.001 then
			local bounded = delta.Unit * maxStep
			position = Vector3.new(previous.X + bounded.X, position.Y, previous.Z + bounded.Z)
		end
	end
	local groundY = probe:Height(position.X, position.Z, root.Position.Y)
	if not groundY then
		position, groundY = goal, targetY
	end
	-- Sample beneath the current position; step up without sinking into a ramp.
	local floorY = groundY + height
	local smoothY = previous.Y + (floorY - previous.Y) * alpha(Config.VerticalSpeed, dt)
	position = Vector3.new(position.X, math.max(floorY, smoothY), position.Z)
	local delta = position - previous
	local speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / math.max(dt, 0.001)
	local walking = speed > Config.MoveThreshold and 1 or 0
	visual.Walk += (walking - visual.Walk) * alpha(Config.WalkBlendSpeed, dt)
	visual.Position = position

	local yaw = targetYaw
	visual.Yaw = visual.Yaw or yaw
	local turn = (yaw - visual.Yaw + math.pi) % (2 * math.pi) - math.pi
	visual.Yaw += turn * alpha(Config.TurnSpeed, dt)
	local time = clock + visual.Phase
	local bob = (math.sin(time * Config.IdleFrequency) + 1) * Config.IdleBob
	local pitch = 0
	if flying then
		bob += math.sin(time * Config.FlyFrequency) * Config.FlyBob
		pitch = Config.FlyLean * visual.Walk
	else
		bob += math.abs(math.sin(time * Config.HopFrequency)) * Config.HopHeight * visual.Walk
		pitch = math.cos(time * Config.HopFrequency) * Config.WalkLean * visual.Walk
	end
	-- Calibrate the artwork last so pitch stays on the movement's right axis.
	presentationOffset = presentationOffset or Vector3.zero
	local frame = CFrame.new(position + Vector3.new(0, bob, 0) + presentationOffset)
		* CFrame.Angles(0, visual.Yaw, 0) * CFrame.Angles(pitch, 0, 0)
		* CFrame.Angles(0, math.rad(visual.Definition.YawOffset or 0), 0)
	visual.Model:PivotTo(frame)
	return true
end

return FollowMotion
