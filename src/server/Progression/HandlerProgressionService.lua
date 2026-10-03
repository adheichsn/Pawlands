local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.HandlerProgression)
local ProgressionMath = require(Shared.Progression.ProgressionMath)

local HandlerProgressionService = {}
local started = false
local stateByPlayer = {}
local characterConnections = {}
local profileService = nil
local addedConnection = nil
local removingConnection = nil

local BASE_MAX_HEALTH_ATTRIBUTE = "PawlandsHandlerBaseMaxHealth"

local function validPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function finiteNonNegative(value)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return nil
	end
	return value
end

local function publish(player, snapshot)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(Config.LevelAttributeName, snapshot.Level)
	player:SetAttribute(Config.ExperienceAttributeName, snapshot.Experience)
	player:SetAttribute(Config.ExperienceIntoLevelAttributeName, snapshot.ExperienceIntoLevel)
	player:SetAttribute(Config.ExperienceToNextLevelAttributeName, snapshot.ExperienceToNextLevel)
end

local function makeSnapshot(totalExperience)
	local resolved = ProgressionMath.Resolve(totalExperience, Config)
	return {
		Level = resolved.Level,
		MaxLevel = resolved.MaxLevel,
		Experience = resolved.TotalExperience,
		ExperienceIntoLevel = resolved.ExperienceIntoLevel,
		ExperienceToNextLevel = resolved.ExperienceToNextLevel,
		MaxTotalExperience = resolved.MaxTotalExperience,
		IsMaxLevel = resolved.IsMaxLevel,
	}
end

local function getHumanoid(character)
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		return humanoid
	end
	local candidate = character:WaitForChild("Humanoid", 5)
	return candidate and candidate:IsA("Humanoid") and candidate or nil
end

local function authoredBaseMaxHealth(humanoid)
	local stored = tonumber(humanoid:GetAttribute(BASE_MAX_HEALTH_ATTRIBUTE))
	if stored and stored > 0 and stored == stored and stored ~= math.huge then
		return stored
	end
	local current = tonumber(humanoid.MaxHealth)
	if not current or current <= 0 or current ~= current or current == math.huge then
		current = 100
	end
	humanoid:SetAttribute(BASE_MAX_HEALTH_ATTRIBUTE, current)
	return current
end

local function applyCharacterHealth(player, character, preserveRatio)
	if not started or player.Parent ~= Players or player.Character ~= character then
		return
	end
	local snapshot = stateByPlayer[player]
	if not snapshot then
		return
	end
	local humanoid = getHumanoid(character)
	if not humanoid or player.Character ~= character then
		return
	end

	local baseMaxHealth = authoredBaseMaxHealth(humanoid)
	local multiplier = ProgressionMath.GrowthMultiplier(Config.MaxHealthGrowthPerLevel, snapshot.Level, Config)
	local nextMaxHealth = math.max(1, math.floor(baseMaxHealth * multiplier + 0.5))
	local oldMaxHealth = math.max(1, tonumber(humanoid.MaxHealth) or baseMaxHealth)
	local oldHealth = math.clamp(tonumber(humanoid.Health) or 0, 0, oldMaxHealth)
	local healthRatio = oldHealth / oldMaxHealth

	humanoid.MaxHealth = nextMaxHealth
	if oldHealth <= 0 then
		humanoid.Health = 0
	elseif preserveRatio then
		humanoid.Health = math.clamp(nextMaxHealth * healthRatio, 0, nextMaxHealth)
	else
		-- A newly spawned Handler starts at the full MaxHealth granted by the
		-- already-loaded level. Level changes during life preserve health ratio.
		humanoid.Health = nextMaxHealth
	end
end

local function connectCharacter(player)
	if characterConnections[player] then
		characterConnections[player]:Disconnect()
	end
	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		task.defer(applyCharacterHealth, player, character, false)
	end)
	if player.Character then
		task.defer(applyCharacterHealth, player, player.Character, false)
	end
