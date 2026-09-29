local Workspace = game:GetService("Workspace")

local CombatContactRuntime = {}

local function horizontalUnit(vector, fallback)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude > 0.001 then
		return flat.Unit
	end
	local fallbackFlat = Vector3.new(fallback.X, 0, fallback.Z)
	if fallbackFlat.Magnitude > 0.001 then
		return fallbackFlat.Unit
	end
	return Vector3.new(0, 0, -1)
end

local function getTargetRoot(target)
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return nil
	end
	return target:FindFirstChild("RootPart", true)
		or target.PrimaryPart
		or target:FindFirstChildWhichIsA("BasePart", true)
end

local function getHorizontalRadius(target, contact)
	local ok, _, size = pcall(target.GetBoundingBox, target)
	if not ok then
		return contact.MinSlimeRadiusStuds
	end
	return math.clamp(
		math.max(size.X, size.Z) * 0.5,
		contact.MinSlimeRadiusStuds,
		contact.MaxSlimeRadiusStuds
	)
end

local function resolveCorrection(character, target, root, direction, distance, contact)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.FloorMaterial == Enum.Material.Air then
		return 0
	end

	local desiredDistance = getHorizontalRadius(target, contact)
		+ contact.PlayerRadiusStuds
		+ contact.GapStuds
	local correction = math.min(
		math.max(0, desiredDistance - distance),
		contact.SoftSeparationMaxStuds
	)
	if correction <= 0.001 then
		return 0
	end

	local rayDirection = -direction * correction
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, target }
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local result = Workspace:Raycast(root.Position, rayDirection, params)
	if result and result.Instance and result.Instance.CanCollide then
		correction = math.max(0, result.Distance - contact.RaycastPaddingStuds)
	end
	return correction
end

function CombatContactRuntime.PrepareAttack(character, target, config, fallbackDirection)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return fallbackDirection
	end

	local fallback = fallbackDirection or root.CFrame.LookVector
	local targetRoot = getTargetRoot(target)
	if not targetRoot then
		return horizontalUnit(fallback, root.CFrame.LookVector)
	end

	local delta = Vector3.new(
		targetRoot.Position.X - root.Position.X,
		0,
		targetRoot.Position.Z - root.Position.Z
	)
	local direction = horizontalUnit(delta, fallback)
	local distance = delta.Magnitude
	local contact = config.Contact
	if not contact or distance > contact.FacingAssistMaxDistanceStuds then
		return direction
	end

	local correction = resolveCorrection(character, target, root, direction, distance, contact)
	local position = root.Position - (direction * correction)
	root.CFrame = CFrame.lookAt(position, position + direction, Vector3.yAxis)
	return direction
end

return CombatContactRuntime
