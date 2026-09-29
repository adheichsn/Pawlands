local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PlayerMovement)
local RunToggleController = require(script.Parent.Movement.RunToggleController)
local LocomotionAnimator = require(script.Parent.Animation.LocomotionAnimator)

local PlayerMovementController = {}
local stopCurrent
local activeRunToggle

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

	local function cleanupCharacter()
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
		if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
			warn("[Pawlands Movement] Custom locomotion is authored for R6; runtime skipped.")
			return
		end
		local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator")
		local animateConnection = disableDefaultAnimate(character)
		stopPlayingLocomotionTracks(animator)

		humanoid.WalkSpeed = Config.WalkSpeed
		local locomotion = LocomotionAnimator.new(humanoid, root, animator)
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
			humanoid.WalkSpeed = running and Config.RunSpeed or Config.WalkSpeed
		end
	end)
	activeRunToggle = runToggle

	local addedConnection = player.CharacterAdded:Connect(bindCharacter)
	local removingConnection = player.CharacterRemoving:Connect(cleanupCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end

	stopCurrent = function()
		addedConnection:Disconnect()
		removingConnection:Disconnect()
		cleanupCharacter()
		if runToggle then
			runToggle:Destroy()
			runToggle = nil
		end
		activeRunToggle = nil
	end
end

function PlayerMovementController.IsRunning()
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
