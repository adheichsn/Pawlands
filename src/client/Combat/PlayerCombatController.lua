local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PlayerCombat)
local CombatTargeting = require(script.Parent.CombatTargeting)
local PlayerAttackAnimator = require(script.Parent.PlayerAttackAnimator)

local PlayerCombatController = {}
local stopCurrent

local function getRemote()
	local pawlands = ReplicatedStorage:WaitForChild("Pawlands")
	local remotes = pawlands:WaitForChild(Config.RemoteFolderName)
	return remotes:WaitForChild(Config.AttackRemoteName)
end

local function isGrounded(humanoid)
	return humanoid.FloorMaterial ~= Enum.Material.Air
		and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
end

function PlayerCombatController.Start()
	if stopCurrent then
		return
	end

	local player = Players.LocalPlayer
	local mouse = player:GetMouse()
	local remote = getRemote()
	local characterCleanup
	local animatorRuntime
	local humanoid
	local root
	local comboIndex = 0
	local lastAttackAt = -math.huge

	local function cleanupCharacter()
		if animatorRuntime then
			animatorRuntime:Destroy()
			animatorRuntime = nil
		end
		humanoid, root = nil, nil
		comboIndex = 0
		lastAttackAt = -math.huge
	end

	local function bindCharacter(character)
		cleanupCharacter()
		humanoid = character:WaitForChild("Humanoid")
		root = character:WaitForChild("HumanoidRootPart")
		local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator")
		animatorRuntime = PlayerAttackAnimator.new(animator)
	end

	local function tryAttack()
		if not humanoid or not root or humanoid.Health <= 0 then
			return
		end
		if Config.RequireGrounded and not isGrounded(humanoid) then
			return
		end

		local target = CombatTargeting.ResolveFromPart(mouse.Target)
		if not CombatTargeting.IsAlive(target) then
			return
		end
		if (target:GetPivot().Position - root.Position).Magnitude > Config.ClientTargetMaxDistance then
			return
		end

		local now = os.clock()
		if now - lastAttackAt < Config.AttackCooldown then
			return
		end
		if now - lastAttackAt > Config.ComboResetSeconds then
			comboIndex = 0
		end
		comboIndex = comboIndex % 4 + 1
		lastAttackAt = now

		if animatorRuntime then
			animatorRuntime:Play(comboIndex)
		end
		remote:FireServer(target)
	end

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
		cleanupCharacter()
	end
end

function PlayerCombatController.Stop()
	if stopCurrent then
		local stop = stopCurrent
		stopCurrent = nil
		stop()
	end
end

return PlayerCombatController
