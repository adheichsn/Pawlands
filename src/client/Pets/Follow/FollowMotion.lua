local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetFollow)

local FollowMotion = {}
local function alpha(speed, dt)
	return 1 - math.exp(-speed * dt)
end

local function turnYaw(currentYaw, targetYaw, dt, maxDegreesPerSecond)
	local turn = (targetYaw - currentYaw + math.pi) % (2 * math.pi) - math.pi
	if maxDegreesPerSecond and maxDegreesPerSecond > 0 then
		local maxTurn = math.rad(maxDegreesPerSecond) * dt
		return currentYaw + math.clamp(turn, -maxTurn, maxTurn)
	end
	return currentYaw + turn * alpha(Config.TurnSpeed, dt)
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
		visual.MotionSpeed = 0
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

	-- Combat/retarget/return profiles can opt into acceleration limiting. The
	-- existing exponential follow remains the desired path; this only prevents a
	-- recovery hold from instantly jumping to the transition speed cap.
	local maxAcceleration = motionProfile and motionProfile.MaxHorizontalAcceleration
	local desiredDelta = Vector3.new(position.X - previous.X, 0, position.Z - previous.Z)
	if not recall and maxAcceleration and maxAcceleration > 0 then
		local desiredSpeed = desiredDelta.Magnitude / math.max(dt, 0.001)
		local currentSpeed = math.max(0, tonumber(visual.MotionSpeed) or 0)
		local maxSpeedChange = maxAcceleration * dt
		local nextSpeed = currentSpeed + math.clamp(
			desiredSpeed - currentSpeed,
			-maxSpeedChange,
			maxSpeedChange
		)
		if desiredDelta.Magnitude > 0.001 then
			local step = math.min(desiredDelta.Magnitude, math.max(0, nextSpeed) * dt)
			local bounded = desiredDelta.Unit * step
			position = Vector3.new(previous.X + bounded.X, position.Y, previous.Z + bounded.Z)
		end
		visual.MotionSpeed = nextSpeed
	else
		visual.MotionSpeed = desiredDelta.Magnitude / math.max(dt, 0.001)
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
	local turnSpeed = motionProfile and motionProfile.TurnSpeedDegreesPerSecond
	visual.Yaw = turnYaw(visual.Yaw, yaw, dt, turnSpeed)
	local time = clock + visual.Phase
	local suppressAmbientMotion = motionProfile and motionProfile.SuppressAmbientMotion == true
	local bob = 0
	local pitch = 0
	if not suppressAmbientMotion then
		bob = (math.sin(time * Config.IdleFrequency) + 1) * Config.IdleBob
		if flying then
			bob += math.sin(time * Config.FlyFrequency) * Config.FlyBob
			pitch = Config.FlyLean * visual.Walk
		else
			bob += math.abs(math.sin(time * Config.HopFrequency)) * Config.HopHeight * visual.Walk
			pitch = math.cos(time * Config.HopFrequency) * Config.WalkLean * visual.Walk
		end
	end
	local presentationPitch = math.rad(motionProfile and motionProfile.PresentationPitchDegrees or 0)
	local presentationRoll = math.rad(motionProfile and motionProfile.PresentationRollDegrees or 0)
	-- Preserve the existing movement rotation order. Authored yaw calibration stays
	-- last for normal follow/attack pitch; KO tilt is then applied on the visible
	-- artwork axes, matching Pawtopia's frozen-world-rotation down presentation.
	presentationOffset = presentationOffset or Vector3.zero
	local frame = CFrame.new(position + Vector3.new(0, bob, 0) + presentationOffset)
		* CFrame.Angles(0, visual.Yaw, 0)
		* CFrame.Angles(pitch, 0, 0)
		* CFrame.Angles(0, math.rad(visual.Definition.YawOffset or 0), 0)
		* CFrame.Angles(presentationPitch, 0, presentationRoll)
	visual.Model:PivotTo(frame)
	return true
end

return FollowMotion
