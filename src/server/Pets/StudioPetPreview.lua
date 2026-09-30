local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Config = require(script.Parent.Parent.Config.Development)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local PartyConfig = require(Shared.Config.PetParty)
local Catalog = require(Shared.Config.PetCatalog)
local Rules = require(Shared.Pets.PartyRules)

local StudioPetPreview = {}
local started = false

local function catalogNames()
	local names = {}
	for id in pairs(Catalog.Pets) do
		table.insert(names, id)
	end
	table.sort(names)
	return names
end

function StudioPetPreview.Start(partyService, inventoryService, vitalsService, feedbackService)
	if started or not RunService:IsStudio() then
		return
	end
	started = true
	local connections, initialized = {}, {}

	local function printParty(player)
		local entries = {}
		for _, uid in ipairs(partyService.GetParty(player)) do
			local pet = inventoryService.GetPet(player, uid)
			if pet then
				table.insert(entries, uid .. "=" .. pet.PetId)
			end
		end
		print("[Pawlands Pets] Party " .. player.Name .. ": " .. (#entries > 0 and table.concat(entries, ", ") or "empty"))
	end

	local function printInventory(player)
		local equipped = {}
		for _, uid in ipairs(partyService.GetParty(player)) do
			equipped[uid] = true
		end
		local entries = {}
		for _, pet in ipairs(inventoryService.GetInventory(player)) do
			local marker = equipped[pet.Uid] and " [equipped]" or ""
			table.insert(entries, pet.Uid .. "=" .. pet.PetId .. "/" .. pet.Variant .. marker)
		end
		print("[Pawlands Pets] Inventory " .. player.Name .. ": " .. (#entries > 0 and table.concat(entries, ", ") or "empty"))
	end

	local function formatVitals(vitals)
		if not vitals then
			return "unavailable"
		end
		local recover = vitals.KO and math.max(0, vitals.RecoverAt - workspace:GetServerTimeNow()) or 0
		return string.format(
			"%s %.0f/%.0f state=%s KO=%s recover=%.1fs",
			vitals.Uid,
			vitals.Health,
			vitals.MaxHealth,
			vitals.CombatState,
			tostring(vitals.KO),
			recover
		)
	end

	local function printVitals(player, requestedUid)
		if not vitalsService then
			warn("[Pawlands Pets] Pet vitals service is unavailable.")
			return
		end
		if requestedUid and requestedUid ~= "" then
			local vitals, reason = vitalsService.GetSnapshot(player, string.lower(requestedUid))
			if vitals then
				print("[Pawlands Pets] Vitals " .. player.Name .. ": " .. formatVitals(vitals))
			else
				warn("[Pawlands Pets] " .. tostring(reason))
			end
			return
		end
		local entries = {}
		for _, pet in ipairs(inventoryService.GetInventory(player)) do
			local vitals = vitalsService.GetSnapshot(player, pet.Uid)
			if vitals then
				table.insert(entries, formatVitals(vitals))
			end
		end
		print("[Pawlands Pets] Vitals " .. player.Name .. ": " .. (#entries > 0 and table.concat(entries, " | ") or "empty"))
	end

	local function ensureOwned(player, petId)
		for _, pet in ipairs(inventoryService.GetInventory(player)) do
			if pet.PetId == petId then
				return pet.Uid
			end
		end
		local pet, reason = inventoryService.Grant(player, petId)
		return pet and pet.Uid or nil, reason
	end

	local function applyNames(player, requestedNames)
		local normalized, reason = Rules.validate(requestedNames, Catalog, PartyConfig.MaxSize)
		if not normalized then
			return false, reason
		end
		local uids = {}
		for _, petId in ipairs(normalized) do
			local uid, grantReason = ensureOwned(player, petId)
			if not uid then
				return false, grantReason
			end
			table.insert(uids, uid)
		end
		return partyService.SetParty(player, uids)
	end

	local function publishDamageFeedback(player, uid, vitals)
		if not feedbackService or not vitals then
			return
		end
		for slot, equippedUid in ipairs(partyService.GetParty(player)) do
			if equippedUid == uid then
				feedbackService.PublishHit(player, slot, vitals.KO == true, vitals.RecoverAt or 0, Vector3.zero)
				return
			end
		end
	end

	local function report(player, ok, reason)
		if ok then
			printParty(player)
		else
			warn("[Pawlands Pets] " .. player.Name .. ": " .. tostring(reason))
		end
	end

	local function help()
		print("[Pawlands Pets] !pets Bunny Cat Dog Dragon | !pets clear | !pets list")
		print("[Pawlands Pets] !petgrant Bunny | !petinventory | !petequip p1 | !petunequip p1 | !party | !petreset")
		print("[Pawlands Pets] !petvitals [p1] | !pethurt p1 25 | !petko p1 | !petheal p1")
	end

	local function added(player)
		if initialized[player] then
			return
		end
		initialized[player] = true
		if Config.EnablePetPreview then
			report(player, applyNames(player, Config.PreviewParty))
		end
		if Config.EnablePetCommands then
			connections[player] = player.Chatted:Connect(function(message)
				local command, tail = string.match(message, "^(%S+)%s*(.-)%s*$")
				if not command then
					return
				end
				command = string.lower(command)
				local lower = string.lower(tail)

				if command == "!pets" then
					if lower == "clear" then
						report(player, partyService.SetParty(player, {}))
					elseif lower == "list" then
						print("[Pawlands Pets] Available: " .. table.concat(catalogNames(), ", "))
					elseif tail == "" or lower == "help" then
						help()
					else
						local requested = {}
						for name in string.gmatch(tail, "[^,%s]+") do
							table.insert(requested, name)
						end
						report(player, applyNames(player, requested))
					end
				elseif command == "!petgrant" then
					if tail == "" then
						warn("[Pawlands Pets] Usage: !petgrant Bunny")
						return
					end
					local pet, reason = inventoryService.Grant(player, tail)
					if pet then
						if vitalsService then
							vitalsService.GetSnapshot(player, pet.Uid)
						end
						print("[Pawlands Pets] Granted " .. pet.PetId .. " as " .. pet.Uid .. ".")
						printInventory(player)
					else
						warn("[Pawlands Pets] " .. tostring(reason))
					end
				elseif command == "!petinventory" then
					printInventory(player)
				elseif command == "!petequip" then
					if tail == "" then
						warn("[Pawlands Pets] Usage: !petequip p1")
						return
					end
					report(player, partyService.Equip(player, string.lower(tail)))
				elseif command == "!petunequip" then
					if tail == "" then
						warn("[Pawlands Pets] Usage: !petunequip p1")
						return
					end
					report(player, partyService.Unequip(player, string.lower(tail)))
				elseif command == "!party" then
					printParty(player)
				elseif command == "!petvitals" then
					printVitals(player, tail)
				elseif command == "!pethurt" then
					local uid, amountText = string.match(tail, "^(%S+)%s+(%S+)$")
					local amount = tonumber(amountText)
					if not uid or not amount then
						warn("[Pawlands Pets] Usage: !pethurt p1 25")
					elseif not vitalsService then
						warn("[Pawlands Pets] Pet vitals service is unavailable.")
					else
						uid = string.lower(uid)
						local ok, vitals, reason = vitalsService.ApplyDamage(player, uid, amount)
						if ok then
							publishDamageFeedback(player, uid, vitals)
							print("[Pawlands Pets] Hurt " .. formatVitals(vitals))
						else
							warn("[Pawlands Pets] " .. tostring(reason))
						end
					end
				elseif command == "!petko" then
					if tail == "" then
						warn("[Pawlands Pets] Usage: !petko p1")
					elseif not vitalsService then
						warn("[Pawlands Pets] Pet vitals service is unavailable.")
					else
						local uid = string.lower(tail)
						local ok, vitals, reason = vitalsService.KnockOut(player, uid)
						if ok then
							publishDamageFeedback(player, uid, vitals)
							print("[Pawlands Pets] KO " .. formatVitals(vitals))
						else
							warn("[Pawlands Pets] " .. tostring(reason))
						end
					end
				elseif command == "!petheal" then
					if tail == "" then
						warn("[Pawlands Pets] Usage: !petheal p1")
					elseif not vitalsService then
						warn("[Pawlands Pets] Pet vitals service is unavailable.")
					else
						local ok, vitals, reason = vitalsService.Restore(player, string.lower(tail))
						if ok then
							print("[Pawlands Pets] Healed " .. formatVitals(vitals))
						else
							warn("[Pawlands Pets] " .. tostring(reason))
						end
					end
				elseif command == "!petreset" then
					local ok, reason = partyService.SetParty(player, {})
					if not ok then
						warn("[Pawlands Pets] " .. tostring(reason))
						return
					end
					local cleared, clearReason = inventoryService.Clear(player)
					if cleared then
						if vitalsService then
							vitalsService.Clear(player)
						end
						print("[Pawlands Pets] Session inventory and party cleared for " .. player.Name .. ".")
					else
						warn("[Pawlands Pets] " .. tostring(clearReason))
					end
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
