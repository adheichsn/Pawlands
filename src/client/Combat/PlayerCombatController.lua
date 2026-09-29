local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PlayerCombat)
local MovementConfig = require(Shared.Config.PlayerMovement)
local CombatTargeting = require(script.Parent.CombatTargeting)
local PlayerAttackAnimator = require(script.Parent.PlayerAttackAnimator)

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

local function isActivelyRunning(humanoid, root)
	if humanoid.WalkSpeed < MovementConfig.RunSpeed - 0.1 or humanoid.MoveDirection.Magnitude <= 0.10 then
		return false
	end
	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	return horizontalSpeed >= Config.RunningAttackMinHorizontalSpeed
end

function PlayerCombatController.Start()
	if stopCurrent then
		return
	end

	local player = Players.LocalPlayer
	local mouse = player:GetMouse()
	local remote = getRemote()
	local animatorRuntime
	local humanoid
	local root
	local character
	local comboIndex = 0
	local lastAttackAt = -math.huge

	local function cleanupCharacter()
		if animatorRuntime then
			animatorRuntime:Destroy()
			animatorRuntime = nil
		end
		character, humanoid, root = nil, nil, nil
		comboIndex = 0
		lastAttackAt = -math.huge
	end

	local function bindCharacter(newCharacter)
		cleanupCharacter()
		character = newCharacter
		humanoid = newCharacter:WaitForChild("Humanoid")
		root = newCharacter:WaitForChild("HumanoidRootPart")
		local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator")
		animatorRuntime = PlayerAttackAnimator.new(animator)
	end

	local function tryAttack()
		if not character or not humanoid or not root or humanoid.Health <= 0 then
			return false
		end
		if Config.RequireGrounded and not isGrounded(humanoid) then
			return false
		end

		local now = os.clock()
		if now - lastAttackAt < Config.AttackCooldown then
			return false
		end
		if now - lastAttackAt > Config.ComboResetSeconds then
			comboIndex = 0
		end

		local freshChain = comboIndex == 0
		local runningAttack = freshChain and isActivelyRunning(humanoid, root)
		if runningAttack then
			-- Mark the chain as started; the next click continues at M1 combo 1.
			comboIndex = 4
			if animatorRuntime then
				animatorRuntime:PlayRunning()
			end
		else
			comboIndex = comboIndex % 4 + 1
			if animatorRuntime then
				animatorRuntime:PlayCombo(comboIndex)
			end
		end
		lastAttackAt = now

		-- Targeting happens after the swing is accepted locally. Missing a slime is
		-- a valid whiff, so M1 never depends on clicking a model directly.
		local target, aimDirection = CombatTargeting.Acquire(character, root, mouse.Target, Config)
		if target then
			remote:FireServer(target, aimDirection)
		end
		return true
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

-- Future Studio-owned mobile/gamepad input can call this same entry point.
-- No touch GUI is created by runtime code.
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
