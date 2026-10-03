local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.Economy)

local EconomyService = {}
local started = false
local profileService = nil
local stateByPlayer = {}
local playerAddedConnection = nil
local playerRemovingConnection = nil

local function validPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function resourceDefinition(resourceId)
	return type(resourceId) == "string" and Config.Resources[resourceId] or nil
end

local function integer(value)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	if value ~= math.floor(value) then
		return nil
	end
	return value
end

local function positiveInteger(value)
	value = integer(value)
	if not value or value <= 0 then
		return nil
	end
	return value
end

local function trim(value)
	return string.match(value, "^%s*(.-)%s*$") or ""
end

local function auditContext(raw)
	if type(raw) ~= "table" then
		return nil, "Economy mutation requires an audit context."
	end
	if type(raw.Reason) ~= "string" or type(raw.Source) ~= "string" then
		return nil, "Economy audit context requires string Reason and Source fields."
	end
	local reason = trim(raw.Reason)
	local source = trim(raw.Source)
	if reason == "" or source == "" then
		return nil, "Economy audit Reason and Source cannot be blank."
	end
	if #reason > Config.MaxReasonLength then
		return nil, "Economy audit Reason is too long."
	end
	if #source > Config.MaxSourceLength then
		return nil, "Economy audit Source is too long."
	end
	return {
		Reason = reason,
		Source = source,
	}, nil
end

local function balanceFromSnapshot(snapshot, definition)
	if type(snapshot) ~= "table" then
		return 0
	end
	local section = snapshot[definition.Section]
	local value = type(section) == "table" and tonumber(section[definition.Id]) or 0
	if not value or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.max(0, math.min(Config.MaxBalance, math.floor(value)))
end

local function stateFor(player)
	local state = stateByPlayer[player]
	if state then
		return state
	end
	state = {
		Sequence = 0,
		Ledger = {},
	}
	stateByPlayer[player] = state
	return state
end

local function bumpRevision(player)
	local current = tonumber(player:GetAttribute(Config.RevisionAttributeName)) or 0
	player:SetAttribute(Config.RevisionAttributeName, math.max(0, math.floor(current)) + 1)
end

local function publishResource(player, definition, balance)
	player:SetAttribute(definition.AttributeName, balance)
end

local function publishSnapshot(player, snapshot)
	for _, definition in pairs(Config.Resources) do
		publishResource(player, definition, balanceFromSnapshot(snapshot, definition))
	end
	if player:GetAttribute(Config.RevisionAttributeName) == nil then
		player:SetAttribute(Config.RevisionAttributeName, 0)
	end
end

local function appendLedger(player, definition, operation, delta, before, after, audit)
	local state = stateFor(player)
	state.Sequence += 1
	local entry = {
		Sequence = state.Sequence,
		Timestamp = os.time(),
		Operation = operation,
		ResourceId = definition.Id,
		Delta = delta,
		BalanceBefore = before,
		BalanceAfter = after,
		Reason = audit.Reason,
		Source = audit.Source,
	}
	table.insert(state.Ledger, entry)
	while #state.Ledger > Config.MaxLedgerEntries do
		table.remove(state.Ledger, 1)
	end
	return table.clone(entry)
end

local function currentBalance(player, definition)
	if not started or not profileService then
		return nil, "Economy service is unavailable."
	end
	if not validPlayer(player) then
		return nil, "Player is not in this server."
	end
	local snapshot = profileService.GetEconomySnapshot(player)
	if not snapshot then
		return nil, "Player economy is not initialized."
	end
	return balanceFromSnapshot(snapshot, definition), nil
end

local function commit(player, definition, nextBalance, operation, delta, audit)
	local ok, reason = profileService.SetEconomyBalance(player, definition.Id, nextBalance)
	if not ok then
		return nil, nil, reason
	end
	publishResource(player, definition, nextBalance)
	bumpRevision(player)
	local before = nextBalance - delta
	local transaction = appendLedger(player, definition, operation, delta, before, nextBalance, audit)
	return nextBalance, transaction, nil
end

function EconomyService.GetSnapshot(player)
	if not started or not profileService then
		return nil, "Economy service is unavailable."
	end
	local snapshot = profileService.GetEconomySnapshot(player)
	if not snapshot then
		return nil, "Player economy is not initialized."
	end
	local result = {}
	for resourceId, definition in pairs(Config.Resources) do
		result[resourceId] = balanceFromSnapshot(snapshot, definition)
	end
	return result, nil
