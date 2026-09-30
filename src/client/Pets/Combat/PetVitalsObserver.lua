local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetVitals)

local PetVitalsObserver = {}

local function safeNumber(value)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function decode(value)
	local result = {}
	if type(value) ~= "string" or value == "" or #value > 2048 then
		return result
	end

	for entry in string.gmatch(value, "[^;]+") do
		local fields = string.split(entry, ",")
		if #fields >= 7 then
			local slot = safeNumber(fields[1])
			local health = safeNumber(fields[3])
			local maxHealth = safeNumber(fields[4])
			local recoverAt = safeNumber(fields[7])
			if slot and health and maxHealth and recoverAt then
				slot = math.floor(slot)
				if slot >= 1 and slot <= 16 then
					result[slot] = {
						Uid = tostring(fields[2] or ""),
						Health = health,
						MaxHealth = maxHealth,
						CombatState = tostring(fields[5] or Config.States.Idle),
						KO = fields[6] == "1",
						RecoverAt = recoverAt,
					}
				end
			end
		end
	end
	return result
end

function PetVitalsObserver.Read(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return {}
	end
	return decode(player:GetAttribute(Config.AttributeName))
end

function PetVitalsObserver.Start(changed, removed)
	local watched = {}

	local function add(player)
		if watched[player] then
			return
		end
		watched[player] = player:GetAttributeChangedSignal(Config.AttributeName):Connect(function()
			changed(player, PetVitalsObserver.Read(player))
		end)
		changed(player, PetVitalsObserver.Read(player))
	end

	local function remove(player)
		local connection = watched[player]
		if connection then
			connection:Disconnect()
		end
		watched[player] = nil
		removed(player)
	end

	local addConnection = Players.PlayerAdded:Connect(add)
	local removeConnection = Players.PlayerRemoving:Connect(remove)
	for _, player in ipairs(Players:GetPlayers()) do
		add(player)
	end

	return function()
		addConnection:Disconnect()
		removeConnection:Disconnect()
		local players = {}
		for player in pairs(watched) do
			table.insert(players, player)
		end
		for _, player in ipairs(players) do
			remove(player)
		end
	end
end

return PetVitalsObserver
