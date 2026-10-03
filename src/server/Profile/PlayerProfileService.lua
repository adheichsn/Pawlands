local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.Profile)
local TutorialConfig = require(Shared.Config.Tutorial)
local EconomyConfig = require(Shared.Config.Economy)
local Schema = require(script.Parent.ProfileSchema)
local Store = require(script.Parent.ProfileStore)

local PlayerProfileService = {}
local states = {}
local started = false
local closing = false
local playerAddedConnection = nil
local playerRemovingConnection = nil

local PERSISTED_TUTORIAL_ATTRIBUTES = table.freeze({
	TutorialConfig.StageAttributeName,
	TutorialConfig.StarterPetGrantedAttributeName,
	TutorialConfig.StarterPetUidAttributeName,
	TutorialConfig.StarterPetSpeciesAttributeName,
	TutorialConfig.StarterPetHitConfirmedAttributeName,
})

local function validPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player")
end

local function stateFor(player)
	return states[player]
end

local function markDirty(state)
	if not state or state.Status ~= "Ready" or state.Releasing then
		return
	end
	state.Revision += 1
	state.Dirty = true
end

local function applyTutorialAttributes(player, profile)
	local tutorial = profile.Tutorial
	player:SetAttribute(TutorialConfig.StageAttributeName, tutorial.Stage)
	player:SetAttribute(TutorialConfig.StarterPetGrantedAttributeName, tutorial.StarterPetGranted == true)
	player:SetAttribute(TutorialConfig.StarterPetUidAttributeName, tutorial.StarterPetUid or "")
	player:SetAttribute(TutorialConfig.StarterPetSpeciesAttributeName, tutorial.StarterPetSpecies or "")
	player:SetAttribute(TutorialConfig.StarterPetHitConfirmedAttributeName, tutorial.StarterPetHitConfirmed == true)
end

local function syncTutorialFromAttributes(player, state)
	if not state or state.Status ~= "Ready" or state.ApplyingAttributes or state.Releasing then
		return
	end
	local tutorial = state.Profile.Tutorial
	local changed = false

	local stage = player:GetAttribute(TutorialConfig.StageAttributeName)
	if type(stage) == "string" and TutorialConfig.Stages[stage] ~= nil and tutorial.Stage ~= stage then
		tutorial.Stage = stage
		changed = true
	end
	local granted = player:GetAttribute(TutorialConfig.StarterPetGrantedAttributeName) == true
	if tutorial.StarterPetGranted ~= granted then
		tutorial.StarterPetGranted = granted
		changed = true
	end
	local uid = player:GetAttribute(TutorialConfig.StarterPetUidAttributeName)
	uid = type(uid) == "string" and uid or ""
	if tutorial.StarterPetUid ~= uid then
		tutorial.StarterPetUid = uid
		changed = true
	end
	local species = player:GetAttribute(TutorialConfig.StarterPetSpeciesAttributeName)
	species = type(species) == "string" and species or ""
	if tutorial.StarterPetSpecies ~= species then
		tutorial.StarterPetSpecies = species
		changed = true
	end
	local hitConfirmed = player:GetAttribute(TutorialConfig.StarterPetHitConfirmedAttributeName) == true
	if tutorial.StarterPetHitConfirmed ~= hitConfirmed then
		tutorial.StarterPetHitConfirmed = hitConfirmed
		changed = true
	end

	if changed then
		markDirty(state)
	end
end

local function disconnectStateConnections(state)
	if not state then
		return
	end
	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end
	table.clear(state.Connections)
end

local function connectTutorialTracking(player, state)
	for _, attributeName in ipairs(PERSISTED_TUTORIAL_ATTRIBUTES) do
		table.insert(state.Connections, player:GetAttributeChangedSignal(attributeName):Connect(function()
			syncTutorialFromAttributes(player, state)
		end))
	end
end

