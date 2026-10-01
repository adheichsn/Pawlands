local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PlayerMovement)
local RunToggleController = require(script.Parent.Movement.RunToggleController)
local LocomotionAnimator = require(script.Parent.Animation.LocomotionAnimator)
local InteractionLock = require(script.Parent.Parent.Interaction.InteractionLock)

local PlayerMovementController = {}
local stopCurrent
local activeRunToggle

local function isMovementLocked()
	-- Inventory remains an interaction/action lock so combat clicks and overlapping
	-- modals stay blocked, but it does not freeze local locomotion.
	return InteractionLock.IsLockedExcept("Inventory")
end

local function disableDefaultAnimate(character)
	local function disable(instance)
		if instance.Name == "Animate" and instance:IsA("LocalScript") then
			instance.Disabled = true
		end
	end

	local existing = character:FindFirstChild("Animate")
	if existing then
		disable(existing)
	end
	return character.ChildAdded:Connect(disable)
end

local function stopPlayingLocomotionTracks(animator)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Priority == Enum.AnimationPriority.Idle
			or track.Priority == Enum.AnimationPriority.Movement
		then
			track:Stop(0)
		end
	end
end

function PlayerMovementController.Start()
	if stopCurrent then
		return
	end

	local player = Players.LocalPlayer
	local characterCleanup
	local runToggle
	local speedTween
	local activeHumanoid
	local activeRoot
	local jumpStateWasEnabled
	local movementLockedState

	local function cancelSpeedTween()
		if speedTween then
			speedTween:Cancel()
			speedTween = nil
		end
	end

	local function setMovementLocked(locked)
		locked = locked == true
		if movementLockedState == locked then
			return
		end
		movementLockedState = locked

		local humanoid = activeHumanoid
		if not humanoid or not humanoid.Parent then
			return
		end

		cancelSpeedTween()
		if locked then
			if runToggle then
				runToggle:Reset()
			end
			if jumpStateWasEnabled == nil then
				jumpStateWasEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
			end
			humanoid.WalkSpeed = 0
			humanoid.Jump = false
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			if activeRoot and activeRoot.Parent then
				local velocity = activeRoot.AssemblyLinearVelocity
				activeRoot.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
			end
		else
			if jumpStateWasEnabled ~= nil then
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, jumpStateWasEnabled)
				jumpStateWasEnabled = nil
			end
			humanoid.WalkSpeed = Config.WalkSpeed
		end
	end

	local function cleanupCharacter()
		cancelSpeedTween()
		if activeHumanoid and activeHumanoid.Parent and jumpStateWasEnabled ~= nil then
			activeHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, jumpStateWasEnabled)
		end
		jumpStateWasEnabled = nil
		movementLockedState = nil
		activeHumanoid = nil
		activeRoot = nil
		if characterCleanup then
			characterCleanup()
			characterCleanup = nil
		end
	end

	local function bindCharacter(character)
		cleanupCharacter()
		if runToggle then
			runToggle:Reset()
		end

		local humanoid = character:WaitForChild("Humanoid")
		local root = character:WaitForChild("HumanoidRootPart")
		activeHumanoid = humanoid
		activeRoot = root
		if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
			warn("[Pawlands Movement] Custom locomotion is authored for R6; runtime skipped.")
			return
		end
		local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator")
		local animateConnection = disableDefaultAnimate(character)
		stopPlayingLocomotionTracks(animator)

		humanoid.WalkSpeed = Config.WalkSpeed
		local locomotion = LocomotionAnimator.new(humanoid, root, animator)
		setMovementLocked(isMovementLocked())
		local updateConnection = RunService.PreRender:Connect(function()
			locomotion:Update(runToggle and runToggle:IsRunning() or false)
		end)

		characterCleanup = function()
			updateConnection:Disconnect()
			animateConnection:Disconnect()
			locomotion:Destroy()
		end
	end

	runToggle = RunToggleController.new(function(running)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			cancelSpeedTween()
			if isMovementLocked() then
				humanoid.WalkSpeed = 0
				return
			end
			local targetSpeed = running and Config.RunSpeed or Config.WalkSpeed
			if Config.SpeedTransitionSeconds > 0 then
				speedTween = TweenService:Create(
					humanoid,
					TweenInfo.new(
						Config.SpeedTransitionSeconds,
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.Out
					),
					{ WalkSpeed = targetSpeed }
				)
				speedTween:Play()
			else
				humanoid.WalkSpeed = targetSpeed
			end
		end
	end)
	activeRunToggle = runToggle

	local stopLockObserver = InteractionLock.Subscribe(function()
		setMovementLocked(isMovementLocked())
	end)
	local addedConnection = player.CharacterAdded:Connect(bindCharacter)
	local removingConnection = player.CharacterRemoving:Connect(cleanupCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end

	stopCurrent = function()
		addedConnection:Disconnect()
		removingConnection:Disconnect()
		stopLockObserver()
		cleanupCharacter()
		if runToggle then
			runToggle:Destroy()
			runToggle = nil
		end
		activeRunToggle = nil
	end
end

function PlayerMovementController.IsRunning()
	if isMovementLocked() then
		return false
	end
	return activeRunToggle and activeRunToggle:IsRunning() or false
end

function PlayerMovementController.Stop()
	if stopCurrent then
		local stop = stopCurrent
		stopCurrent = nil
		stop()
	end
end

return PlayerMovementController
