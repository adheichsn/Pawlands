local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local ProfileConfig = require(Shared.Config.Profile)
local DevelopmentConfig = require(script.Parent.Parent.Config.Development)

local ProfileDevCommands = {}
local started = false
local connections = {}
local playerAddedConnection = nil
local playerRemovingConnection = nil

local function disconnectPlayer(player)
	local connection = connections[player]
	if connection then
		connection:Disconnect()
		connections[player] = nil
	end
end

local function formatParty(profile)
	local entries = {}
	for slot, uid in ipairs(profile.Party or {}) do
		local pet = profile.Pets and profile.Pets.Records and profile.Pets.Records[uid]
		local petId = pet and pet.PetId or "missing"
		table.insert(entries, string.format("%d=%s(%s)", slot, tostring(uid), tostring(petId)))
	end
	return #entries > 0 and table.concat(entries, ", ") or "empty"
end

local function inspect(player, profileService)
	local profile = profileService.GetSnapshot(player)
	if not profile then
		warn("[Pawlands Profile] Profile is not ready for " .. player.Name .. ".")
		return
	end

	local pets = profile.Pets or {}
	local order = pets.Order or {}
	local records = pets.Records or {}
	local handler = profile.Handler or {}
	local economy = profile.Economy or {}
	local currencies = economy.Currencies or {}
	local materials = economy.Materials or {}
	local tutorial = profile.Tutorial or {}
	local persistent = player:GetAttribute(ProfileConfig.PersistentAttributeName) == true

	print(string.format(
		"[Pawlands Profile] %s (%d) schema=v%d mode=%s handler=Lv%d exp=%d pets=%d nextUid=p%d",
		player.Name,
		player.UserId,
		ProfileConfig.SchemaVersion,
		persistent and "persistent" or "studio-memory",
		math.floor(tonumber(handler.Level) or 1),
		math.floor(tonumber(handler.Experience) or 0),
		#order,
		math.floor(tonumber(pets.NextSequence) or 0) + 1
	))
	print("[Pawlands Profile] Party: " .. formatParty(profile))
	print(string.format(
		"[Pawlands Profile] Economy: Coins=%d Diamonds=%d SlimeCore=%d",
		math.floor(tonumber(currencies.Coins) or 0),
		math.floor(tonumber(currencies.Diamonds) or 0),
		math.floor(tonumber(materials.SlimeCore) or 0)
	))
	print(string.format(
		"[Pawlands Profile] Tutorial: stage=%s starterGranted=%s starterUid=%s starterSpecies=%s petHit=%s",
		tostring(tutorial.Stage or ""),
		tostring(tutorial.StarterPetGranted == true),
		tostring(tutorial.StarterPetUid or ""),
		tostring(tutorial.StarterPetSpecies or ""),
		tostring(tutorial.StarterPetHitConfirmed == true)
	))

	local equippedSlots = {}
	for slot, uid in ipairs(profile.Party or {}) do
		equippedSlots[uid] = slot
	end
	local limit = math.min(#order, 50)
	for index = 1, limit do
		local uid = order[index]
		local pet = records[uid]
		if pet then
			local slot = equippedSlots[uid]
			local flags = {}
			if pet.Favorite == true then
				table.insert(flags, "favorite")
			end
			if slot then
				table.insert(flags, "slot" .. tostring(slot))
			end
			if tutorial.StarterPetUid == uid then
				table.insert(flags, "starter")
			end
			local suffix = #flags > 0 and (" [" .. table.concat(flags, ",") .. "]") or ""
			print(string.format(
				"[Pawlands Profile] Pet %s=%s/%s Lv%d exp=%d variant=%s%s",
				tostring(uid),
				tostring(pet.PetId or ""),
				tostring(pet.SpeciesId or ""),
				math.floor(tonumber(pet.Level) or 1),
				math.floor(tonumber(pet.Experience) or 0),
				tostring(pet.Variant or "Normal"),
				suffix
			))
		end
	end
	if #order > limit then
		print(string.format("[Pawlands Profile] ... %d additional Pet records omitted.", #order - limit))
	end
end

local function handleReset(player, tail, profileService)
	if string.lower(tail or "") ~= "confirm" then
		warn("[Pawlands Profile] Reset is destructive. Run !profilereset CONFIRM to reset your current profile.")
		return
	end

	local ok, reason = profileService.ResetForDevelopment(player)
	if not ok then
		warn("[Pawlands Profile] Reset failed for " .. player.Name .. ": " .. tostring(reason))
		return
	end

	print("[Pawlands Profile] Reset complete for " .. player.Name .. ". Rejoin to load a fresh profile.")
	player:Kick("Your Pawlands development profile was reset. Rejoin to start fresh.")
end

function ProfileDevCommands.Start(profileService)
	if started or not RunService:IsStudio() or DevelopmentConfig.EnableProfileCommands ~= true then
		return
	end
	if not profileService then
		error("ProfileDevCommands requires PlayerProfileService.")
	end
	started = true

	local function added(player)
		disconnectPlayer(player)
		connections[player] = player.Chatted:Connect(function(message)
			local command, tail = string.match(message, "^(%S+)%s*(.-)%s*$")
			if not command then
				return
			end
			command = string.lower(command)
			if command == "!profileinspect" then
				inspect(player, profileService)
			elseif command == "!profilereset" then
				handleReset(player, tail, profileService)
			end
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		added(player)
	end
	playerAddedConnection = Players.PlayerAdded:Connect(added)
	playerRemovingConnection = Players.PlayerRemoving:Connect(disconnectPlayer)
	print("[Pawlands Profile] Studio commands ready: !profileinspect | !profilereset CONFIRM")
end

function ProfileDevCommands.Stop()
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
	for _, connection in pairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

return ProfileDevCommands
