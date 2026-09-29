local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Catalog = require(Shared.Config.SlimeCatalog)
local Animations = require(Shared.Config.SlimeAnimations)

local SlimeFactory = {}

local function resolveAssets()
	local node = ReplicatedStorage
	for _, name in ipairs(Catalog.AssetPath) do
		node = node:FindFirstChild(name)
		if not node then
			return nil
		end
	end
	return node
end

local function configureParts(model)
	local root = model:FindFirstChild("RootPart", true)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.CastShadow = true
			item.Massless = item ~= root
			if item == root then
				item.Anchored = true
				item.CanQuery = false
			else
				item.Anchored = false
				item.CanQuery = true
			end
		elseif item:IsA("LuaSourceContainer") then
			item:Destroy()
		end
	end
	return root
end

local function loadIdle(model)
	local animator = model:FindFirstChildWhichIsA("Animator", true)
	if not animator then
		return nil, "missing Animator"
	end
	local animation = Instance.new("Animation")
	animation.Name = "PawlandsSlimeIdleRuntime"
	animation.AnimationId = Animations.Idle
	local ok, trackOrReason = pcall(function()
		local track = animator:LoadAnimation(animation)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play(0.12)
		return track
	end)
	animation:Destroy()
	if not ok or not trackOrReason then
		return nil, tostring(trackOrReason)
	end
	return trackOrReason, nil
end

function SlimeFactory.Create(definition, slot, runtimeFolder)
	local assets = resolveAssets()
	if not assets then
		return nil, "Missing Studio slime folder ReplicatedStorage/" .. table.concat(Catalog.AssetPath, "/")
	end
	local template = assets:FindFirstChild(definition.ModelName)
	if not template or not template:IsA("Model") then
		return nil, "Missing Studio slime model: " .. definition.ModelName
	end

	local model = template:Clone()
	if not model then
		return nil, "Slime template is not Archivable: " .. definition.ModelName
	end
	local authoredPivot = model:GetPivot()
	local bounds, size = model:GetBoundingBox()
	local localCenter = authoredPivot:PointToObjectSpace(bounds.Position)
	local groundOffset = math.max(0, size.Y * 0.5 - localCenter.Y)

	local root = configureParts(model)
	if not root then
		model:Destroy()
		return nil, "Slime model has no RootPart: " .. definition.ModelName
	end

	model.Name = string.format("Slime_%02d_%s", slot, definition.Id)
	model:SetAttribute("SlimeId", definition.Id)
	model:SetAttribute("SlimeSlot", slot)
	model:SetAttribute("SlimeState", "Spawn")
	model:SetAttribute("TargetUserId", 0)
	model.Parent = runtimeFolder

	local idleTrack, animationReason = loadIdle(model)
	return {
		Model = model,
		IdleTrack = idleTrack,
		AnimationReason = animationReason,
		GroundOffset = groundOffset,
	}, nil
end

function SlimeFactory.Destroy(visual)
	if visual.IdleTrack then
		visual.IdleTrack:Stop(0.1)
		visual.IdleTrack:Destroy()
	end
	visual.Model:Destroy()
end

return SlimeFactory
