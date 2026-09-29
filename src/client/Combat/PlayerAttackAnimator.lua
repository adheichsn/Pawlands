local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local CombatConfig = require(Shared.Config.PlayerCombat)
local CombatAnimations = require(Shared.Config.PlayerCombatAnimations)

local PlayerAttackAnimator = {}
PlayerAttackAnimator.__index = PlayerAttackAnimator

local function loadTrack(animator, name, animationId)
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()

	if not ok or not track then
		warn("[Pawlands Combat] Failed to load animation " .. name .. ": " .. tostring(track))
		return nil
	end

	track.Name = name
	track.Priority = CombatConfig.AnimationPriority
	track.Looped = false
	return track
end

function PlayerAttackAnimator.new(animator)
	local self = setmetatable({
		ComboTracks = {},
		RunningTrack = nil,
		Current = nil,
	}, PlayerAttackAnimator)

	for index, animationId in ipairs(CombatAnimations.M1) do
		self.ComboTracks[index] = loadTrack(animator, "Pawlands_M1_" .. tostring(index), animationId)
	end
	self.RunningTrack = loadTrack(animator, "Pawlands_RunningAttack", CombatAnimations.RunningAttack)
	return self
end

function PlayerAttackAnimator:_play(track, speed)
	if not track then
		return false
	end

	local fade = CombatConfig.AnimationFadeSeconds
	if self.Current and self.Current ~= track and self.Current.IsPlaying then
		self.Current:Stop(fade)
	elseif self.Current == track and track.IsPlaying then
		track:Stop(0)
	end

	self.Current = track
	track:Play(fade, 1, speed or 1)
	return true
end

function PlayerAttackAnimator:PlayCombo(comboIndex)
	local track = self.ComboTracks[comboIndex]
	return self:_play(track, CombatConfig.GetComboPlaybackSpeed(comboIndex, track and track.Length))
end

function PlayerAttackAnimator:PlayRunning()
	local track = self.RunningTrack
	return self:_play(track, CombatConfig.GetRunningPlaybackSpeed(track and track.Length))
end

function PlayerAttackAnimator:Destroy()
	if self.Current and self.Current.IsPlaying then
		self.Current:Stop(0)
	end
	self.Current = nil
	for _, track in pairs(self.ComboTracks) do
		if track then
			track:Destroy()
		end
	end
	if self.RunningTrack then
		self.RunningTrack:Destroy()
	end
	table.clear(self.ComboTracks)
	self.RunningTrack = nil
end

return PlayerAttackAnimator
