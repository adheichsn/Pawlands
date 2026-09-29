local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetParty)
local Catalog = require(Shared.Config.PetCatalog)
local Rules = require(Shared.Pets.PartyRules)
local Codec = require(Shared.Pets.PartyCodec)

local PartyObserver = {}

function PartyObserver.Start(changed, removed)
	local watched = {}
	local function read(player)
		local decoded = Codec.decode(player:GetAttribute(Config.AttributeName))
		return Rules.validate(decoded, Catalog, Config.MaxSize) or {}
	end
	local function added(player)
		if watched[player] then
			return
		end
		watched[player] = {
			player:GetAttributeChangedSignal(Config.AttributeName):Connect(function()
				changed(player, read(player), player.Character)
			end),
			player.CharacterAdded:Connect(function(character)
				changed(player, read(player), character)
			end),
			player.CharacterRemoving:Connect(function()
				changed(player, read(player), nil)
			end),
		}
		changed(player, read(player), player.Character)
	end
	local function remove(player)
		for _, connection in ipairs(watched[player] or {}) do
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

return PartyObserver
