local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local SlimeZone = {}
SlimeZone.__index = SlimeZone

local function resolvePath(root, names)
	local node = root
	for _, name in ipairs(names) do
		node = node:FindFirstChild(name)
		if not node then
			return nil
		end
	end
	return node
end

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function sortPointsAroundCenter(points)
	if #points < 3 then
		return
	end
	local center = Vector3.zero
	for _, point in ipairs(points) do
		center += point.WorldPosition
	end
	center /= #points
	table.sort(points, function(a, b)
		local ap, bp = a.WorldPosition, b.WorldPosition
		local angleA = math.atan2(ap.Z - center.Z, ap.X - center.X)
		local angleB = math.atan2(bp.Z - center.Z, bp.X - center.X)
		return angleA < angleB
	end)
end

local function newParams()
	local params = RaycastParams.new()
	params.IgnoreWater = true
	params.RespectCanCollide = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	return params
end

function SlimeZone.new(config, runtimeFolder)
	local zonePart = resolvePath(Workspace, config.ZonePath)
	if not zonePart or not zonePart:IsA("BasePart") then
		return nil, "Missing Studio CombatZone at Workspace/" .. table.concat(config.ZonePath, "/")
	end

	local points = {}
	for _, child in ipairs(zonePart:GetChildren()) do
		if child:IsA("Attachment") and child.Name == config.SpawnPointName then
			table.insert(points, child)
		end
	end
	sortPointsAroundCenter(points)
	if #points == 0 then
		return nil, "CombatZone has no Attachment children named " .. config.SpawnPointName .. "."
	end

	local self = setmetatable({
		Config = config,
		Part = zonePart,
		Points = points,
		RuntimeFolder = runtimeFolder,
		GroundParams = newParams(),
		ObstacleParams = newParams(),
	}, SlimeZone)
	self:RefreshGroundFilter()
	return self, nil
end

function SlimeZone:RefreshGroundFilter()
	local excluded = { self.RuntimeFolder, self.Part }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	self.GroundParams.FilterDescendantsInstances = excluded
	self.ObstacleParams.FilterDescendantsInstances = excluded
end

function SlimeZone:Contains(worldPosition, padding)
	local localPosition = self.Part.CFrame:PointToObjectSpace(worldPosition)
	local half = self.Part.Size * 0.5
	local inset = padding or 0
	return math.abs(localPosition.X) <= math.max(0, half.X - inset)
		and math.abs(localPosition.Z) <= math.max(0, half.Z - inset)
end

function SlimeZone:ClampXZ(worldPosition)
	local localPosition = self.Part.CFrame:PointToObjectSpace(worldPosition)
	local half = self.Part.Size * 0.5
	local padding = self.Config.ZonePadding
	local x = math.clamp(localPosition.X, -math.max(0, half.X - padding), math.max(0, half.X - padding))
	local z = math.clamp(localPosition.Z, -math.max(0, half.Z - padding), math.max(0, half.Z - padding))
	local clamped = self.Part.CFrame:PointToWorldSpace(Vector3.new(x, localPosition.Y, z))
	return Vector3.new(clamped.X, worldPosition.Y, clamped.Z)
end

function SlimeZone:GroundAt(worldPosition)
	local originY = math.max(worldPosition.Y, self.Part.Position.Y) + self.Config.GroundRayHeight
	local origin = Vector3.new(worldPosition.X, originY, worldPosition.Z)
	local result = Workspace:Raycast(origin, Vector3.new(0, -self.Config.GroundRayDistance, 0), self.GroundParams)
	if not result or result.Normal.Y < self.Config.MinGroundNormalY then
		return nil
	end
	return result.Position.Y
end

function SlimeZone:GroundPoint(worldPosition)
	local clamped = self:ClampXZ(worldPosition)
	local groundY = self:GroundAt(clamped)
	if not groundY then
		return nil
	end
	return Vector3.new(clamped.X, groundY, clamped.Z)
end

function SlimeZone:ProbeObstacle(fromPosition, toPosition, maximumDistance)
	local delta = horizontal(toPosition - fromPosition)
	local distance = delta.Magnitude
	if distance <= 0.05 then
		return nil
	end
	local castDistance = math.min(distance, maximumDistance or distance)
	local direction = delta.Unit
	local origin = fromPosition + Vector3.new(0, self.Config.ObstacleProbeHeight, 0)
	local frame = CFrame.lookAt(origin, origin + direction)
	return Workspace:Blockcast(
		frame,
		self.Config.ObstacleProbeSize,
		direction * castDistance,
		self.ObstacleParams
	)
end

function SlimeZone:HasClearRoute(fromPosition, toPosition, maximumDistance)
	return self:ProbeObstacle(fromPosition, toPosition, maximumDistance) == nil
end

-- The slime rigs are moved kinematically with PivotTo, so Roblox collision alone
-- cannot stop them clipping through props. This final sweep prevents a crowd or
-- navigation correction from stepping through solid map geometry between ticks.
function SlimeZone:ResolveMotion(fromPosition, desiredPosition)
	local delta = horizontal(desiredPosition - fromPosition)
	local distance = delta.Magnitude
	if distance <= 0.001 then
		return desiredPosition
	end

	local hit = self:ProbeObstacle(fromPosition, desiredPosition, distance)
	if not hit then
		return desiredPosition
	end

	local direction = delta.Unit
	local safeDistance = math.max(0, hit.Distance - self.Config.ObstacleSkin)
	local safe = fromPosition + direction * safeDistance
	local normal = horizontal(hit.Normal)
	if normal.Magnitude <= 0.001 then
		return safe
	end

	-- Remove only the component that pushes into the obstacle, leaving a small
	-- tangential slide so separation steering does not produce sticky corners.
	normal = normal.Unit
	local remaining = delta - direction * safeDistance
	local intoSurface = remaining:Dot(normal)
	local slide = remaining
	if intoSurface < 0 then
		slide -= normal * intoSurface
	end
	if slide.Magnitude <= 0.05 then
		return safe
	end

	local slideTarget = safe + slide
	if self:ProbeObstacle(safe, slideTarget, slide.Magnitude) then
		return safe
	end
	return slideTarget
end

function SlimeZone:GetBoundaryCenter()
	if #self.Points == 0 then
		return self.Part.Position
	end
	local center = Vector3.zero
	for _, point in ipairs(self.Points) do
		center += point.WorldPosition
	end
	return center / #self.Points
end

-- Studio Points describe the outer combat boundary. Spawn positions are evenly
-- distributed around that boundary and then inset toward the center.
function SlimeZone:GetInsetSpawnPositions(count, seed)
	count = math.min(math.max(0, math.floor(count or 0)), #self.Points)
	if count <= 0 then
		return {}
	end

	local center = self:GetBoundaryCenter()
	local alpha = math.clamp(self.Config.SpawnBoundaryInsetAlpha or 0.55, 0, 1)
	local rotation = math.max(0, math.floor(seed or 0)) % #self.Points
	local positions = table.create(count)

	for index = 1, count do
		local baseIndex = math.floor(((index - 1) * #self.Points) / count)
		local pointIndex = ((baseIndex + rotation) % #self.Points) + 1
		local boundaryPosition = self.Points[pointIndex].WorldPosition
		positions[index] = center:Lerp(boundaryPosition, alpha)
	end
	return positions
end

return SlimeZone
