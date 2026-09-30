local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Catalog = require(Shared.Config.PetCatalog)
local Config = require(Shared.Config.PetVitals)

local PetVitalsService = {}
local started = false
local inventoryService
local partyService
local stateByPlayer = {}
local heartbeatConnection
local addedConnection
local removingConnection
local accumulator = 0

local FIELD_SEPARATOR = ","
local ENTRY_SEPARATOR = ";"

local function safeNumber(value)
	value = tonumber(value) or 0
	if value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return value
end

local function encodeSnapshot(entries)
	local parts = {}
	for slot, entry in pairs(entries or {}) do
		if type(slot) == "number" and type(entry) == "table" then
			local uid = tostring(entry.Uid or "")
			local state = tostring(entry.CombatState or "Idle")
			if uid ~= "" and not string.find(uid, "[,;]") and not string.find(state, "[,;]") then
				table.insert(parts, {
					Slot = math.floor(slot),
					Value = table.concat({
						tostring(math.floor(slot)),
						uid,
						string.format("%.3f", safeNumber(entry.Health)),
						string.format("%.3f", safeNumber(entry.MaxHealth)),
						state,
						entry.KO == true and "1" or "0",
						string.format("%.3f", safeNumber(entry.RecoverAt)),
					}, FIELD_SEPARATOR),
				})
			end
		end
	end
	table.sort(parts, function(a, b)
		return a.Slot < b.Slot
	end)
	local encoded = {}
	for _, part in ipairs(parts) do
		table.insert(encoded, part.Value)
	end
	return table.concat(encoded, ENTRY_SEPARATOR)
end

local function now()
	return Workspace:GetServerTimeNow()
end

local function validPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function getPlayerState(player)
	local state = stateByPlayer[player]
	if state or not validPlayer(player) then
		return state
	end
	state = {
		Pets = {},
		Published = nil,
	}
	stateByPlayer[player] = state
	return state
end

local function maxHealthForPet(pet)
	local definition = pet and Catalog.Pets[pet.PetId]
	local configured = definition and tonumber(definition.MaxHealth)
	return math.max(1, configured or Config.DefaultMaxHealth)
end

local function cloneVitals(vitals)
	return vitals and table.clone(vitals) or nil
end

local function ensureVitals(player, uid)
	local playerState = getPlayerState(player)
	if not playerState or not inventoryService then
		return nil, "Pet vitals service is unavailable."
	end
	local pet = inventoryService.GetPet(player, uid)
	if not pet then
		return nil, "Pet is not owned: " .. tostring(uid)
	end
	local vitals = playerState.Pets[uid]
	if vitals then
		return vitals, nil
	end
	local maxHealth = maxHealthForPet(pet)
	vitals = {
		Uid = uid,
		PetId = pet.PetId,
		Health = maxHealth,
		MaxHealth = maxHealth,
		CombatState = Config.States.Idle,
		KO = false,
		RecoverAt = 0,
	}
	playerState.Pets[uid] = vitals
	return vitals, nil
end

local function recoverIfReady(vitals, clock)
	if not vitals.KO or vitals.RecoverAt <= 0 or clock < vitals.RecoverAt then
		return false
	end
	vitals.Health = vitals.MaxHealth
	vitals.KO = false
	vitals.RecoverAt = 0
	vitals.CombatState = Config.States.Idle
	return true
end

local function buildPartySnapshot(player, clock)
	local result = {}
	if not partyService then
		return result
	end
	for slot, uid in ipairs(partyService.GetParty(player)) do
		local vitals = ensureVitals(player, uid)
		if vitals then
			recoverIfReady(vitals, clock)
			result[slot] = cloneVitals(vitals)
		end
	end
	return result
end

local function publishPlayer(player, clock)
	if player.Parent ~= Players then
		return
	end
	local playerState = getPlayerState(player)
	if not playerState then
		return
	end
	local encoded = encodeSnapshot(buildPartySnapshot(player, clock))
	if encoded ~= playerState.Published then
		playerState.Published = encoded
		player:SetAttribute(Config.AttributeName, encoded)
	end
end

local function reconcilePlayer(player, clock)
	local playerState = getPlayerState(player)
	if not playerState then
		return
	end
	local equipped = {}
	if partyService then
		for _, uid in ipairs(partyService.GetParty(player)) do
			equipped[uid] = true
			ensureVitals(player, uid)
		end
	end
	local changed = false
	for uid, vitals in pairs(playerState.Pets) do
		if recoverIfReady(vitals, clock) then
			changed = true
		end
		if not equipped[uid] and not vitals.KO and vitals.CombatState ~= Config.States.Idle then
			vitals.CombatState = Config.States.Idle
			changed = true
		end
	end
	if changed then
		playerState.Published = nil
	end
	publishPlayer(player, clock)
end

function PetVitalsService.GetSnapshot(player, uid)
	local vitals, reason = ensureVitals(player, uid)
	if not vitals then
		return nil, reason
	end
	if recoverIfReady(vitals, now()) then
		local playerState = getPlayerState(player)
		if playerState then
			playerState.Published = nil
		end
	end
	return cloneVitals(vitals), nil