local function loadPlayer(player)
	if not validPlayer(player) or states[player] then
		return
	end
	local state = {
		Status = "Loading",
		Profile = nil,
		Dirty = false,
		Revision = 0,
		Saving = false,
		Releasing = false,
		ApplyingAttributes = false,
		Connections = {},
	}
	states[player] = state
	player:SetAttribute(Config.ReadyAttributeName, false)
	player:SetAttribute(Config.PersistentAttributeName, Store.IsPersistent())
	player:SetAttribute(Config.FailureAttributeName, false)

	local profile, reason = Store.Load(player.UserId)
	if not profile then
		state.Status = "Failed"
		player:SetAttribute(Config.FailureAttributeName, true)
		warn(string.format("[Pawlands Profile] Failed to load %s: %s", player.Name, tostring(reason)))
		if player.Parent == Players then
			task.defer(function()
				if player.Parent == Players then
					player:Kick(Config.LoadFailureKickMessage)
				end
			end)
		end
		return
	end

	-- A Player can leave while a persistent UpdateAsync is yielding. Release the
	-- newly acquired lock instead of leaving a ghost session behind.
	if player.Parent ~= Players or closing then
		Store.Release(player.UserId, profile)
		states[player] = nil
		return
	end

	state.Profile = Schema.NormalizeData(profile)
	state.ApplyingAttributes = true
	applyTutorialAttributes(player, state.Profile)
	state.ApplyingAttributes = false
	state.Status = "Ready"
	connectTutorialTracking(player, state)
	player:SetAttribute(Config.ReadyAttributeName, true)
end

local function saveState(player, state, release)
	if not state or state.Status ~= "Ready" or state.Saving then
		return false, "Profile is not ready for save."
	end
	state.Saving = true
	if release then
		state.Releasing = true
	end
	local revision = state.Revision
	local snapshot = Schema.DeepCopy(state.Profile)
	local ok, reason
	if release then
		ok, reason = Store.Release(player.UserId, snapshot)
	else
		ok, reason = Store.Save(player.UserId, snapshot)
	end
	state.Saving = false

	if ok then
		if state.Revision == revision then
			state.Dirty = false
		end
	else
		state.Releasing = false
		warn(string.format("[Pawlands Profile] Failed to save %s: %s", player.Name, tostring(reason)))
	end
	return ok, reason
end

local function releasePlayer(player)
	local state = stateFor(player)
	if not state then
		return
	end

	-- PlayerRemoving can race an autosave. Wait for that write to finish so the
	-- final release cannot silently skip clearing the session lock.
	local waitDeadline = os.clock() + 12
	while state.Saving and os.clock() < waitDeadline do
		task.wait(0.05)
	end

	if state.Status == "Ready" and not state.Releasing then
		saveState(player, state, true)
	end
	disconnectStateConnections(state)
	states[player] = nil
end

local function mutate(player, callback)
	local state = stateFor(player)
	if not state or state.Status ~= "Ready" or state.Releasing then
		return false, "Player profile is not ready."
	end
	local changed, reason = callback(state.Profile)
	if changed == nil then
		return false, reason or "Profile mutation failed."
	end
	if changed == true then
		markDirty(state)
	end
	return true, nil
end

function PlayerProfileService.AwaitReady(player)
	if not validPlayer(player) then
		return nil, "Invalid Player."
	end
	while true do
		local state = stateFor(player)
		if state then
			if state.Status == "Ready" then
				return Schema.DeepCopy(state.Profile), nil
			elseif state.Status == "Failed" then
				return nil, "Player profile failed to load."
			end
		end
		if player.Parent ~= Players or closing then
			return nil, "Player left before profile became ready."
		end
		task.wait(0.05)
	end
end

function PlayerProfileService.IsReady(player)
	local state = stateFor(player)
	return state ~= nil and state.Status == "Ready"
end

function PlayerProfileService.GetSnapshot(player)
	local state = stateFor(player)
	return state and state.Status == "Ready" and Schema.DeepCopy(state.Profile) or nil
end

function PlayerProfileService.GetPetInventorySnapshot(player)
	local profile = PlayerProfileService.GetSnapshot(player)
	return profile and profile.Pets or nil
end

function PlayerProfileService.GetPartySnapshot(player)
	local profile = PlayerProfileService.GetSnapshot(player)
	return profile and table.clone(profile.Party) or {}
end

