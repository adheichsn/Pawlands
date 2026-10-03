local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local ProfileConfig = require(Shared.Config.Profile)
local InventoryConfig = require(Shared.Config.Inventory)
local PetPartyConfig = require(Shared.Config.PetParty)
local PetCatalog = require(Shared.Config.PetCatalog)
local PetProgressionConfig = require(Shared.Config.PetProgression)
local HandlerProgressionConfig = require(Shared.Config.HandlerProgression)
local EconomyConfig = require(Shared.Config.Economy)
local TutorialConfig = require(Shared.Config.Tutorial)
local ProgressionMath = require(Shared.Progression.ProgressionMath)

local ProfileSchema = {}

local validTutorialStages = {}
for _, stage in pairs(TutorialConfig.Stages) do
	validTutorialStages[stage] = true
end

local function finiteNonNegative(value)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return 0
	end
	return math.floor(value + 0.5)
end

local function stringOr(value, fallback)
	if type(value) == "string" then
		return value
	end
	return fallback
end

function ProfileSchema.DeepCopy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for key, child in pairs(value) do
		copy[ProfileSchema.DeepCopy(key, seen)] = ProfileSchema.DeepCopy(child, seen)
	end
	return copy
end

function ProfileSchema.NewData()
	return {
		Handler = {
			Level = HandlerProgressionConfig.InitialLevel,
			Experience = 0,
		},
		Economy = {
			Currencies = {
				Coins = 0,
				Diamonds = 0,
			},
			Materials = {
				SlimeCore = 0,
			},
		},
		Pets = {
			NextSequence = 0,
			Order = {},
			Records = {},
		},
		Party = {},
		Tutorial = {
			Stage = TutorialConfig.Stages.NotStarted,
			StarterPetGranted = false,
			StarterPetUid = "",
			StarterPetSpecies = "",
			StarterPetHitConfirmed = false,
		},
	}
end

local function normalizePet(uid, raw)
	if type(uid) ~= "string" or uid == "" or #uid > 64 or type(raw) ~= "table" then
		return nil
	end
	local petId = stringOr(raw.PetId, "")
	local definition = PetCatalog.Pets[petId]
	if not definition then
		return nil
	end
	local resolved = ProgressionMath.Resolve(finiteNonNegative(raw.Experience), PetProgressionConfig)
	return {
		Uid = uid,
		PetId = petId,
		SpeciesId = definition.SpeciesId,
		Variant = stringOr(raw.Variant, "Normal"),
		Favorite = raw.Favorite == true,
		Level = resolved.Level,
		Experience = resolved.TotalExperience,
	}
end

local function normalizePets(rawPets)
	rawPets = type(rawPets) == "table" and rawPets or {}
	local rawRecords = type(rawPets.Records) == "table" and rawPets.Records or {}
	local rawOrder = type(rawPets.Order) == "table" and rawPets.Order or {}
	local result = {
		NextSequence = math.max(0, math.floor(tonumber(rawPets.NextSequence) or 0)),
		Order = {},
		Records = {},
	}
	local seen = {}
	local maxSequence = result.NextSequence

	local function addUid(uid)
		if #result.Order >= InventoryConfig.PetCapacity or seen[uid] then
			return
		end
		local pet = normalizePet(uid, rawRecords[uid])
		if not pet then
			return
		end
		seen[uid] = true
		result.Records[uid] = pet
		table.insert(result.Order, uid)
		local sequence = tonumber(string.match(uid, "^p(%d+)$"))
		if sequence then
			maxSequence = math.max(maxSequence, math.floor(sequence))
		end
	end

	for _, uid in ipairs(rawOrder) do
		if type(uid) == "string" then
			addUid(uid)
		end
	end

	-- Recover valid records that may have survived an older/broken Order array.
	local remaining = {}
	for uid in pairs(rawRecords) do
		if type(uid) == "string" and not seen[uid] then
			table.insert(remaining, uid)
		end
	end
	table.sort(remaining)
	for _, uid in ipairs(remaining) do
		addUid(uid)
	end

	result.NextSequence = maxSequence
	return result
end

local function normalizeParty(rawParty, pets)
	local result = {}
	local seenUid = {}
	local seenSpecies = {}
	if type(rawParty) ~= "table" then
		return result
	end
	for _, uid in ipairs(rawParty) do
		if #result >= PetPartyConfig.MaxSize then
			break
		end
		local pet = type(uid) == "string" and pets.Records[uid] or nil
		if pet and not seenUid[uid] and not seenSpecies[pet.SpeciesId] then
			seenUid[uid] = true
			seenSpecies[pet.SpeciesId] = true
			table.insert(result, uid)
		end
	end
	return result
