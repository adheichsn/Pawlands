local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Pawlands = ReplicatedStorage:WaitForChild("Pawlands")
local Shared = Pawlands:WaitForChild("Shared")
local CombatConfig = require(Shared.Config.PetCombat)
local FollowConfig = require(Shared.Config.PetFollow)
local CombatEffects = require(script.Parent.Parent.Parent.Combat.CombatEffects)
local PresentationRuntime = require(script.Parent.PetCombatPresentationRuntime)

local PetCombatFeedbackController = {}
local stopCurrent = nil

local function resolvePetVisual(ownerUserId, petSlot)
	local folder = Workspace:FindFirstChild(FollowConfig.VisualFolderName)
	if not folder or not folder:IsA("Folder") then
		return nil
	end

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model")
			and tonumber(model:GetAttribute("OwnerUserId")) == ownerUserId
			and tonumber(model:GetAttribute("PetSlot")) == petSlot
		then
			return model
		end
	end
	return nil
end

function PetCombatFeedbackController.Start()
	if stopCurrent then
		return
	end

	local remotes = Pawlands:WaitForChild(CombatConfig.RemoteFolderName)
	local feedbackRemote = remotes:WaitForChild(CombatConfig.FeedbackRemoteName)
	local connection = feedbackRemote.OnClientEvent:Connect(function(ownerUserId, petSlot, knockedOut, recoverAt, hitDirection)
		if type(ownerUserId) ~= "number" or type(petSlot) ~= "number" then
			return
		end
		petSlot = math.floor(petSlot)
		if petSlot < 1 then
			return
		end

		PresentationRuntime.RecordHit(ownerUserId, petSlot, knockedOut, recoverAt, hitDirection)

		local petModel = resolvePetVisual(ownerUserId, petSlot)
		if not petModel then
			return
		end

		-- Keep the final hit splat particles, but let the KO template own the
		-- knockout sound so the finishing impact does not double-stack audio.
		CombatEffects.PlaySlimeHitPet(petModel, knockedOut ~= true)
		if knockedOut == true then
			CombatEffects.PlayPetKO(petModel)
		end
	end)

	stopCurrent = function()
		connection:Disconnect()
	end
end

function PetCombatFeedbackController.Stop()
	if not stopCurrent then
		return
	end
	local stop = stopCurrent
	stopCurrent = nil
	stop()
end

return PetCombatFeedbackController