end

function EconomyService.GetBalance(player, resourceId)
	local definition = resourceDefinition(resourceId)
	if not definition then
		return nil, "Unknown economy resource: " .. tostring(resourceId)
	end
	return currentBalance(player, definition)
end

function EconomyService.Add(player, resourceId, amount, rawAudit)
	local definition = resourceDefinition(resourceId)
	if not definition then
		return nil, nil, "Unknown economy resource: " .. tostring(resourceId)
	end
	local gain = positiveInteger(amount)
	if not gain then
		return nil, nil, "Economy add amount must be a positive integer."
	end
	local audit, auditReason = auditContext(rawAudit)
	if not audit then
		return nil, nil, auditReason
	end
	local before, reason = currentBalance(player, definition)
	if before == nil then
		return nil, nil, reason
	end
	if gain > Config.MaxBalance - before then
		return nil, nil, definition.DisplayName .. " balance would exceed the maximum."
	end
	return commit(player, definition, before + gain, "Add", gain, audit)
end

function EconomyService.Spend(player, resourceId, amount, rawAudit)
	local definition = resourceDefinition(resourceId)
	if not definition then
		return nil, nil, "Unknown economy resource: " .. tostring(resourceId)
	end
	local spend = positiveInteger(amount)
	if not spend then
		return nil, nil, "Economy spend amount must be a positive integer."
	end
	local audit, auditReason = auditContext(rawAudit)
	if not audit then
		return nil, nil, auditReason
	end
	local before, reason = currentBalance(player, definition)
	if before == nil then
		return nil, nil, reason
	end
	if before < spend then
		return nil, nil, string.format("Insufficient %s (%d/%d).", definition.DisplayName, before, spend)
	end
	return commit(player, definition, before - spend, "Spend", -spend, audit)
end

function EconomyService.SetBalance(player, resourceId, amount, rawAudit)
	local definition = resourceDefinition(resourceId)
	if not definition then
		return nil, nil, "Unknown economy resource: " .. tostring(resourceId)
	end
	local nextBalance = integer(amount)
	if not nextBalance or nextBalance < 0 or nextBalance > Config.MaxBalance then
		return nil, nil, "Economy balance must be a non-negative integer within the supported range."
	end
	local audit, auditReason = auditContext(rawAudit)
	if not audit then
		return nil, nil, auditReason
	end
	local before, reason = currentBalance(player, definition)
	if before == nil then
		return nil, nil, reason
	end
	if before == nextBalance then
		return nextBalance, nil, nil
	end
	return commit(player, definition, nextBalance, "Set", nextBalance - before, audit)
end

function EconomyService.GetLedgerSnapshot(player)
	local state = stateByPlayer[player]
	local result = {}
	if not state then
		return result
	end
	for index, entry in ipairs(state.Ledger) do
		result[index] = table.clone(entry)
	end
	return result
end

local function bindPlayer(player)
	stateFor(player)
	task.spawn(function()
		local profile, reason = profileService.AwaitReady(player)
		if not profile then
			if player.Parent == Players then
				warn(string.format("[Pawlands Economy] Could not initialize %s: %s", player.Name, tostring(reason)))
			end
			return
		end
		if not started or player.Parent ~= Players then
			return
		end
		publishSnapshot(player, profile.Economy)
	end)
end

local function unbindPlayer(player)
	stateByPlayer[player] = nil
end

function EconomyService.Start(playerProfileService)
	if started then
		return
	end
	if not playerProfileService then
		error("EconomyService requires PlayerProfileService.")
	end
	profileService = playerProfileService
	started = true
	playerAddedConnection = Players.PlayerAdded:Connect(bindPlayer)
	playerRemovingConnection = Players.PlayerRemoving:Connect(unbindPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
end

function EconomyService.Stop()
	if not started then
		return
	end
	started = false
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	for _, player in ipairs(Players:GetPlayers()) do
		for _, definition in pairs(Config.Resources) do
			player:SetAttribute(definition.AttributeName, nil)
		end
		player:SetAttribute(Config.RevisionAttributeName, nil)
	end
	table.clear(stateByPlayer)
	profileService = nil
end

return EconomyService
