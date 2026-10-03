local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.CombatContribution)

local CombatContributionService = {}
local started = false
local nextEncounterSerial = 0
local listeners = {}
local stateByModel = setmetatable({}, { __mode = "k" })

local function finiteNonNegative(value, fallback)
	local number = tonumber(value)
	if not number or number ~= number or number == math.huge or number == -math.huge then
		return fallback or 0
	end
	return math.max(0, number)
end

local function trackable(model)
	if Config.Enabled ~= true or not model or not model:IsA("Model") then
		return false
	end
	if Config.TrackWorldCombatOnly == true then
		return model:GetAttribute(Config.WorldCombatAttributeName) == true
	end
	return true
end

local function getThreshold(model, attributeName, fallback)
	local override = model:GetAttribute(attributeName)
	if override == nil then
		return fallback
	end
	return finiteNonNegative(override, fallback)
end

local function ensureState(model)
	local state = stateByModel[model]
	if state then
		return state
	end
	nextEncounterSerial += 1
	state = {
		EncounterSerial = nextEncounterSerial,
		StartedAt = workspace:GetServerTimeNow(),
		Finalized = false,
		TotalDamage = 0,
		Participants = {},
		MaxHealth = math.max(1, finiteNonNegative(model:GetAttribute("MaxHealth"), 1)),
		DefeatingUserId = 0,
		DefeatingSourceType = "None",
		DefeatingPetUid = "",
		Snapshot = nil,
	}
	stateByModel[model] = state
	model:SetAttribute(Config.FinalizedAttributeName, false)
	model:SetAttribute(Config.ParticipantCountAttributeName, 0)
	model:SetAttribute(Config.EligibleCountAttributeName, 0)
	model:SetAttribute(Config.EncounterSerialAttributeName, state.EncounterSerial)
	return state
end

local function ensureParticipant(state, player)
	local userId = player.UserId
	local participant = state.Participants[userId]
	if participant then
		participant.Name = player.Name
		return participant
	end
	participant = {
		UserId = userId,
		Name = player.Name,
		FirstHitAt = workspace:GetServerTimeNow(),
		LastHitAt = 0,
		TotalDamage = 0,
		PlayerDamage = 0,
		PetDamage = 0,
		HitCount = 0,
		PlayerHitCount = 0,
		PetHitCount = 0,
		PetDamageByUid = {},
	}
	state.Participants[userId] = participant
	return participant
end

local function sortedPetUids(petDamageByUid)
	local result = {}
	for uid, damage in pairs(petDamageByUid) do
		if finiteNonNegative(damage, 0) > 0 then
			table.insert(result, uid)
		end
	end
	table.sort(result)
	return result
end

local function cloneDamageByUid(source)
	local result = {}
	for uid, damage in pairs(source or {}) do
		result[uid] = damage
	end
	return result
end

local function buildSnapshot(model, state)
	local totalDamage = math.max(0, state.TotalDamage)
	local minimumDamage = getThreshold(model, Config.MinimumDamageAttributeName, Config.MinimumDamage)
	local minimumShare = math.clamp(
		getThreshold(model, Config.MinimumShareAttributeName, Config.MinimumShare),
		0,
		1
	)
	local participants = {}
	local eligibleUserIds = {}

	for _, participant in pairs(state.Participants) do
		local share = totalDamage > 0 and participant.TotalDamage / totalDamage or 0
		local eligible = participant.TotalDamage >= minimumDamage and share >= minimumShare
		local petUids = sortedPetUids(participant.PetDamageByUid)
		local copy = {
			UserId = participant.UserId,
			Name = participant.Name,
			FirstHitAt = participant.FirstHitAt,
			LastHitAt = participant.LastHitAt,
			TotalDamage = participant.TotalDamage,
			PlayerDamage = participant.PlayerDamage,
			PetDamage = participant.PetDamage,
			HitCount = participant.HitCount,
			PlayerHitCount = participant.PlayerHitCount,
			PetHitCount = participant.PetHitCount,
			Share = share,
			Eligible = eligible,
			PetUids = petUids,
			PetDamageByUid = cloneDamageByUid(participant.PetDamageByUid),
		}
		table.insert(participants, copy)
		if eligible then
			table.insert(eligibleUserIds, participant.UserId)
		end
	end

	table.sort(participants, function(a, b)
		if a.TotalDamage ~= b.TotalDamage then
			return a.TotalDamage > b.TotalDamage
		end
		return a.UserId < b.UserId
	end)
	table.sort(eligibleUserIds)

	return {
		EncounterSerial = state.EncounterSerial,
		Model = model,
		SlimeId = tostring(model:GetAttribute("SlimeId") or model.Name),
		WorldRegionId = tostring(model:GetAttribute("WorldRegionId") or ""),
		WorldPopulationIndex = math.max(0, math.floor(finiteNonNegative(model:GetAttribute("WorldPopulationIndex"), 0))),
		StartedAt = state.StartedAt,
		FinalizedAt = workspace:GetServerTimeNow(),
		MaxHealth = state.MaxHealth,
		TotalDamage = totalDamage,
		MinimumDamage = minimumDamage,
		MinimumShare = minimumShare,
		DefeatingUserId = state.DefeatingUserId,
		DefeatingSourceType = state.DefeatingSourceType,
		DefeatingPetUid = state.DefeatingPetUid,
		Participants = participants,
		EligibleUserIds = eligibleUserIds,
	}
