local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetCombat)
local Codec = require(Shared.Pets.PetCombatCodec)

local Observer = {}

function Observer.Start(changed, removed)
	local watched = {}
	local function read(player)
		return Codec.decode(player:GetAttribute(Config.AssignmentAttributeName))
	end
	local function added(player)
		if watched[player] then
			return
		end
		watched[player] = player:GetAttributeChangedSignal(Config.AssignmentAttributeName):Connect(function()
			changed(player, read(player))
		end)
		changed(player, read(player))
	end
	local function remove(player)
		local connection = watched[player]
		if connection then
			connection:Disconnect()
		end
		watched[player] = nil
		removed(player)
	end
	local addConnection = Players.PlayerAdded:Connect(added)
	local removeConnection = Players.PlayerRemoving:Connect(remove)
	for _, player in ipairs(Players:GetPlayers()) do
		added(player)
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

return Observer
