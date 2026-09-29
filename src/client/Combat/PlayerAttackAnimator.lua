local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local CombatConfig = require(Shared.Config.PlayerCombat)
local CombatAnimations = require(Shared.Config.PlayerCombatAnimations)

local PlayerAttackAnimator = {}
PlayerAttackAnimator.__index = PlayerAttackAnimator

function PlayerAttackAnimator.new(animator)
	local self = setmetatable({
		Tracks = {},
		Current = nil,
	}, PlayerAttackAnimator)

	for index, animationId in ipairs(CombatAnimations.M1) do
		local animation = Instance.new("Animation")
		animation.Name = "Pawlands_M1_" .. tostring(index)
		animation.AnimationId = animationId
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		animation:Destroy()

		if ok and track then
			track.Name = "Pawlands_M1_" .. tostring(index)
			track.Priority = CombatConfig.AnimationPriority
			track.Looped = false
			self.Tracks[index] = track
		else
			warn("[Pawlands Combat] Failed to load M1 animation " .. tostring(index) .. ": " .. tostring(track))
		end
	end
	return self
end

function PlayerAttackAnimator:Play(comboIndex)
	local track = self.Tracks[comboIndex]
	if not track then
		return false
	end
	if self.Current and self.Current ~= track and self.Current.IsPlaying then
		self.Current:Stop(CombatConfig.AnimationFade)
	end
	self.Current = track
	track:Play(CombatConfig.AnimationFade, 1, 1)
	return true
end

function PlayerAttackAnimator:Destroy()
	for _, track in pairs(self.Tracks) do
		if track.IsPlaying then
			track:Stop(0)
		end
		track:Destroy()
	end
	table.clear(self.Tracks)
	self.Current = nil
end

return PlayerAttackAnimator