function PlayerProfileService.GetHandlerSnapshot(player)
	local profile = PlayerProfileService.GetSnapshot(player)
	return profile and table.clone(profile.Handler) or nil
end

function PlayerProfileService.GetEconomySnapshot(player)
	local profile = PlayerProfileService.GetSnapshot(player)
	return profile and Schema.DeepCopy(profile.Economy) or nil
end

function PlayerProfileService.AddPet(player, pet, nextSequence)
	return mutate(player, function(profile)
		if type(pet) ~= "table" or type(pet.Uid) ~= "string" or pet.Uid == "" then
			return nil, "Invalid Pet record."
		end
		if profile.Pets.Records[pet.Uid] then
			return nil, "Pet UID already exists: " .. pet.Uid
		end
		profile.Pets.Records[pet.Uid] = Schema.DeepCopy(pet)
		table.insert(profile.Pets.Order, pet.Uid)
		profile.Pets.NextSequence = math.max(profile.Pets.NextSequence, math.floor(tonumber(nextSequence) or 0))
		return true
	end)
end

function PlayerProfileService.SetPetFavorite(player, uid, favorite)
	return mutate(player, function(profile)
		local pet = profile.Pets.Records[uid]
		if not pet then
			return nil, "Pet is not owned: " .. tostring(uid)
		end
		local value = favorite == true
		if pet.Favorite == value then
			return false
		end
		pet.Favorite = value
		return true
	end)
end

function PlayerProfileService.SetPetProgression(player, uid, level, experience)
	return mutate(player, function(profile)
		local pet = profile.Pets.Records[uid]
		if not pet then
			return nil, "Pet is not owned: " .. tostring(uid)
		end
		local nextLevel = math.max(1, math.floor(tonumber(level) or 1))
		local nextExperience = math.max(0, math.floor((tonumber(experience) or 0) + 0.5))
		if pet.Level == nextLevel and pet.Experience == nextExperience then
			return false
		end
		pet.Level = nextLevel
		pet.Experience = nextExperience
		return true
	end)
end

function PlayerProfileService.ClearPets(player)
	return mutate(player, function(profile)
		if #profile.Pets.Order == 0 and #profile.Party == 0 then
			return false
		end
		profile.Pets.Order = {}
		profile.Pets.Records = {}
		profile.Party = {}
		-- NextSequence intentionally never decreases so a cleared/deleted UID is not
		-- silently reused later in the same persistent account history.
		return true
	end)
end

function PlayerProfileService.SetParty(player, party)
	return mutate(player, function(profile)
		local requested = type(party) == "table" and party or {}
		local nextParty = {}
		for _, uid in ipairs(requested) do
			if type(uid) == "string" then
				table.insert(nextParty, uid)
			end
		end
		if #nextParty == #profile.Party then
			local same = true
			for index, uid in ipairs(nextParty) do
				if profile.Party[index] ~= uid then
					same = false
					break
				end
			end
			if same then
				return false
			end
		end
		profile.Party = nextParty
		return true
	end)
end

function PlayerProfileService.SetHandlerProgression(player, level, experience)
	return mutate(player, function(profile)
		local nextLevel = math.max(1, math.floor(tonumber(level) or 1))
		local nextExperience = math.max(0, math.floor((tonumber(experience) or 0) + 0.5))
		if profile.Handler.Level == nextLevel and profile.Handler.Experience == nextExperience then
			return false
		end
		profile.Handler.Level = nextLevel
		profile.Handler.Experience = nextExperience
		return true
	end)
end

function PlayerProfileService.SetEconomyBalance(player, resourceId, balance)
	local definition = type(resourceId) == "string" and EconomyConfig.Resources[resourceId] or nil
	if not definition then
		return false, "Unknown economy resource: " .. tostring(resourceId)
	end
	local numericBalance = tonumber(balance)
	if not numericBalance
		or numericBalance ~= numericBalance
		or numericBalance == math.huge
		or numericBalance == -math.huge
		or numericBalance ~= math.floor(numericBalance)
		or numericBalance < 0
		or numericBalance > EconomyConfig.MaxBalance
	then
		return false, "Economy balance is outside the supported integer range."
	end

	return mutate(player, function(profile)
		local section = profile.Economy and profile.Economy[definition.Section]
		if type(section) ~= "table" then
			return nil, "Economy profile section is missing: " .. tostring(definition.Section)
		end
		if section[resourceId] == numericBalance then
			return false
		end
		section[resourceId] = numericBalance
		return true
	end)
