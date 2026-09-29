local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetParty)
local Catalog = require(Shared.Config.PetCatalog)
local Rules = require(Shared.Pets.PartyRules)
local Codec = require(Shared.Pets.PartyCodec)
local Assets = require(Shared.Pets.PetAssets)

local PetPartyService = {}
local parties = {}
local started = false

function PetPartyService.GetParty(player)
	return table.clone(parties[player] or {})
end

-- Trusted server API only. A future inventory must verify ownership before calling.
-- No client equip remote is exposed by this foundation.
function PetPartyService.SetParty(player, requested)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "Player is not in this server."
	end
	local party, reason = Rules.validate(requested, Catalog, Config.MaxSize)
	if not party then
		return false, reason
	end
	for _, id in ipairs(party) do
		local model, assetReason = Assets.find(Catalog.Pets[id], Config.AssetPath)
		if not model then
			return false, assetReason
		end
	end
	parties[player] = party
	player:SetAttribute(Config.AttributeName, Codec.encode(party))
	return true, nil
end

function PetPartyService.Start()
	if started then
		return
	end
	started = true
	local function added(player)
		if not parties[player] then
			parties[player] = {}
			player:SetAttribute(Config.AttributeName, "")
		end
	end
	Players.PlayerAdded:Connect(added)
	Players.PlayerRemoving:Connect(function(player)
		parties[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		added(player)
	end
end

return PetPartyService
