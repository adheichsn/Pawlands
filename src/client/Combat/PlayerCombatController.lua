local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PlayerCombat)
local CombatTargeting = require(script.Parent.CombatTargeting)
local CombatContactRuntime = require(script.Parent.CombatContactRuntime)
local CombatEffects = require(script.Parent.CombatEffects)
local PlayerAttackAnimator = require(script.Parent.PlayerAttackAnimator)
local ComboFlow = require(script.Parent.ComboFlow)
local PlayerMovementController = require(script.Parent.Parent.Player.PlayerMovementController)
local InteractionLock = require(script.Parent.Parent.Interaction.InteractionLock)

local PlayerCombatController = {}
local stopCurrent
local attackCurrent

local function getRemote()
	local pawlands = ReplicatedStorage:WaitForChild("Pawlands")
	local remotes = pawlands:WaitForChild(Config.RemoteFolderName)
	return remotes:WaitForChild(Config.AttackRemoteName)
end

local function isGrounded(humanoid)
	return humanoid.FloorMaterial ~= Enum.Material.Air
		and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
end

local function horizontalSpeed(root)
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

function PlayerCombatController.Start()
	if stopCurrent then
		return
	end

	local player = Players.LocalPlayer
	local mouse = player:GetMouse()
	local remote = getRemote()
	local animatorRuntime
	local comboRuntime
	local humanoid
	local root
	local character

	local function cleanupCharacter()
		if comboRuntime then
			comboRuntime:Destroy()
			comboRuntime = nil
		end
		if animatorRuntime then
			animatorRuntime:Destroy()
			animatorRuntime = nil
		end
		character, humanoid, root = nil, nil, nil
	end

	local function bindCharacter(newCharacter)
		cleanupCharacter()
		character = newCharacter
		humanoid = newCharacter:WaitForChild("Humanoid")
		root = newCharacter:WaitForChild("HumanoidRootPart")
		local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator")
		animatorRuntime = PlayerAttackAnimator.new(animator)

		comboRuntime = ComboFlow.new(Config, {
			OnAttack = function(kind, comboIndex)
				if not character or not root or not humanoid or humanoid.Health <= 0 then
					return
				end

				if kind == Config.ActionTypes.RunningAttack then
					animatorRuntime:PlayRunning()
				else
					animatorRuntime:PlayCombo(comboIndex)
					CombatEffects.PlaySwing(character, comboIndex)
				end

				-- Preferred target only improves local facing/contact presentation. The
				-- server resolves the actual victim from the forward melee volume.
				local preferred, fallbackAim = CombatTargeting.Acquire(character, root, mouse.Target, Config)
				local aimDirection = CombatContactRuntime.PrepareAttack(
					character,
					preferred,
					Config,
					fallbackAim
				)
				remote:FireServer(kind, comboIndex, aimDirection, preferred)
			end,
		})
	end

	local function tryAttack()
		if InteractionLock.IsLocked() then
			return false
		end
		if not character or not humanoid or not root or humanoid.Health <= 0 or not comboRuntime then
			return false
		end
		if Config.RequireGrounded and not isGrounded(humanoid) then
			return false
		end

		local running = PlayerMovementController.IsRunning()
			and humanoid.MoveDirection.Magnitude > 0.10
			and horizontalSpeed(root) >= Config.RunningAttack.ClientMinimumHorizontalSpeedStuds
		return comboRuntime:Request(running)
	end

	attackCurrent = tryAttack
	local inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			tryAttack()
		end
	end)

	local addedConnection = player.CharacterAdded:Connect(bindCharacter)
	local removingConnection = player.CharacterRemoving:Connect(cleanupCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end

	stopCurrent = function()
		inputConnection:Disconnect()
		addedConnection:Disconnect()
		removingConnection:Disconnect()
		attackCurrent = nil
		cleanupCharacter()
	end
end

-- Future Studio-owned mobile/gamepad input can call the same entry point without
-- changing targeting, cadence, or server authority.
function PlayerCombatController.Attack()
	return attackCurrent and attackCurrent() or false
end

function PlayerCombatController.Stop()
	if stopCurrent then
		local stop = stopCurrent
		stopCurrent = nil
		stop()
	end
end

return PlayerCombatController
