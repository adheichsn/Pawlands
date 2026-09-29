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

local function finiteVector(vector)
	return typeof(vector) == "Vector3"
		and vector.X == vector.X and vector.Y == vector.Y and vector.Z == vector.Z
		and math.abs(vector.X) < math.huge
		and math.abs(vector.Y) < math.huge
		and math.abs(vector.Z) < math.huge
end

local function horizontalUnit(vector)
	if not finiteVector(vector) then
		return nil
	end
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude <= 1e-4 then
		return nil
	end
	return flat.Unit
end

local function angleDegrees(a, b)
	return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
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

function CombatValidation.ResolveAim(root, requestedDirection, config)
	local rootDirection = horizontalUnit(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local requested = horizontalUnit(requestedDirection)
	if not requested then
		return rootDirection
	end
	if angleDegrees(rootDirection, requested) > config.ServerAimRootMaxDegrees then
		return rootDirection
	end
	return requested
end

function CombatValidation.IsRunningAttackValid(playerState, config)
	local root = playerState.Root
	local humanoid = playerState.Humanoid
	if humanoid.MoveDirection.Magnitude <= 0.10 then
		return false
	end
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	return speed >= config.RunningAttack.ServerMinimumHorizontalSpeedStuds
end

function CombatValidation.HasLineOfSight(character, target, runtimeFolder)
	local origin = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
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