end

function PetVitalsService.GetPartySnapshot(player)
	return buildPartySnapshot(player, now())
end

function PetVitalsService.CanCombat(player, uid)
	local vitals = ensureVitals(player, uid)
	if not vitals then
		return false
	end
	if recoverIfReady(vitals, now()) then
		local playerState = getPlayerState(player)
		if playerState then
			playerState.Published = nil
		end
	end
	return not vitals.KO and vitals.Health > 0
end

function PetVitalsService.SetCombatActive(player, uid, active)
	local vitals, reason = ensureVitals(player, uid)
	if not vitals then
		return false, reason
	end
	if recoverIfReady(vitals, now()) then
		local playerState = getPlayerState(player)
		if playerState then
			playerState.Published = nil
		end
	end
	if vitals.KO then
		return false, "Pet is knocked out."
	end
	local nextState = active and Config.States.Combat or Config.States.Idle
	if vitals.CombatState ~= nextState then
		vitals.CombatState = nextState
		local playerState = getPlayerState(player)
		if playerState then
			playerState.Published = nil
		end
	end
	return true, nil
end

function PetVitalsService.ReleaseCombat(player)
	local playerState = getPlayerState(player)
	if not playerState then
		return
	end
	local changed = false
	for _, vitals in pairs(playerState.Pets) do
		if not vitals.KO and vitals.CombatState ~= Config.States.Idle then
			vitals.CombatState = Config.States.Idle
			changed = true
		end
	end
	if changed then
		playerState.Published = nil
	end
	publishPlayer(player, now())
end

function PetVitalsService.ApplyDamage(player, uid, amount)
	local vitals, reason = ensureVitals(player, uid)
	if not vitals then
		return false, nil, reason
	end
	local damage = tonumber(amount)
	if not damage or damage <= 0 then
		return false, cloneVitals(vitals), "Damage must be greater than zero."
	end
	if recoverIfReady(vitals, now()) then
		local playerState = getPlayerState(player)
		if playerState then
			playerState.Published = nil
		end
	end
	if vitals.KO or vitals.Health <= 0 then
		return false, cloneVitals(vitals), "Pet is knocked out."
	end

	vitals.Health = math.max(0, vitals.Health - damage)
	if vitals.Health <= 0 then
		vitals.Health = 0
		vitals.KO = true
		vitals.CombatState = Config.States.KO
		vitals.RecoverAt = now() + Config.RecoverSeconds
	end
	local playerState = getPlayerState(player)
	if playerState then
		playerState.Published = nil
	end
	publishPlayer(player, now())
	return true, cloneVitals(vitals), nil
end

function PetVitalsService.KnockOut(player, uid)
	local vitals, reason = ensureVitals(player, uid)
	if not vitals then
		return false, nil, reason
	end
	if vitals.KO then
		return true, cloneVitals(vitals), nil
	end
	return PetVitalsService.ApplyDamage(player, uid, math.max(1, vitals.Health))
end

function PetVitalsService.Restore(player, uid)
	local vitals, reason = ensureVitals(player, uid)
	if not vitals then
		return false, nil, reason
	end
	vitals.Health = vitals.MaxHealth
	vitals.KO = false
	vitals.RecoverAt = 0
	vitals.CombatState = Config.States.Idle
	local playerState = getPlayerState(player)
	if playerState then
		playerState.Published = nil
	end
	publishPlayer(player, now())
	return true, cloneVitals(vitals), nil
end

function PetVitalsService.Clear(player)
	stateByPlayer[player] = nil
	if player.Parent == Players then
		player:SetAttribute(Config.AttributeName, "")
	end
end

function PetVitalsService.Start(petInventoryService, petPartyService)
	if started then
		return
	end
	inventoryService = petInventoryService
	partyService = petPartyService
	if not inventoryService or not partyService then
		error("PetVitalsService requires PetInventoryService and PetPartyService.")
	end
	started = true

	local function initializePlayer(player)
		getPlayerState(player)
		player:SetAttribute(Config.AttributeName, "")
		publishPlayer(player, now())
	end

	addedConnection = Players.PlayerAdded:Connect(initializePlayer)
	removingConnection = Players.PlayerRemoving:Connect(function(player)
		stateByPlayer[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		initializePlayer(player)
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		local interval = 1 / math.max(1, Config.UpdateRate)
		if accumulator < interval then
			return
		end
		accumulator %= interval
		local clock = now()
		for _, player in ipairs(Players:GetPlayers()) do
			reconcilePlayer(player, clock)
		end
	end)
end

function PetVitalsService.Stop()
	if not started then
		return
	end
	started = false
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if addedConnection then
		addedConnection:Disconnect()
		addedConnection = nil
	end
	if removingConnection then
		removingConnection:Disconnect()
		removingConnection = nil
	end
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute(Config.AttributeName, "")
	end
	table.clear(stateByPlayer)
	inventoryService = nil
	partyService = nil
	accumulator = 0
end

return PetVitalsService
