local DirectionResolver = {}

-- Direction is resolved against the character's current facing so this patch does not
-- replace Roblox camera/rotation behavior. A future camera-facing movement pass can
-- change orientation independently without rewriting the animation mapping.
function DirectionResolver.Resolve(root, moveDirection)
	if not root or moveDirection.Magnitude <= 0.001 then
		return "Forward"
	end

	local localDirection = root.CFrame:VectorToObjectSpace(moveDirection.Unit)
	local forward = -localDirection.Z
	local right = localDirection.X
	local angle = math.deg(math.atan2(right, forward))

	if angle >= -22.5 and angle < 22.5 then
		return "Forward"
	elseif angle >= 22.5 and angle < 67.5 then
		return "FrontRight"
	elseif angle >= 67.5 and angle < 112.5 then
		return "Right"
	elseif angle >= 112.5 and angle < 157.5 then
		return "BackRight"
	elseif angle >= 157.5 or angle < -157.5 then
		return "Back"
	elseif angle >= -157.5 and angle < -112.5 then
		return "BackLeft"
	elseif angle >= -112.5 and angle < -67.5 then
		return "Left"
	end

	return "FrontLeft"
end

return DirectionResolver
