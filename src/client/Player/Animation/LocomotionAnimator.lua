local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PlayerMovement)
local DirectionResolver = require(script.Parent.DirectionResolver)
local AnimationTracks = require(script.Parent.AnimationTracks)

local LocomotionAnimator = {}
LocomotionAnimator.__index = LocomotionAnimator

local walkTracks = {
	Forward = "WalkForward1",
	Back = "WalkBack",
	Right = "WalkRight",
	Left = "WalkLeft",
	FrontRight = "WalkFrontRight",
	FrontLeft = "WalkFrontLeft",
	BackRight = "WalkBackRight",
	BackLeft = "WalkBackLeft",
}

local idleAlternates = { "IdleAlt1", "IdleAlt2" }

local function horizontalSpeed(root)
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function playbackSpeed(actualSpeed, referenceSpeed)
	return math.clamp(
		actualSpeed / math.max(referenceSpeed, 0.001),
		Config.MinimumPlaybackSpeed,
		Config.MaximumPlaybackSpeed
	)
end

local function randomFrom(random, values)
	return values[random:NextInteger(1, #values)]
end

function LocomotionAnimator.new(humanoid, root, animator)
	local self = setmetatable({
		Humanoid = humanoid,
		Root = root,
		Tracks = AnimationTracks.new(animator),
		Random = Random.new(),
		Mode = "",
		Direction = "Forward",
		WasAirborne = false,
		MaxDownSpeed = 0,
		OneShotToken = 0,
		OneShotActive = false,
		OneShotStartedAt = 0,
		NextIdleVariantAt = 0,
	}, LocomotionAnimator)

	self:EnterIdle(Config.AnimationFade)
	return self
end

function LocomotionAnimator:ScheduleIdleVariant()
	self.NextIdleVariantAt = os.clock() + self.Random:NextNumber(
		Config.IdleVariantMinSeconds,
		Config.IdleVariantMaxSeconds
	)
end

function LocomotionAnimator:EnterIdle(fadeTime)
	self.Mode = "Idle"
	self.Direction = "Forward"
	self.OneShotActive = false
	self.Tracks:PlayExclusive("IdleBase", fadeTime or Config.AnimationFade, 1)
	self:ScheduleIdleVariant()
end

function LocomotionAnimator:PlayOneShot(name, onFinished)
	self.OneShotToken += 1
	local token = self.OneShotToken
	self.OneShotActive = true
	self.OneShotStartedAt = os.clock()
	local track = self.Tracks:PlayExclusive(name, Config.OneShotFade, 1)
	if not track then
		self.OneShotActive = false
		if onFinished then
			onFinished()
		end
		return
	end

	local connection
	connection = track.Stopped:Connect(function()
		connection:Disconnect()
		if token ~= self.OneShotToken then
			return
		end
		self.OneShotActive = false
		if onFinished then
			onFinished()
		end
	end)
end

function LocomotionAnimator:PlayLanding(downSpeed)
	if downSpeed < Config.MinLandingSpeed then
		return false
	end

	local name = "LandingLight"
	if downSpeed >= Config.HeavyLandingSpeed then
		name = "LandingHeavy"
	elseif downSpeed >= Config.MediumLandingSpeed then
		name = "LandingMedium"
	end

	self.Mode = "Landing"
	self:PlayOneShot(name)
	return self.OneShotActive
end

function LocomotionAnimator:UpdateIdleVariant()
	if self.Mode ~= "Idle" or self.OneShotActive or os.clock() < self.NextIdleVariantAt then
		return
	end

	local name = randomFrom(self.Random, idleAlternates)
	self:PlayOneShot(name, function()
		if self.Mode == "Idle" then
			self.Tracks:PlayExclusive("IdleBase", Config.AnimationFade, 1)
			self:ScheduleIdleVariant()
		end
	end)
end

function LocomotionAnimator:Update(isRunning)
	local humanoid = self.Humanoid
	local root = self.Root
	if humanoid.Health <= 0 or not root.Parent then
		return
	end

	local state = humanoid:GetState()
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall

	if airborne then
		self.WasAirborne = true
		self.MaxDownSpeed = math.max(self.MaxDownSpeed, -root.AssemblyLinearVelocity.Y)
		self.OneShotToken += 1
		self.OneShotActive = false

		if state == Enum.HumanoidStateType.Jumping or root.AssemblyLinearVelocity.Y > 1.5 then
			if self.Mode ~= "Jump" then
				self.Mode = "Jump"
				self.Tracks:PlayExclusive("Jump", Config.AnimationFade, 1)
			end
		else
			if self.Mode ~= "Falling" then
				self.Mode = "Falling"
				self.Tracks:PlayExclusive("Falling", Config.AnimationFade, 1)
			end
		end
		return
	end

	if self.WasAirborne then
		self.WasAirborne = false
		local downSpeed = self.MaxDownSpeed
		self.MaxDownSpeed = 0
		if self:PlayLanding(downSpeed) then
			return
		end
	end

	local moving = humanoid.MoveDirection.Magnitude > Config.MoveDeadzone
	local speed = horizontalSpeed(root)

	if self.OneShotActive then
		if self.Mode == "Landing" then
			local lockedFor = os.clock() - self.OneShotStartedAt
			if not moving or lockedFor < Config.MinimumLandingPresentationLock then
				return
			end
		elseif not moving then
			return
		end
		self.OneShotToken += 1
		self.OneShotActive = false
	end

	if not moving or speed <= Config.IdleSpeed then
		local fade = self.Mode == "Run" and Config.SprintStopFade or Config.AnimationFade
		if self.Mode ~= "Idle" or (self.Tracks:Get("IdleBase") and not self.Tracks:Get("IdleBase").IsPlaying) then
			self:EnterIdle(fade)
		else
			self:UpdateIdleVariant()
		end
		return
	end

	self.OneShotToken += 1
	self.OneShotActive = false

	if isRunning then
		self.Mode = "Run"
		self.Direction = "Forward"
		self.Tracks:PlayExclusive(
			"RunNormal",
			Config.AnimationFade,
			playbackSpeed(speed, Config.RunReferenceSpeed)
		)
		return
	end

	local facingLocked = not humanoid.AutoRotate
		or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
	local direction = "Forward"
	if facingLocked then
		direction = DirectionResolver.Resolve(
			root,
			humanoid.MoveDirection,
			self.Direction,
			Config.DirectionHysteresisDegrees
		)
	end
	self.Mode = "Walk"
	self.Direction = direction
	self.Tracks:PlayExclusive(
		walkTracks[direction] or "WalkForward1",
		Config.AnimationFade,
		playbackSpeed(speed, Config.WalkReferenceSpeed)
	)
end

function LocomotionAnimator:Destroy()
	self.OneShotToken += 1
	self.Tracks:Destroy()
end

return LocomotionAnimator
