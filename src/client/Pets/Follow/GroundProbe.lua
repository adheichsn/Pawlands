local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetFollow)
local probeSize = Vector3.new(Config.GroundProbeWidth, Config.GroundProbeThickness, Config.GroundProbeWidth)

local GroundProbe = {}
GroundProbe.__index = GroundProbe

function GroundProbe.new(visualFolder)
	local params = RaycastParams.new()
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return setmetatable({ Params = params, VisualFolder = visualFolder }, GroundProbe)
end

function GroundProbe:Refresh(skipPlayer)
	local excluded = { self.VisualFolder }
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= skipPlayer and player.Character then
			table.insert(excluded, player.Character)
		end
	end
	self.Params.ExcludeInstances = excluded
end

function GroundProbe:Height(x, z, rootY)
	-- A point ray falls through plank seams and triggers an unnecessary recall.
	-- Cast a thin support area; its bottom starts at the previous ray height.
	local origin = CFrame.new(x, rootY + Config.RayHeight + probeSize.Y / 2, z)
	local hit = Workspace:Blockcast(origin, probeSize, Vector3.new(0, -Config.RayDistance, 0), self.Params)
	if not hit or hit.Normal.Y < Config.MinGroundNormalY then
		return nil
	end
	if rootY - hit.Position.Y > Config.MaxGroundDrop then
		return nil
	end
	return hit.Position.Y
end

return GroundProbe
