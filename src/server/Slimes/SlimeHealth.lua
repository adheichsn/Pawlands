local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.SlimeCombat)
local FeedbackConfig = require(Shared.Config.SlimeFeedback)

local SlimeHealth = {}

function SlimeHealth.Initialize(model)
	model:SetAttribute("MaxHealth", Config.MaxHealth)
	model:SetAttribute("Health", Config.MaxHealth)
	model:SetAttribute("Defeated", false)
	model:SetAttribute("DefeatedAt", 0)
	model:SetAttribute("LastHitUserId", 0)
	model:SetAttribute("LastHitSourceType", "None")
	model:SetAttribute("PlayerHitSerial", 0)
	model:SetAttribute("LastPlayerHitAt", 0)
	model:SetAttribute("LastPlayerHitUserId", 0)
	model:SetAttribute("LastHitSourceUid", "")
	model:SetAttribute("LastHitDamage", 0)
	model:SetAttribute("LastHitDirection", Vector3.zero)
	model:SetAttribute("LastHitFeedbackTier", FeedbackConfig.FeedbackTiers.Light)
	model:SetAttribute("HitSerial", 0)
end

function SlimeHealth.IsAlive(model)
	return model
		and model:GetAttribute("Defeated") ~= true
		and (model:GetAttribute("Health") or 0) > 0
end

function SlimeHealth.ApplyDamage(model, amount, player, feedback)
	if not SlimeHealth.IsAlive(model) then
		return false, 0
	end

	local appliedDamage = math.max(0, amount)
	local current = model:GetAttribute("Health") or Config.MaxHealth
	local nextHealth = math.max(0, current - appliedDamage)
	local feedbackTier = feedback and feedback.Tier
	if feedbackTier ~= FeedbackConfig.FeedbackTiers.Finisher then
		feedbackTier = FeedbackConfig.FeedbackTiers.Light
	end
	local feedbackDirection = feedback and feedback.Direction
	if typeof(feedbackDirection) ~= "Vector3" then
		feedbackDirection = Vector3.zero
	end

	-- Publish metadata before HitSerial so clients can treat the serial as the
	-- committed presentation event and read a complete snapshot for that impact.
	local sourceType = feedback and feedback.SourceType == "Pet" and "Pet" or "Player"
	local sourceUid = sourceType == "Pet" and tostring(feedback and feedback.SourceUid or "") or ""
	model:SetAttribute("LastHitUserId", player and player.UserId or 0)
	model:SetAttribute("LastHitSourceType", sourceType)
	if sourceType == "Player" then
		model:SetAttribute("PlayerHitSerial", (model:GetAttribute("PlayerHitSerial") or 0) + 1)
		model:SetAttribute("LastPlayerHitAt", time())
		model:SetAttribute("LastPlayerHitUserId", player and player.UserId or 0)
	end
	model:SetAttribute("LastHitSourceUid", sourceUid)
	model:SetAttribute("LastHitDamage", appliedDamage)
	model:SetAttribute("LastHitDirection", feedbackDirection)
	model:SetAttribute("LastHitFeedbackTier", feedbackTier)
	model:SetAttribute("Health", nextHealth)

	if nextHealth <= 0 then
		model:SetAttribute("DefeatedAt", Workspace:GetServerTimeNow())
		model:SetAttribute("Defeated", true)
		model:SetAttribute("CombatReady", false)
		model:SetAttribute("AttackQueued", false)
		model:SetAttribute("AttackTurnActive", false)
		model:SetAttribute("TargetUserId", 0)
		model:SetAttribute("TargetType", "None")
		model:SetAttribute("TargetPetSlot", 0)
		model:SetAttribute("TargetPetUid", "")
		model:SetAttribute("SlimeState", "Defeated")
	end

	model:SetAttribute("HitSerial", (model:GetAttribute("HitSerial") or 0) + 1)
	return true, nextHealth
end

return SlimeHealth