end

local function initializePlayer(player)
	local profile = profileService and profileService.AwaitReady(player)
	if not profile or player.Parent ~= Players then
		return
	end
	local saved = profileService.GetHandlerSnapshot(player) or {}
	local snapshot = makeSnapshot(saved.Experience or 0)
	stateByPlayer[player] = snapshot
	publish(player, snapshot)
	connectCharacter(player)
end

function HandlerProgressionService.GetSnapshot(player)
	local snapshot = stateByPlayer[player]
	return snapshot and table.clone(snapshot) or nil
end

function HandlerProgressionService.SetExperience(player, totalExperience)
	if not started then
		return nil, "Handler progression service is unavailable."
	end
	if not validPlayer(player) then
		return nil, "Player is not in this server."
	end
	local requested = finiteNonNegative(totalExperience)
	if not requested then
		return nil, "Handler experience must be a finite non-negative number."
	end
	local snapshot = makeSnapshot(requested)
	local persisted, persistReason = profileService.SetHandlerProgression(player, snapshot.Level, snapshot.Experience)
	if not persisted then
		return nil, persistReason
	end
	stateByPlayer[player] = snapshot
	publish(player, snapshot)
	if player.Character then
		applyCharacterHealth(player, player.Character, true)
	end
	return table.clone(snapshot), nil
end

function HandlerProgressionService.AddExperience(player, amount)
	local gain = finiteNonNegative(amount)
	if not gain then
		return nil, 0, "Handler experience gain must be a finite non-negative number."
	end
	local before = HandlerProgressionService.GetSnapshot(player)
	if not before then
		return nil, 0, "Handler progression is not initialized."
	end
	if before.IsMaxLevel or gain <= 0 then
		return before, 0, nil
	end
	local after, reason = HandlerProgressionService.SetExperience(player, before.Experience + gain)
	if not after then
		return nil, 0, reason
	end
	return after, math.max(0, after.Level - before.Level), nil
end

function HandlerProgressionService.GetDamageMultiplier(player)
	local snapshot = HandlerProgressionService.GetSnapshot(player)
	if not snapshot then
		return 1
	end
	return ProgressionMath.GrowthMultiplier(Config.DamageGrowthPerLevel, snapshot.Level, Config)
end

function HandlerProgressionService.GetMaxHealthMultiplier(player)
	local snapshot = HandlerProgressionService.GetSnapshot(player)
	if not snapshot then
		return 1
	end
	return ProgressionMath.GrowthMultiplier(Config.MaxHealthGrowthPerLevel, snapshot.Level, Config)
end

function HandlerProgressionService.Start(playerProfileService)
	if started then
		return
	end
	if not playerProfileService then
		error("HandlerProgressionService requires PlayerProfileService.")
	end
	profileService = playerProfileService
	started = true
	addedConnection = Players.PlayerAdded:Connect(initializePlayer)
	removingConnection = Players.PlayerRemoving:Connect(function(player)
		stateByPlayer[player] = nil
		if characterConnections[player] then
			characterConnections[player]:Disconnect()
			characterConnections[player] = nil
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		initializePlayer(player)
	end
end

function HandlerProgressionService.Stop()
	if not started then
		return
	end
	started = false
	if addedConnection then
		addedConnection:Disconnect()
		addedConnection = nil
	end
	if removingConnection then
		removingConnection:Disconnect()
		removingConnection = nil
	end
	for player, connection in pairs(characterConnections) do
		connection:Disconnect()
		characterConnections[player] = nil
	end
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute(Config.LevelAttributeName, nil)
		player:SetAttribute(Config.ExperienceAttributeName, nil)
		player:SetAttribute(Config.ExperienceIntoLevelAttributeName, nil)
		player:SetAttribute(Config.ExperienceToNextLevelAttributeName, nil)
	end
	table.clear(stateByPlayer)
	profileService = nil
end

return HandlerProgressionService
