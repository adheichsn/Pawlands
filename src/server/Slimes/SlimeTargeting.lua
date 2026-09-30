local SlimeTargeting = {}

local function playerKey(player)
	return string.format("player:%d", player.UserId)
end

local function petKey(player, uid)
	return string.format("pet:%d:%s", player.UserId, tostring(uid))
end

local function resolvePlayer(player, zone)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	if not zone:Contains(root.Position) then
		return nil
	end
	return {
		Kind = "Player",
		Key = playerKey(player),
		Player = player,
		Position = root.Position,
		Root = root,
		Character = character,
	}
end

local function petContexts(player, petCombatService, vitalsService, zone)
	local result = {}
	if not petCombatService or not vitalsService then
		return result
	end
	for slot, entry in pairs(petCombatService.GetCombatTargets(player)) do
		local position = entry.Position
		if typeof(position) == "Vector3"
			and vitalsService.CanCombat(player, entry.Uid)
		then
			table.insert(result, {
				Kind = "Pet",
				Key = petKey(player, entry.Uid),
				Player = player,
				PetSlot = slot,
				PetUid = entry.Uid,
				Position = position,
				AssignedSlimeModel = entry.SlimeModel,
			})
		end
	end
	table.sort(result, function(a, b)
		return a.PetSlot < b.PetSlot
	end)
	return result
end

local function linkedPetCandidates(agent, player, petCombatService, vitalsService, zone, config, pressure)
	local linked = {}
	for _, context in ipairs(petContexts(player, petCombatService, vitalsService, zone)) do
		if context.AssignedSlimeModel == agent.Model then
			local count = pressure[context.Key] or 0
			if count < math.max(1, config.MaxSlimesPerPet or 2) then
				table.insert(linked, context)
			end
		end
	end
	table.sort(linked, function(a, b)
		local aPressure = pressure[a.Key] or 0
		local bPressure = pressure[b.Key] or 0
		if aPressure ~= bPressure then
			return aPressure < bPressure
		end
		local aDistance = agent:DistanceTo(a.Position)
		local bDistance = agent:DistanceTo(b.Position)
		if math.abs(aDistance - bDistance) > 0.01 then
			return aDistance < bDistance
		end
		return a.PetSlot < b.PetSlot
	end)
	return linked
end

function SlimeTargeting.ResolveStrike(strike, petCombatService, vitalsService, zone)
	if not strike or not strike.Player then
		return nil
	end
	if strike.TargetKind == "Pet" and strike.PetUid then
		for _, context in ipairs(petContexts(strike.Player, petCombatService, vitalsService, zone)) do
			if context.PetUid == strike.PetUid then
				return context
			end
		end
		return nil
	end
	return resolvePlayer(strike.Player, zone)
end

function SlimeTargeting.ResolveCurrent(agent, petCombatService, vitalsService, zone)
	local player = agent.TargetPlayer
	if not player then
		return nil
	end
	if agent.TargetKind == "Pet" and agent.TargetPetUid then
		for _, context in ipairs(petContexts(player, petCombatService, vitalsService, zone)) do
			if context.PetUid == agent.TargetPetUid and context.AssignedSlimeModel == agent.Model then
				return context
			end
		end
		return nil
	end
	return resolvePlayer(player, zone)
end

function SlimeTargeting.Select(agent, player, petCombatService, vitalsService, zone, config, pressure, _randomObject)
	local playerContext = resolvePlayer(player, zone)
	if not playerContext then
		return nil
	end

	-- Engagement ownership wins over periodic weighted rerolls. A healthy Pet that
	-- is actually fighting this slime becomes the readable primary opponent.
	local linked = linkedPetCandidates(agent, player, petCombatService, vitalsService, zone, config, pressure)
	if #linked > 0 then
		return linked[1]
	end

	-- No linked healthy Pet means the Player is the safe fallback. This also
	-- covers zero-pet and all-pets-KO states without cross-targeting somebody
	-- else's duel partner.
	return playerContext
end

function SlimeTargeting.Assign(agent, context, now, config, _randomObject)
	if not context then
		return false
	end
	local changed = agent.TargetKind ~= context.Kind
		or agent.TargetKey ~= context.Key
		or agent.TargetPetUid ~= context.PetUid

	agent.TargetKind = context.Kind
	agent.TargetKey = context.Key
	agent.TargetPetSlot = context.PetSlot
	agent.TargetPetUid = context.PetUid
	agent.NextTargetReviewAt = now + math.max(0.1, config.TargetStickMinSeconds or 2.5)
	agent.TargetPlayerHitSerialAtAcquire = tonumber(agent.Model:GetAttribute("PlayerHitSerial")) or 0

	agent.Model:SetAttribute("TargetType", context.Kind)
	agent.Model:SetAttribute("TargetPetSlot", context.PetSlot or 0)
	agent.Model:SetAttribute("TargetPetUid", context.PetUid or "")
	return changed
end

function SlimeTargeting.TryPlayerTakeover(agent, zone, config, now)
	if agent.TargetKind ~= "Pet" or not agent.TargetPlayer then
		return nil
	end
	if now < (agent.NextTargetReviewAt or 0) then
		return nil
	end

	local currentSerial = tonumber(agent.Model:GetAttribute("PlayerHitSerial")) or 0
	local baseline = tonumber(agent.TargetPlayerHitSerialAtAcquire) or currentSerial
	local directHits = math.max(0, currentSerial - baseline)
	local requiredHits = math.max(1, math.floor(tonumber(config.PlayerTakeoverHitCount) or 3))
	local lastHitAt = tonumber(agent.Model:GetAttribute("LastPlayerHitAt")) or 0
	local lastHitUserId = tonumber(agent.Model:GetAttribute("LastPlayerHitUserId")) or 0
	local recentWindow = math.max(0.1, tonumber(config.PlayerTakeoverWindowSeconds) or 2.4)

	if directHits < requiredHits
		or lastHitUserId ~= agent.TargetPlayer.UserId
		or now - lastHitAt > recentWindow
	then
		agent.NextTargetReviewAt = now + math.max(0.1, tonumber(config.TargetReviewIntervalSeconds) or 0.45)
		return nil
	end

	return resolvePlayer(agent.TargetPlayer, zone)
end

function SlimeTargeting.Clear(agent)
	agent.TargetKind = nil
	agent.TargetKey = nil
	agent.TargetPetSlot = nil
	agent.TargetPetUid = nil
	agent.NextTargetReviewAt = 0
	agent.TargetPlayerHitSerialAtAcquire = 0
	if agent.Model then
		agent.Model:SetAttribute("TargetType", "None")
		agent.Model:SetAttribute("TargetPetSlot", 0)
		agent.Model:SetAttribute("TargetPetUid", "")
	end
end

function SlimeTargeting.AddPressure(pressure, context)
	if context and context.Kind == "Pet" then
		pressure[context.Key] = (pressure[context.Key] or 0) + 1
	end
end

return SlimeTargeting
