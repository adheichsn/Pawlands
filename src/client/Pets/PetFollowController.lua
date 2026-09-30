local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Pawlands = ReplicatedStorage:WaitForChild("Pawlands")
local Shared = Pawlands:WaitForChild("Shared")
local Config = require(Shared.Config.PetFollow)
local Observer = require(script.Parent.PartyObserver)
local Formation = require(script.Parent.Follow.Formation)
local GroundProbe = require(script.Parent.Follow.GroundProbe)
local VisualFactory = require(script.Parent.Follow.VisualFactory)
local Motion = require(script.Parent.Follow.FollowMotion)
local CombatConfig = require(Shared.Config.PetCombat)
local CombatObserver = require(script.Parent.Combat.CombatAssignmentObserver)
local CombatFormation = require(script.Parent.Combat.CombatFormation)
local CombatAttackRuntime = require(script.Parent.Combat.CombatAttackRuntime)
local CombatTransitionRuntime = require(script.Parent.Combat.CombatTransitionRuntime)
local SlimeMovementConfig = require(Shared.Config.SlimeMovement)

local PetFollowController = {}
local stopCurrent

local function slimeModelsBySlot()
	local result = {}
	local folder = Workspace:FindFirstChild(SlimeMovementConfig.RuntimeFolderName)
	if not folder or not folder:IsA("Folder") then
		return result
	end
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("Defeated") ~= true then
			local slot = tonumber(model:GetAttribute("SlimeSlot"))
			if slot then
				result[math.floor(slot)] = model
			end
		end
	end
	return result
end

function PetFollowController.Start()
	if stopCurrent then
		return
	end
	local remotes = Pawlands:WaitForChild(CombatConfig.RemoteFolderName)
	local petImpactRemote = remotes:WaitForChild(CombatConfig.AttackImpactRemoteName)
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
		entries[player] = {
			Party = party,
			Character = character,
			Visuals = {},
			RetryAt = 0,
			CombatAssignments = {},
			CombatAnchors = {},
			CombatAttackStates = {},
			CombatTransitionStates = {},
		}
		probe:Refresh()
	end, remove)

	local stopCombatObserver = CombatObserver.Start(function(player, assignments)
		local entry = entries[player]
		if entry then
			entry.CombatAssignments = assignments
		end
	end, function(player)
		local entry = entries[player]
		if entry then
			entry.CombatAssignments = {}
		end
	end)

	local renderConnection = RunService.PreRender:Connect(function(frameDt)
		if frameDt <= 0 then
			return
		end
		local dt, clock = math.min(frameDt, 0.1), os.clock()
		local localCharacter = Players.LocalPlayer.Character
		local slimesBySlot = slimeModelsBySlot()
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

			local validAssignments = {}
			local targetPositions = {}
			local targetModels = {}
			for petSlot, assignedSlimeSlot in pairs(entry.CombatAssignments or {}) do
				local slime = slimesBySlot[assignedSlimeSlot]
				if slime and slime:GetAttribute("Defeated") ~= true then
					local slimePosition = slime:GetPivot().Position
					if (slimePosition - root.Position).Magnitude <= CombatConfig.HardLeashStuds + 2 then
						validAssignments[petSlot] = assignedSlimeSlot
						targetPositions[assignedSlimeSlot] = slimePosition
						targetModels[petSlot] = slime
					end
				end
			end

			local combatCenter = CombatFormation.combatCenter(validAssignments, targetPositions)
			local activeAnchorSlots = {}
			local combatGoals = {}
			local targetPositionsByPet = {}
			for petSlot, assignedSlimeSlot in pairs(validAssignments) do
				local slimePosition = targetPositions[assignedSlimeSlot]
				local anchor = entry.CombatAnchors[assignedSlimeSlot]
				if not anchor then
					anchor = {
						Direction = CombatFormation.outerDirection(slimePosition, root.Position, combatCenter),
					}
					entry.CombatAnchors[assignedSlimeSlot] = anchor
				end
				activeAnchorSlots[assignedSlimeSlot] = true
				local attackers = CombatFormation.attackersForTarget(validAssignments, assignedSlimeSlot)
				combatGoals[petSlot] = CombatFormation.goal(petSlot, attackers, slimePosition, anchor.Direction)
				targetPositionsByPet[petSlot] = slimePosition
			end
			for slimeSlot in pairs(entry.CombatAnchors) do
				if not activeAnchorSlots[slimeSlot] then
					entry.CombatAnchors[slimeSlot] = nil
				end
			end
			combatGoals = CombatFormation.resolveSpacing(combatGoals, targetPositionsByPet)
			CombatAttackRuntime.trim(entry.CombatAttackStates, #entry.Party)
			CombatTransitionRuntime.trim(entry.CombatTransitionStates, #entry.Party)

			for slot, visual in pairs(entry.Visuals) do
				local x, z = Formation.slot(slot, #entry.Party, spacing, depth, Config.FirstRow)
				local followGoal = frame:PointToWorldSpace(Vector3.new(x, 0, z))
				local combatGoal = combatGoals[slot]
				local targetToken = targetModels[slot]
				local target, motionProfile, holding = CombatTransitionRuntime.step(
					entry.CombatTransitionStates,
					slot,
					visual.Position,
					targetToken,
					combatGoal,
					followGoal,
					clock
				)

				local targetYaw = yaw
				local attackOffset = Vector3.zero
				local impact = false
				if combatGoal and targetToken and not holding then
					targetYaw = CombatFormation.facingYaw(combatGoal, targetPositionsByPet[slot]) or yaw
					attackOffset, impact = CombatAttackRuntime.step(
						entry.CombatAttackStates,
						slot,
						visual,
						targetToken,
						targetPositionsByPet[slot],
						combatGoal,
						clock
					)
				else
					if holding and visual.Yaw then
						targetYaw = visual.Yaw
					end
					attackOffset, impact = CombatAttackRuntime.step(
						entry.CombatAttackStates, slot, visual, nil, nil, nil, clock
					)
					if holding then
						impact = false
					end
				end

				if impact and player == Players.LocalPlayer then
					local slimeSlot = validAssignments[slot]
					if slimeSlot then
						petImpactRemote:FireServer(slot, slimeSlot)
					end
				end
				if Motion.step(
					visual,
					target,
					root,
					targetYaw or yaw,
					dt,
					clock,
					probe,
					recall,
					attackOffset,
					motionProfile
				) then
					visual.Model.Parent = folder
				else
					VisualFactory.hide(visual)
				end
			end
		end
	end)
	stopCurrent = function()
		renderConnection:Disconnect()
		stopCombatObserver()
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
