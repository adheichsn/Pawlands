local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatTargeting = {}

local function runtimeFolder()
	return Workspace:FindFirstChild("PawlandsSlimes")
end

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function safeUnit(vector, fallback)
	local flat = horizontal(vector)
	if flat.Magnitude <= 1e-4 then
		return fallback
	end
	return flat.Unit
end

local function angleDegrees(a, b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	return math.deg(math.acos(dot))
end

local function cursorPosition(camera)
	local viewport = camera.ViewportSize
	if not UserInputService.MouseEnabled then
		return viewport * 0.5
	end

	local mouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	return Vector2.new(mouse.X - inset.X, mouse.Y - inset.Y)
end

local function lineOfSight(character, target, folder)
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local start = head and head.Position or root.Position
	local goal = target:GetPivot().Position
	local params = RaycastParams.new()
	params.IgnoreWater = true
	params.RespectCanCollide = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, folder }
	return Workspace:Raycast(start, goal - start, params) == nil
end

function CombatTargeting.ResolveFromPart(part)
	if not part then
		return nil
	end
	local folder = runtimeFolder()
	if not folder then
		return nil
	end

	local current = part
	while current and current ~= Workspace do
		if current:IsA("Model") and current.Parent == folder and current:GetAttribute("SlimeId") then
			return current
		end
		current = current.Parent
	end
	return nil
end

function CombatTargeting.IsAlive(slimeModel)
	return slimeModel
		and slimeModel.Parent == runtimeFolder()
		and slimeModel:GetAttribute("Defeated") ~= true
		and (slimeModel:GetAttribute("Health") or 0) > 0
end

function CombatTargeting.ResolveAimDirection(root)
	local rootForward = safeUnit(root.CFrame.LookVector, Vector3.new(0, 0, -1))
	local camera = Workspace.CurrentCamera
	if not camera then
		return rootForward
	end

	-- Shift Lock keeps the cursor centered and is most naturally camera-led.
	-- Normal mouse/mobile play remains character-facing so orbiting the camera
	-- does not make attacks fire behind the avatar.
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		return safeUnit(camera.CFrame.LookVector, rootForward)
	end
	return rootForward
end

function CombatTargeting.Acquire(character, root, hoveredPart, config)
	local folder = runtimeFolder()
	if not folder then
		return nil, CombatTargeting.ResolveAimDirection(root)
	end

	local camera = Workspace.CurrentCamera
	local aimDirection = CombatTargeting.ResolveAimDirection(root)
	local directTarget = CombatTargeting.ResolveFromPart(hoveredPart)
	local cursor = camera and cursorPosition(camera) or nil
	local viewportScale = camera and math.max(1, math.min(camera.ViewportSize.X, camera.ViewportSize.Y)) or 1
	local bestTarget = nil
	local bestScore = math.huge

	for _, candidate in ipairs(folder:GetChildren()) do
		if candidate:IsA("Model") and CombatTargeting.IsAlive(candidate) then
			local delta = candidate:GetPivot().Position - root.Position
			local flat = horizontal(delta)
			local distance = flat.Magnitude
			if distance > 0.01 and distance <= config.TargetAcquisitionRange then
				local direction = flat.Unit
				local angle = angleDegrees(aimDirection, direction)
				if angle <= config.TargetHalfAngleDegrees and lineOfSight(character, candidate, folder) then
					local cursorScore = 0
					if camera and cursor then
						local screen, visible = camera:WorldToViewportPoint(candidate:GetPivot().Position)
						if visible and screen.Z > 0 then
							cursorScore = (Vector2.new(screen.X, screen.Y) - cursor).Magnitude / viewportScale
						else
							cursorScore = 1
						end
					end

					local score = (angle / config.TargetHalfAngleDegrees) * config.TargetAngleWeight
						+ (distance / config.TargetAcquisitionRange) * config.TargetDistanceWeight
						+ cursorScore * config.TargetCursorWeight
					if candidate == directTarget then
						score -= config.DirectHoverBonus
					end

					if score < bestScore then
						bestScore = score
						bestTarget = candidate
					end
				end
			end
		end
	end

	return bestTarget, aimDirection
end

return CombatTargeting
