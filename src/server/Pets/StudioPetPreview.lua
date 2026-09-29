local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Config = require(script.Parent.Parent.Config.Development)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Catalog = require(Shared.Config.PetCatalog)

local StudioPetPreview = {}
local started = false

function StudioPetPreview.Start(service)
	if started or not RunService:IsStudio() then
		return
	end
	started = true
	local connections, initialized = {}, {}
	local function apply(player, party)
		local ok, reason = service.SetParty(player, party)
		if ok then
			print("[Pawlands Pets] " .. player.Name .. ": " .. table.concat(service.GetParty(player), ", "))
		else
			warn("[Pawlands Pets] " .. player.Name .. ": " .. tostring(reason))
		end
	end
	local function added(player)
		if initialized[player] then
			return
		end
		initialized[player] = true
		if Config.EnablePetPreview then
			apply(player, Config.PreviewParty)
		end
		if Config.EnablePetCommands then
			connections[player] = player.Chatted:Connect(function(message)
				local command, tail = string.match(message, "^(%S+)%s*(.-)%s*$")
				if not command or string.lower(command) ~= "!pets" then
					return
				end
				local lower = string.lower(tail)
				if lower == "clear" then
					apply(player, {})
				elseif lower == "list" then
					local names = {}
					for id in pairs(Catalog.Pets) do
						table.insert(names, id)
					end
					table.sort(names)
					print("[Pawlands Pets] Available: " .. table.concat(names, ", "))
				elseif tail == "" or lower == "help" then
					print("[Pawlands Pets] !pets Bunny Cat Dog Dragon | !pets clear | !pets list")
				else
					local requested = {}
					for name in string.gmatch(tail, "[^,%s]+") do
						table.insert(requested, name)
					end
					apply(player, requested)
				end
			end)
		end
	end
	Players.PlayerAdded:Connect(added)
	Players.PlayerRemoving:Connect(function(player)
		if connections[player] then
			connections[player]:Disconnect()
		end
		connections[player], initialized[player] = nil, nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		added(player)
	end
end

return StudioPetPreview
