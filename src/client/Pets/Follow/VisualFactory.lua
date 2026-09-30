local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local PartyConfig = require(Shared.Config.PetParty)
local Catalog = require(Shared.Config.PetCatalog)
local Assets = require(Shared.Pets.PetAssets)

local VisualFactory = {}

function VisualFactory.create(id, ownerId, slot)
	local definition = Catalog.Pets[id]
	local template, reason = Assets.find(definition, PartyConfig.AssetPath)
	if not template then
		return nil, reason
	end
	local model = template:Clone()
	if not model then
		return nil, "Pet template is not Archivable: " .. id
	end
	local authoredPivot = model:GetPivot()
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.CastShadow = true
		elseif item:IsA("LuaSourceContainer") then
			item:Destroy()
		end
	end
	local body = model:FindFirstChild("Body", true)
	local primary = (body and body:IsA("BasePart") and body)
		or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		model:Destroy()
		return nil, "Pet clone has no BasePart: " .. id
	end
	-- Body can have an imported, rotated PivotOffset even when the model is upright.
	-- Preserve the Studio model pivot before making Body the PrimaryPart.
	primary.PivotOffset = primary.CFrame:ToObjectSpace(authoredPivot)
	model.PrimaryPart = primary
	local pivot = model:GetPivot()
	local bounds, size = model:GetBoundingBox()
	local localCenter = pivot:PointToObjectSpace(bounds.Position)
	model.Name = tostring(ownerId) .. "_" .. tostring(slot) .. "_" .. id
	model:SetAttribute("OwnerUserId", ownerId)
	model:SetAttribute("PetSlot", slot)
	model:SetAttribute("PetId", id)
	return {
		Model = model,
		Definition = definition,
		GroundOffset = math.max(0, size.Y / 2 - localCenter.Y),
		Footprint = math.max(size.X, size.Z),
		Phase = slot * 1.7,
		Position = nil,
		Yaw = nil,
		Walk = 0,
		MotionSpeed = 0,
	}, nil
end

function VisualFactory.hide(visual)
	visual.Model.Parent = nil
	visual.Position, visual.Yaw, visual.Walk, visual.MotionSpeed = nil, nil, 0, 0
end

function VisualFactory.destroyAll(visuals)
	for _, visual in pairs(visuals) do
		visual.Model:Destroy()
	end
	table.clear(visuals)
end

return VisualFactory
