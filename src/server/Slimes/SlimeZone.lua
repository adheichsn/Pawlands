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

local function sortPoints(points)
	table.sort(points, function(a, b)
		local ap, bp = a.WorldPosition, b.WorldPosition
		if math.abs(ap.X - bp.X) > 0.01 then
			return ap.X < bp.X
		end
		if math.abs(ap.Z - bp.Z) > 0.01 then
			return ap.Z < bp.Z
		end
		return ap.Y < bp.Y
	end)
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
	sortPoints(points)
	if #points == 0 then
		return nil, "CombatZone has no Attachment children named " .. config.SpawnPointName .. "."
	end

	local rayParams = RaycastParams.new()
	rayParams.IgnoreWater = true
	rayParams.RespectCanCollide = true
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local self = setmetatable({
		Config = config,
		Part = zonePart,
		Points = points,
		RuntimeFolder = runtimeFolder,
		RayParams = rayParams,
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
	self.RayParams.FilterDescendantsInstances = excluded
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
	local result = Workspace:Raycast(origin, Vector3.new(0, -self.Config.GroundRayDistance, 0), self.RayParams)
	if not result or result.Normal.Y < self.Config.MinGroundNormalY then
		return nil
	end
	return result.Position.Y
end

-- Farthest-point sampling uses distinct Studio attachments and maximizes the
-- initial spacing between spawned slimes instead of selecting adjacent points.
function SlimeZone:GetSpreadSpawnPoints(count)
	count = math.min(count, #self.Points)
	if count <= 0 then
		return {}
	end

	local selected = { self.Points[1] }
	local used = { [self.Points[1]] = true }
	while #selected < count do
		local best, bestDistance = nil, -math.huge
		for _, candidate in ipairs(self.Points) do
			if not used[candidate] then
				local nearest = math.huge
				for _, existing in ipairs(selected) do
					local delta = candidate.WorldPosition - existing.WorldPosition
					local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
					nearest = math.min(nearest, horizontal)
				end
				if nearest > bestDistance then
					best, bestDistance = candidate, nearest
				end
			end
		end
		if not best then
			break
		end
		used[best] = true
		table.insert(selected, best)
	end
	return selected
end

return SlimeZone
