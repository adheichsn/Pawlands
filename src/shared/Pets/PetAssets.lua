local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetAssets = {}

function PetAssets.find(definition, assetPath)
	local folder = ReplicatedStorage
	for _, name in ipairs(assetPath) do
		folder = folder:FindFirstChild(name)
		if not folder then
			return nil, "Missing Studio pet folder: ReplicatedStorage/" .. table.concat(assetPath, "/")
		end
	end
	local model = folder:FindFirstChild(definition.ModelName)
	if not model or not model:IsA("Model") then
		return nil, "Missing Studio pet model: " .. definition.ModelName
	end
	if not model:FindFirstChildWhichIsA("BasePart", true) then
		return nil, "Pet model has no BasePart: " .. definition.ModelName
	end
	return model, nil
end

return PetAssets
