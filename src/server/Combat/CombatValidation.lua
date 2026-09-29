local Workspace = game:GetService("Workspace")

local CombatValidation = {}

local function characterState(player)
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return character, humanoid, root
end

function CombatValidation.ValidatePlayer(player, config)
	local character, humanoid, root = characterState(player)
	if not character then
		return nil, "invalid player character"
	end
	if config.RequireGrounded and humanoid.FloorMaterial == Enum.Material.Air then
		return nil, "player is airborne"
	end
	return { Character = character, Humanoid = humanoid, Root = root }, nil
end

function CombatValidation.ValidateTarget(target, runtimeFolder, slimeHealth)
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return false, "invalid target"
	end
	if target.Parent ~= runtimeFolder or not target:GetAttribute("SlimeId") then
		return false, "target is not a managed slime"
	end
	if not slimeHealth.IsAlive(target) then
		return false, "target is defeated"
	end
	return true, nil
end

function CombatValidation.InRange(root, target, range)
	local delta = target:GetPivot().Position - root.Position
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	return horizontal.Magnitude <= range
end

function CombatValidation.HasLineOfSight(character, target, runtimeFolder)
	local origin = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	local start = origin and origin.Position or root.Position
	local goal = target:GetPivot().Position
	local params = RaycastParams.new()
	params.IgnoreWater = true
	params.RespectCanCollide = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, runtimeFolder }
	local result = Workspace:Raycast(start, goal - start, params)
	return result == nil
end

return CombatValidation
