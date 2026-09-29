local PlayerHitboxResolver = {}

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function contactRadius(model)
	local ok, _, size = pcall(model.GetBoundingBox, model)
	if not ok then
		return 1.25
	end
	return math.clamp(math.max(size.X, size.Z) * 0.5, 0.75, 3.5)
end

local function insideVolume(rootPosition, aimDirection, targetPosition, radius, hitbox)
	local delta = horizontal(targetPosition - rootPosition)
	local forward = delta:Dot(aimDirection)
	local lateral = delta - aimDirection * forward
	local lateralDistance = lateral.Magnitude
	if forward + radius < -hitbox.RearToleranceStuds
		or forward - radius > hitbox.ForwardReachStuds
		or math.max(0, lateralDistance - radius) > hitbox.HalfWidthStuds
	then
		return false, math.huge
	end
	local surfaceDistance = math.max(0, delta.Magnitude - radius)
	local lateralSurface = math.max(0, lateralDistance - radius)
	return true, surfaceDistance + lateralSurface * 0.35
end

function PlayerHitboxResolver.Resolve(playerState, aimDirection, preferredTarget, runtimeFolder, config, slimeHealth, validation)
	local root = playerState.Root
	local bestTarget = nil
	local bestScore = math.huge

	for _, candidate in ipairs(runtimeFolder:GetChildren()) do
		if candidate:IsA("Model") and validation.ValidateTarget(candidate, runtimeFolder, slimeHealth) then
			local targetPosition = candidate:GetPivot().Position
			local inside, score = insideVolume(
				root.Position,
				aimDirection,
				targetPosition,
				contactRadius(candidate),
				config.Hitbox
			)
			if inside then
				if config.RequireLineOfSight
					and not validation.HasLineOfSight(playerState.Character, candidate, runtimeFolder)
				then
					continue
				end
				if candidate == preferredTarget then
					score -= 0.20
				end
				if score < bestScore then
					bestScore = score
					bestTarget = candidate
				end
			end
		end
	end

	return bestTarget
end

return PlayerHitboxResolver
