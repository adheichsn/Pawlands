local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetFollow)
local Observer = require(script.Parent.PartyObserver)
local Formation = require(script.Parent.Follow.Formation)
local GroundProbe = require(script.Parent.Follow.GroundProbe)
local VisualFactory = require(script.Parent.Follow.VisualFactory)
local Motion = require(script.Parent.Follow.FollowMotion)

local PetFollowController = {}
local stopCurrent

function PetFollowController.Start()
	if stopCurrent then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = Config.VisualFolderName
	folder.Parent = Workspace
	local probe = GroundProbe.new(folder)
	local entries, warnings = {}, {}
	local function remove(player)
		if entries[player] then
			VisualFactory.destroyAll(entries[player].Visuals)
			entries[player] = nil
		end
		probe:Refresh(player)
	end
	local stopObserver = Observer.Start(function(player, party, character)
		remove(player)
		entries[player] = { Party = party, Character = character, Visuals = {}, RetryAt = 0 }
		probe:Refresh()
	end, remove)

	local renderConnection = RunService.PreRender:Connect(function(frameDt)
		if frameDt <= 0 then
			return
		end
		local dt, clock = math.min(frameDt, 0.1), os.clock()
		local localCharacter = Players.LocalPlayer.Character
		local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
		for player, entry in pairs(entries) do
			local character = entry.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
			local visible = root and root:IsA("BasePart") and root:IsDescendantOf(Workspace)
				and humanoid and humanoid.Health > 0
			if visible and player ~= Players.LocalPlayer and localRoot then
				visible = (root.Position - localRoot.Position).Magnitude <= Config.RenderDistance
			end
			if not visible then
				for _, visual in pairs(entry.Visuals) do
					VisualFactory.hide(visual)
				end
				entry.LastPosition = nil
				continue
			end
			if clock >= entry.RetryAt then
				entry.RetryAt = clock + Config.AssetRetrySeconds
				for slot, id in ipairs(entry.Party) do
					if not entry.Visuals[slot] then
						local visual, reason = VisualFactory.create(id, player.UserId, slot)
						entry.Visuals[slot] = visual
						if not visual and not warnings[id] then
							warnings[id] = true
							warn("[Pawlands Pets] " .. tostring(reason))
						end
					end
				end
			end
			local footprint = 0
			for _, visual in pairs(entry.Visuals) do
				footprint = math.max(footprint, visual.Footprint + Config.ModelPadding)
			end
			local spacing, depth = math.max(Config.Spacing, footprint), math.max(Config.RowDepth, footprint)
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = flat.Magnitude > 0.001 and flat.Unit or Vector3.new(0, 0, -1)
			local frame = CFrame.lookAt(root.Position, root.Position + flat)
			local yaw = math.atan2(-flat.X, -flat.Z)
			local recall = entry.LastPosition and (root.Position - entry.LastPosition).Magnitude > Config.TeleportDistance
			entry.LastPosition = root.Position
			for slot, visual in pairs(entry.Visuals) do
				local x, z = Formation.slot(slot, #entry.Party, spacing, depth, Config.FirstRow)
				local target = frame:PointToWorldSpace(Vector3.new(x, 0, z))
				if Motion.step(visual, target, root, yaw, dt, clock, probe, recall) then
					visual.Model.Parent = folder
				else
					VisualFactory.hide(visual)
				end
			end
		end
	end)
	stopCurrent = function()
		renderConnection:Disconnect()
		stopObserver()
		folder:Destroy()
	end
end

function PetFollowController.Stop()
	if stopCurrent then
		local stop = stopCurrent
		stopCurrent = nil
		stop()
	end
end

return PetFollowController
