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

local function naturalDuration(track)
	if not track or track.Length <= 0 then
		return nil
	end
	return track.Length / CombatConfig.AnimationPlaybackSpeed
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

function PlayerAttackAnimator:_play(track)
	if not track then
		return false, nil
	end

	if self.Current and self.Current ~= track and self.Current.IsPlaying then
		self.Current:Stop(CombatConfig.AnimationTransitionFade)
	elseif self.Current == track and track.IsPlaying then
		track:Stop(CombatConfig.AnimationTransitionFade)
	end

	self.Current = track
	track:Play(CombatConfig.AnimationTransitionFade, 1, CombatConfig.AnimationPlaybackSpeed)
	return true, naturalDuration(track)
end

function PlayerAttackAnimator:PlayCombo(comboIndex)
	return self:_play(self.ComboTracks[comboIndex])
end

function PlayerAttackAnimator:PlayRunning()
	return self:_play(self.RunningTrack)
end

function PlayerAttackAnimator:StopCurrent(fadeTime)
	local track = self.Current
	self.Current = nil
	if track and track.IsPlaying then
		track:Stop(fadeTime or CombatConfig.AnimationExitFade)
	end
end

function PlayerAttackAnimator:Destroy()
	self:StopCurrent(0)
	for _, track in pairs(self.ComboTracks) do
		if track then
			if track.IsPlaying then
				track:Stop(0)
			end
			track:Destroy()
		end
	end
	if self.RunningTrack then
		if self.RunningTrack.IsPlaying then
			self.RunningTrack:Stop(0)
		end
		self.RunningTrack:Destroy()
	end
	table.clear(self.ComboTracks)
	self.RunningTrack = nil
end

return PlayerAttackAnimator