end

local function cloneSnapshot(snapshot)
	if not snapshot then
		return nil
	end
	local copy = table.clone(snapshot)
	copy.Participants = {}
	for _, participant in ipairs(snapshot.Participants or {}) do
		local participantCopy = table.clone(participant)
		participantCopy.PetUids = table.clone(participant.PetUids or {})
		participantCopy.PetDamageByUid = cloneDamageByUid(participant.PetDamageByUid)
		table.insert(copy.Participants, participantCopy)
	end
	copy.EligibleUserIds = table.clone(snapshot.EligibleUserIds or {})
	return copy
end

local function studioLog(snapshot)
	if not RunService:IsStudio() or Config.StudioLogFinalized ~= true then
		return
	end
	print(string.format(
		"[Pawlands Contribution] %s encounter=%d total=%.0f participants=%d eligible=%d.",
		snapshot.SlimeId,
		snapshot.EncounterSerial,
		snapshot.TotalDamage,
		#snapshot.Participants,
		#snapshot.EligibleUserIds
	))
	for index, participant in ipairs(snapshot.Participants) do
		print(string.format(
			"[Pawlands Contribution] #%d %s (%d) total=%.0f share=%.1f%% player=%.0f pet=%.0f pets=[%s] eligible=%s",
			index,
			participant.Name,
			participant.UserId,
			participant.TotalDamage,
			participant.Share * 100,
			participant.PlayerDamage,
			participant.PetDamage,
			table.concat(participant.PetUids, ","),
			tostring(participant.Eligible)
		))
	end
end

local function notify(snapshot)
	studioLog(snapshot)
	for callback in pairs(listeners) do
		local ok, err = pcall(callback, cloneSnapshot(snapshot))
		if not ok then
			warn("[Pawlands Contribution] finalized listener failed: " .. tostring(err))
		end
	end
end

local function finalize(model, state)
	if state.Finalized then
		return state.Snapshot
	end
	state.Finalized = true
	local snapshot = buildSnapshot(model, state)
	state.Snapshot = snapshot
	model:SetAttribute(Config.FinalizedAttributeName, true)
	model:SetAttribute(Config.ParticipantCountAttributeName, #snapshot.Participants)
	model:SetAttribute(Config.EligibleCountAttributeName, #snapshot.EligibleUserIds)
	notify(snapshot)
	return snapshot
end

-- Trusted server-only damage ledger. Call this only after authoritative damage
-- succeeds and pass the effective HP removed (not requested/overkill damage).
function CombatContributionService.RecordDamage(model, player, sourceType, sourceUid, effectiveDamage)
	if not started or not trackable(model) then
		return false
	end
	if not player or not player:IsA("Player") or player.UserId <= 0 then
		return false
	end
	local damage = finiteNonNegative(effectiveDamage, 0)
	if damage <= 0 then
		return false
	end

	local state = ensureState(model)
	if state.Finalized then
		return false
	end
	local participant = ensureParticipant(state, player)
	local now = workspace:GetServerTimeNow()
	participant.LastHitAt = now
	participant.TotalDamage += damage
	participant.HitCount += 1
	state.TotalDamage += damage

	if sourceType == "Pet" then
		local uid = tostring(sourceUid or "")
		participant.PetDamage += damage
		participant.PetHitCount += 1
		if uid ~= "" then
			participant.PetDamageByUid[uid] = (participant.PetDamageByUid[uid] or 0) + damage
		end
	else
		participant.PlayerDamage += damage
		participant.PlayerHitCount += 1
		sourceType = "Player"
		sourceUid = ""
	end

	if model:GetAttribute("Defeated") == true or finiteNonNegative(model:GetAttribute("Health"), 0) <= 0 then
		state.DefeatingUserId = player.UserId
		state.DefeatingSourceType = sourceType
		state.DefeatingPetUid = sourceType == "Pet" and tostring(sourceUid or "") or ""
		finalize(model, state)
	end
	return true
end

function CombatContributionService.GetSnapshot(model)
	local state = model and stateByModel[model]
	if not state then
		return nil
	end
	if state.Finalized then
		return cloneSnapshot(state.Snapshot)
	end
	return cloneSnapshot(buildSnapshot(model, state))
end

function CombatContributionService.GetFinalizedSnapshot(model)
	local state = model and stateByModel[model]
	return state and state.Finalized and cloneSnapshot(state.Snapshot) or nil
end

function CombatContributionService.SubscribeFinalized(callback)
	if type(callback) ~= "function" then
		return function() end
	end
	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

function CombatContributionService.Start()
	if started then
		return
	end
	started = true
	nextEncounterSerial = 0
end

function CombatContributionService.Stop()
	if not started then
		return
	end
	started = false
	table.clear(listeners)
	stateByModel = setmetatable({}, { __mode = "k" })
	nextEncounterSerial = 0
end

return CombatContributionService