end

local function normalizeTutorial(rawTutorial, pets)
	rawTutorial = type(rawTutorial) == "table" and rawTutorial or {}
	local stage = stringOr(rawTutorial.Stage, TutorialConfig.Stages.NotStarted)
	if not validTutorialStages[stage] then
		stage = TutorialConfig.Stages.NotStarted
	end

	local starterUid = stringOr(rawTutorial.StarterPetUid, "")
	local starterPet = pets.Records[starterUid]
	local starterGranted = rawTutorial.StarterPetGranted == true and starterPet ~= nil
	local starterSpecies = starterPet and starterPet.SpeciesId or ""
	if not starterGranted then
		starterUid = ""
		starterSpecies = ""
	end

	return {
		Stage = stage,
		StarterPetGranted = starterGranted,
		StarterPetUid = starterUid,
		StarterPetSpecies = starterSpecies,
		StarterPetHitConfirmed = rawTutorial.StarterPetHitConfirmed == true,
	}
end

local function normalizeEconomy(rawEconomy)
	rawEconomy = type(rawEconomy) == "table" and rawEconomy or {}
	local result = {
		Currencies = {},
		Materials = {},
	}
	for resourceId, definition in pairs(EconomyConfig.Resources) do
		local rawSection = type(rawEconomy[definition.Section]) == "table" and rawEconomy[definition.Section] or {}
		local balance = math.min(EconomyConfig.MaxBalance, finiteNonNegative(rawSection[resourceId]))
		result[definition.Section][resourceId] = balance
	end
	return result
end

function ProfileSchema.NormalizeData(rawData)
	rawData = type(rawData) == "table" and rawData or {}
	local data = ProfileSchema.NewData()
	local pets = normalizePets(rawData.Pets)
	local handlerRaw = type(rawData.Handler) == "table" and rawData.Handler or {}
	local handlerResolved = ProgressionMath.Resolve(finiteNonNegative(handlerRaw.Experience), HandlerProgressionConfig)

	data.Handler.Level = handlerResolved.Level
	data.Handler.Experience = handlerResolved.TotalExperience
	data.Economy = normalizeEconomy(rawData.Economy)
	data.Pets = pets
	data.Party = normalizeParty(rawData.Party, pets)
	data.Tutorial = normalizeTutorial(rawData.Tutorial, pets)
	return data
end

function ProfileSchema.NormalizeRecord(rawRecord)
	if rawRecord == nil then
		return {
			SchemaVersion = ProfileConfig.SchemaVersion,
			Session = nil,
			Data = ProfileSchema.NewData(),
		}, nil
	end
	if type(rawRecord) ~= "table" then
		return nil, "Stored profile is not a table."
	end

	local version = math.floor(tonumber(rawRecord.SchemaVersion) or 0)
	if version > ProfileConfig.SchemaVersion then
		return nil, string.format(
			"Stored profile schema v%d is newer than server schema v%d.",
			version,
			ProfileConfig.SchemaVersion
		)
	end

	-- v0 is the migration bridge for pre-versioned/internal test records.
	-- Schema v2 adds Economy; NormalizeData fills missing v1 economy fields with
	-- zero balances while preserving Handler, Pet, party, and Tutorial progress.
	local sourceData
	if version <= 0 then
		sourceData = type(rawRecord.Data) == "table" and rawRecord.Data or rawRecord
	else
		if type(rawRecord.Data) ~= "table" then
			return nil, "Stored profile data payload is missing or invalid."
		end
		sourceData = rawRecord.Data
	end

	local session = type(rawRecord.Session) == "table" and {
		JobId = stringOr(rawRecord.Session.JobId, ""),
		PlaceId = math.floor(tonumber(rawRecord.Session.PlaceId) or 0),
		Heartbeat = math.max(0, math.floor(tonumber(rawRecord.Session.Heartbeat) or 0)),
	} or nil
	if session and session.JobId == "" then
		session = nil
	end

	return {
		SchemaVersion = ProfileConfig.SchemaVersion,
		Session = session,
		Data = ProfileSchema.NormalizeData(sourceData),
	}, nil
end

return ProfileSchema
