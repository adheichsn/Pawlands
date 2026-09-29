local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PlayerCombat)
local SlimeMovementConfig = require(Shared.Config.SlimeMovement)
local SlimeHealth = require(script.Parent.Parent.Slimes.SlimeHealth)
local CombatValidation = require(script.Parent.CombatValidation)

local CombatService = {}
local started = false
local attackConnection
local removingConnection
local lastAttackByPlayer = {}

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

local function processAttack(player, target, aimDirection)
	local now = os.clock()
	local previous = lastAttackByPlayer[player] or -math.huge
	if now - previous < Config.AttackCooldown then
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
	local validTarget = CombatValidation.ValidateTarget(target, folder, SlimeHealth)
	if not validTarget then
		return
	end
	if not CombatValidation.InRange(playerState.Root, target, Config.AttackRange) then
		return
	end
	if not CombatValidation.InAim(playerState.Root, target, aimDirection, Config) then
		return
	end
	if Config.RequireLineOfSight
		and not CombatValidation.HasLineOfSight(playerState.Character, target, folder) then
		return
	end

	-- Consume cooldown only after every authoritative hit check passes.
	lastAttackByPlayer[player] = now
	local applied, health = SlimeHealth.ApplyDamage(target, Config.Damage, player)
	if applied and RunService:IsStudio() then
		print(string.format(
			"[Pawlands Combat] %s hit %s for %d damage (%d/%d HP).",
			player.Name,
			tostring(target:GetAttribute("SlimeId") or target.Name),
			Config.Damage,
			health,
			target:GetAttribute("MaxHealth") or health
		))
	end
end

function CombatService.Start()
	if started then
		return
	end
	started = true
	local remote = ensureRemote()
	attackConnection = remote.OnServerEvent:Connect(processAttack)
	removingConnection = Players.PlayerRemoving:Connect(function(player)
		lastAttackByPlayer[player] = nil
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
	table.clear(lastAttackByPlayer)
end

return CombatService
