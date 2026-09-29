local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PlayerMovement)
local DirectionResolver = require(script.Parent.DirectionResolver)
local AnimationTracks = require(script.Parent.AnimationTracks)

local LocomotionAnimator = {}
LocomotionAnimator.__index = LocomotionAnimator

local walkTracks = {
	Forward = { "WalkForward1", "WalkForward2" },
	Back = { "WalkBack" },
	Right = { "WalkRight" },
	Left = { "WalkLeft" },
	FrontRight = { "WalkFrontRight" },
	FrontLeft = { "WalkFrontLeft" },
	BackRight = { "WalkBackRight" },
	BackLeft = { "WalkBackLeft" },
}

local runTracks = { "Run1", "Run2" }
local idleAlternates = { "IdleAlt1", "IdleAlt2" }

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
		Direction = "",
		WasAirborne = false,
		MaxDownSpeed = 0,
		OneShotToken = 0,
		OneShotActive = false,
		NextIdleVariantAt = 0,
	}, LocomotionAnimator)

	self:EnterIdle()
	return self
end

function LocomotionAnimator:ScheduleIdleVariant()
	self.NextIdleVariantAt = os.clock() + self.Random:NextNumber(
		Config.IdleVariantMinSeconds,
		Config.IdleVariantMaxSeconds
	)
end

function LocomotionAnimator:EnterIdle()
	self.Mode = "Idle"
	self.Direction = ""
	self.OneShotActive = false
	self.Tracks:PlayExclusive("IdleBase", Config.AnimationFade)
	self:ScheduleIdleVariant()
end

function LocomotionAnimator:PlayOneShot(name, onFinished)
	self.OneShotToken += 1
	local token = self.OneShotToken
	self.OneShotActive = true
	local track = self.Tracks:PlayExclusive(name, Config.OneShotFade)
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
			self.Tracks:PlayExclusive("IdleBase", Config.AnimationFade)
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
				self.Tracks:PlayExclusive("Jump", Config.AnimationFade)
			end
		else
			if self.Mode ~= "Falling" then
				self.Mode = "Falling"
				self.Tracks:PlayExclusive("Falling", Config.AnimationFade)
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

	-- Ground one-shots must be allowed to finish while the player stays still.
	-- Idle variants and RunStop were previously restarted into IdleBase on the
	-- very next frame, making those animations effectively invisible. Landing
	-- remains non-interruptible; idle/run-stop one-shots can still be cancelled
	-- immediately when the player starts moving.
	if self.OneShotActive then
		if self.Mode == "Landing" or not moving then
			return
		end
	end

	if not moving then
		if self.Mode == "Run" then
			self.Mode = "RunStop"
			self:PlayOneShot("RunStop", function()
				if self.Humanoid.MoveDirection.Magnitude <= Config.MoveDeadzone
					and self.Humanoid.FloorMaterial ~= Enum.Material.Air then
					self:EnterIdle()
				end
			end)
			if self.OneShotActive then
				return
			end
		end

		if self.Mode ~= "Idle" or (self.Tracks:Get("IdleBase") and not self.Tracks:Get("IdleBase").IsPlaying) then
			self:EnterIdle()
		else
			self:UpdateIdleVariant()
		end
		return
	end

	self.OneShotToken += 1
	self.OneShotActive = false

	if isRunning then
		if self.Mode ~= "Run" then
			self.Mode = "Run"
			self.Direction = ""
			self.Tracks:PlayExclusive(randomFrom(self.Random, runTracks), Config.AnimationFade)
		end
		return
	end

	local direction = DirectionResolver.Resolve(root, humanoid.MoveDirection)
	if self.Mode ~= "Walk" or self.Direction ~= direction then
		self.Mode = "Walk"
		self.Direction = direction
		self.Tracks:PlayExclusive(randomFrom(self.Random, walkTracks[direction]), Config.AnimationFade)
	end
end

function LocomotionAnimator:Destroy()
	self.OneShotToken += 1
	self.Tracks:Destroy()
end

return LocomotionAnimator
