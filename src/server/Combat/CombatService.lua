local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PlayerCombat)
local SlimeMovementConfig = require(Shared.Config.SlimeMovement)
local SlimeHealth = require(script.Parent.Parent.Slimes.SlimeHealth)
local CombatValidation = require(script.Parent.CombatValidation)
local PlayerHitboxResolver = require(script.Parent.PlayerHitboxResolver)

local CombatService = {}
local started = false
local attackConnection
local removingConnection
local stateByPlayer = {}

local function ensureRemote()
	local pawlands = ReplicatedStorage:WaitForChild("Pawlands")
	local folder = pawlands:FindFirstChild(Config.RemoteFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Config.RemoteFolderName
		folder.Parent = pawlands
	end
	local remote = folder:FindFirstChild(Config.AttackRemoteName)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = Config.AttackRemoteName
		remote.Parent = folder
	end
	return remote
end

local function runtimeFolder()
	local folder = Workspace:FindFirstChild(SlimeMovementConfig.RuntimeFolderName)
	return folder and folder:IsA("Folder") and folder or nil
end

local function getState(player)
	local state = stateByPlayer[player]
	if state then
		return state
	end
	state = {
		LastRequestAt = -math.huge,
		LastM1At = -math.huge,
		NextAttackAt = 0,
		ComboIndex = 0,
		Generation = 0,
	}
	stateByPlayer[player] = state
	return state
end

local function resolveAction(state, actionType, comboIndex, now)
	if actionType == Config.ActionTypes.RunningAttack then
		if comboIndex ~= 0 then
			return nil
		end
		state.ComboIndex = 0
		state.LastM1At = -math.huge
		return Config.RunningAttack, Config.GetRunningImpactDelay(), Config.RunningAttack.DamageMultiplier
	end

	if actionType ~= Config.ActionTypes.M1 then
		return nil
	end
	if type(comboIndex) ~= "number" then
		return nil
	end
	comboIndex = math.floor(comboIndex)
	local expired = now - state.LastM1At > Config.ComboResetSeconds
	local expected = expired and 1 or ((state.ComboIndex % #Config.Combo) + 1)
	if comboIndex ~= expected then
		return nil
	end
	local definition = Config.GetComboDefinition(comboIndex)
	if not definition then
		return nil
	end
	state.ComboIndex = comboIndex
	state.LastM1At = now
	return definition, Config.GetComboImpactDelay(comboIndex), definition.DamageMultiplier
end

local function applyImpact(player, generation, aimDirection, preferredTarget, damageMultiplier, feedbackTier)
	local state = stateByPlayer[player]
	if not state or state.Generation ~= generation then
		return
	end
	local playerState = CombatValidation.ValidatePlayer(player, Config)
	if not playerState then
		return
	end
	local folder = runtimeFolder()
	if not folder then
		return
	end
	local aim = CombatValidation.ResolveAim(playerState.Root, aimDirection, Config)
	local target = PlayerHitboxResolver.Resolve(
		playerState,
		aim,
		preferredTarget,
		folder,
		Config,
		SlimeHealth,
		CombatValidation
	)
	if not target then
		return
	end

	local damage = math.max(1, math.floor(Config.Damage * damageMultiplier + 0.5))
	local targetPosition = target:GetPivot().Position
	local hitDirection = Vector3.new(
		targetPosition.X - playerState.Root.Position.X,
		0,
		targetPosition.Z - playerState.Root.Position.Z
	)
	if hitDirection.Magnitude > 0.001 then
		hitDirection = hitDirection.Unit
	else
		hitDirection = aim
	end
	local applied, health = SlimeHealth.ApplyDamage(target, damage, player, {
		Tier = feedbackTier,
		Direction = hitDirection,
	})
	if applied and RunService:IsStudio() then
		print(string.format(
			"[Pawlands Combat] %s hit %s for %d damage (%d/%d HP).",
			player.Name,
			tostring(target:GetAttribute("SlimeId") or target.Name),
			damage,
			health,
			target:GetAttribute("MaxHealth") or health
		))
	end
end

local function processAttack(player, actionType, comboIndex, aimDirection, preferredTarget)
	local now = os.clock()
	local state = getState(player)
	if now - state.LastRequestAt < Config.RequestRateLimitSeconds then
		return
	end
	state.LastRequestAt = now

	local playerState = CombatValidation.ValidatePlayer(player, Config)
	if not playerState then
		return
	end
	if now + Config.CadenceToleranceSeconds < state.NextAttackAt then
		return
	end
	if actionType == Config.ActionTypes.RunningAttack
		and not CombatValidation.IsRunningAttackValid(playerState, Config)
	then
		return
	end

	local definition, impactDelay, multiplier = resolveAction(state, actionType, comboIndex, now)
	if not definition then
		return
	end
	state.NextAttackAt = now + definition.CadenceSeconds
	state.Generation += 1
	local generation = state.Generation
	local boundedAim = CombatValidation.ResolveAim(playerState.Root, aimDirection, Config)
	local feedbackTier = "Light"
	if actionType == Config.ActionTypes.M1 and comboIndex == #Config.Combo then
		feedbackTier = "Finisher"
	end
	local validPreferred = nil
	local folder = runtimeFolder()
	if folder and CombatValidation.ValidateTarget(preferredTarget, folder, SlimeHealth) then
		validPreferred = preferredTarget
	end

	task.delay(math.max(0, impactDelay), function()
		applyImpact(player, generation, boundedAim, validPreferred, multiplier or 1, feedbackTier)
	end)
end

function CombatService.Start()
	if started then
		return
	end
	started = true
	local remote = ensureRemote()
	attackConnection = remote.OnServerEvent:Connect(processAttack)
	removingConnection = Players.PlayerRemoving:Connect(function(player)
		stateByPlayer[player] = nil
	end)
end

function CombatService.Stop()
	if not started then
		return
	end
	started = false
	if attackConnection then
		attackConnection:Disconnect()
		attackConnection = nil
	end
	if removingConnection then
		removingConnection:Disconnect()
		removingConnection = nil
	end
	table.clear(stateByPlayer)
end

return CombatService
