local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Animations = require(Shared.Config.PlayerAnimations)

local AnimationTracks = {}
AnimationTracks.__index = AnimationTracks

local definitions = {
	IdleBase = { Id = Animations.Idle.Base, Priority = Enum.AnimationPriority.Idle, Looped = true },
	IdleAlt1 = { Id = Animations.Idle.Alt1, Priority = Enum.AnimationPriority.Idle, Looped = false },
	IdleAlt2 = { Id = Animations.Idle.Alt2, Priority = Enum.AnimationPriority.Idle, Looped = false },

	WalkForward1 = { Id = Animations.Walk.Forward1, Priority = Enum.AnimationPriority.Movement, Looped = true },
	WalkForward2 = { Id = Animations.Walk.Forward2, Priority = Enum.AnimationPriority.Movement, Looped = true },
	WalkBack = { Id = Animations.Walk.Back, Priority = Enum.AnimationPriority.Movement, Looped = true },
	WalkRight = { Id = Animations.Walk.Right, Priority = Enum.AnimationPriority.Movement, Looped = true },
	WalkLeft = { Id = Animations.Walk.Left, Priority = Enum.AnimationPriority.Movement, Looped = true },
	WalkFrontRight = { Id = Animations.Walk.FrontRight, Priority = Enum.AnimationPriority.Movement, Looped = true },
	WalkFrontLeft = { Id = Animations.Walk.FrontLeft, Priority = Enum.AnimationPriority.Movement, Looped = true },
	WalkBackRight = { Id = Animations.Walk.BackRight, Priority = Enum.AnimationPriority.Movement, Looped = true },
	WalkBackLeft = { Id = Animations.Walk.BackLeft, Priority = Enum.AnimationPriority.Movement, Looped = true },

	RunNormal = { Id = Animations.Run.Normal, Priority = Enum.AnimationPriority.Movement, Looped = true },
	RunFast = { Id = Animations.Run.Fast, Priority = Enum.AnimationPriority.Movement, Looped = true },

	Jump = { Id = Animations.Air.Jump, Priority = Enum.AnimationPriority.Movement, Looped = false },
	Falling = { Id = Animations.Air.Falling, Priority = Enum.AnimationPriority.Movement, Looped = true },
	LandingLight = { Id = Animations.Air.LandingLight, Priority = Enum.AnimationPriority.Movement, Looped = false },
	LandingMedium = { Id = Animations.Air.LandingMedium, Priority = Enum.AnimationPriority.Movement, Looped = false },
	LandingHeavy = { Id = Animations.Air.LandingHeavy, Priority = Enum.AnimationPriority.Movement, Looped = false },
}

function AnimationTracks.new(animator)
	local self = setmetatable({ Tracks = {}, Current = nil }, AnimationTracks)

	for name, definition in pairs(definitions) do
		local animation = Instance.new("Animation")
		animation.Name = "Pawlands_" .. name
		animation.AnimationId = definition.Id
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		animation:Destroy()

		if ok and track then
			track.Name = "Pawlands_" .. name
			track.Priority = definition.Priority
			track.Looped = definition.Looped
			self.Tracks[name] = track
		else
			warn("[Pawlands Movement] Failed to load animation " .. name .. ": " .. tostring(track))
		end
	end

	return self
end

function AnimationTracks:Get(name)
	return self.Tracks[name]
end

function AnimationTracks:PlayExclusive(name, fadeTime, speed)
	local target = self.Tracks[name]
	if not target then
		return nil
	end

	if self.Current == name and target.IsPlaying then
		target:AdjustSpeed(speed or 1)
		return target
	end

	for otherName, track in pairs(self.Tracks) do
		if otherName ~= name and track.IsPlaying then
			track:Stop(fadeTime or 0.1)
		end
	end

	self.Current = name
	target:Play(fadeTime or 0.1, 1, speed or 1)
	return target
end

function AnimationTracks:StopAll(fadeTime)
	self.Current = nil
	for _, track in pairs(self.Tracks) do
		if track.IsPlaying then
			track:Stop(fadeTime or 0)
		end
	end
end

function AnimationTracks:Destroy()
	self:StopAll(0)
	for _, track in pairs(self.Tracks) do
		track:Destroy()
	end
	table.clear(self.Tracks)
end

return AnimationTracks