end

function PlayerProfileService.SaveNow(player)
	local state = stateFor(player)
	if not state or state.Status ~= "Ready" then
		return false, "Player profile is not ready."
	end
	return saveState(player, state, false)
end

function PlayerProfileService.ResetForDevelopment(player)
	if not RunService:IsStudio() then
		return false, "Development profile reset is Studio-only."
	end
	if not validPlayer(player) then
		return false, "Invalid Player."
	end
	local state = stateFor(player)
	if not state or state.Status ~= "Ready" or state.Releasing then
		return false, "Player profile is not ready for reset."
	end

	local waitDeadline = os.clock() + 12
	while state.Saving and os.clock() < waitDeadline do
		task.wait(0.05)
	end
	if state.Saving then
		return false, "Timed out waiting for the current profile save."
	end

	-- Freeze normal mutation/autosave before atomically replacing the owned record.
	-- On success the Player is expected to be kicked immediately; clearing the state
	-- prevents PlayerRemoving from release-saving the old profile back over the reset.
	state.Releasing = true
	local ok, reason = Store.ResetOwned(player.UserId)
	if not ok then
		state.Releasing = false
		return false, reason
	end

	disconnectStateConnections(state)
	state.Status = "Reset"
	state.Profile = nil
	states[player] = nil
	player:SetAttribute(Config.ReadyAttributeName, false)
	player:SetAttribute(Config.FailureAttributeName, false)
	return true, nil
end

function PlayerProfileService.Start()
	if started then
		return
	end
	started = true
	closing = false
	if not Store.IsPersistent() then
		print("[Pawlands Profile] Studio memory mode active; DataStore persistence is disabled by config.")
	end

	playerAddedConnection = Players.PlayerAdded:Connect(loadPlayer)
	playerRemovingConnection = Players.PlayerRemoving:Connect(releasePlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		loadPlayer(player)
	end

	task.spawn(function()
		while started and not closing do
			task.wait(Config.AutosaveIntervalSeconds)
			if not started or closing then
				break
			end
			for player, state in pairs(states) do
				if state.Status == "Ready" and not state.Saving and not state.Releasing then
					local capturedPlayer = player
					local capturedState = state
					task.spawn(function()
						-- Autosave also refreshes the server-session heartbeat even if no
						-- gameplay data changed, preventing a live lock from expiring.
						saveState(capturedPlayer, capturedState, false)
					end)
				end
			end
		end
	end)

	game:BindToClose(function()
		if not started then
			return
		end
		closing = true
		local targets = {}
		for player, state in pairs(states) do
			if state.Status == "Ready" and not state.Releasing then
				table.insert(targets, player)
			end
		end
		local pending = #targets
		for _, player in ipairs(targets) do
			local capturedPlayer = player
			task.spawn(function()
				releasePlayer(capturedPlayer)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.05)
		end
	end)
end

function PlayerProfileService.Stop()
	if not started then
		return
	end
	started = false
	closing = true
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end

	local targets = {}
	local nonReady = {}
	for player, state in pairs(states) do
		if state.Status == "Ready" and not state.Releasing then
			table.insert(targets, player)
		else
			table.insert(nonReady, player)
		end
	end
	for _, player in ipairs(nonReady) do
		local state = states[player]
		disconnectStateConnections(state)
		states[player] = nil
	end
	local pending = #targets
	for _, player in ipairs(targets) do
		local capturedPlayer = player
		task.spawn(function()
			releasePlayer(capturedPlayer)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.05)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute(Config.ReadyAttributeName, nil)
		player:SetAttribute(Config.PersistentAttributeName, nil)
		player:SetAttribute(Config.FailureAttributeName, nil)
	end
	table.clear(states)
end

return PlayerProfileService
