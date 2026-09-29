local Workspace = game:GetService("Workspace")

local CombatTargeting = {}

local function runtimeFolder()
	return Workspace:FindFirstChild("PawlandsSlimes")
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

return CombatTargeting
