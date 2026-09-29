local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local AnimationConfig = require(Shared.Config.SlimeAnimations)

local SlimeAnimationRuntime = {}
SlimeAnimationRuntime.__index = SlimeAnimationRuntime

local function normalizeId(animationId)
	return string.lower(string.gsub(tostring(animationId or ""), "%s+", ""))
end

local function classify(animation)
	local name = string.lower(animation.Name)
	if string.find(name, "walk", 1, true)
		or string.find(name, "run", 1, true)
		or string.find(name, "chase", 1, true) then
		return "Move"
	end
	if string.find(name, "idle", 1, true) then
		return "Idle"
	end
	return nil
end

local function findAnimator(model)
	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	if not controller then
		return nil
	end
	return controller:FindFirstChildOfClass("Animator")
end

local function safeLoad(animator, animation)
	local animationId = normalizeId(animation.AnimationId)
	if animationId == "" or AnimationConfig.BlockedAnimationIds[animationId] then
		return nil
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Movement
	return track
end

function SlimeAnimationRuntime.new(model)
	local self = setmetatable({
		Model = model,
		Tracks = {},
		CurrentLoop = nil,
		Moving = false,
	}, SlimeAnimationRuntime)

	local animator = findAnimator(model)
	if not animator then
		return self
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Animation") then
			local kind = classify(descendant)
			if kind and not self.Tracks[kind] then
				local track = safeLoad(animator, descendant)
				if track then
					self.Tracks[kind] = track
				end
			end
		end
	end

	return self
end

function SlimeAnimationRuntime:_setLoop(track)
	if self.CurrentLoop == track then
		return
	end
	if self.CurrentLoop and self.CurrentLoop.IsPlaying then
		self.CurrentLoop:Stop(0.12)
	end
	self.CurrentLoop = track
	if track and not track.IsPlaying then
		track:Play(0.12, 1, 1)
	end
end

function SlimeAnimationRuntime:SetMoving(moving)
	moving = moving == true
	if self.Moving == moving and self.CurrentLoop then
		return
	end
	self.Moving = moving
	if moving then
		self:_setLoop(self.Tracks.Move or self.Tracks.Idle)
	else
		self:_setLoop(self.Tracks.Idle)
	end
end

function SlimeAnimationRuntime:HasAuthoredLoop()
	return self.Tracks.Idle ~= nil or self.Tracks.Move ~= nil
end

function SlimeAnimationRuntime:Destroy()
	for _, track in pairs(self.Tracks) do
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	table.clear(self.Tracks)
	self.CurrentLoop = nil
end

return SlimeAnimationRuntime
