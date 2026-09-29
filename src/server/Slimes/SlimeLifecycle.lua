local Players = game:GetService("Players")

local SlimeAgent = require(script.Parent.SlimeAgent)
local SlimeFactory = require(script.Parent.SlimeFactory)

local SlimeLifecycle = {}

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalDistance(a, b)
	return horizontal(a - b).Magnitude
end

local function playerRootsInside(zone)
	local roots = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and zone:Contains(root.Position) then
			table.insert(roots, root)
		end
	end
	return roots
end

local function nearestPlayerDistance(position, roots)
	local nearest = math.huge
	for _, root in ipairs(roots) do
		nearest = math.min(nearest, horizontalDistance(position, root.Position))
	end
	return nearest
end

local function nearestSlimeDistance(position, agents)
	local nearest = math.huge
	for _, agent in ipairs(agents) do
		if agent.Model and agent.Model.Parent then
			nearest = math.min(nearest, horizontalDistance(position, agent.Position))
		end
	end
	return nearest
end

local function resolveRespawnPosition(record, zone, agents, config)
	local candidateCount = math.min(
		math.max(1, math.floor(config.RespawnCandidateCount or 1)),
		#zone.Points
	)
	local seed = (record.Slot * 17) + (record.Generation * 31)
	local candidates = zone:GetInsetSpawnPositions(candidateCount, seed)
	local playerRoots = playerRootsInside(zone)
	local bestPosition = nil
	local bestScore = -math.huge

	for _, candidate in ipairs(candidates) do
		local grounded = zone:GroundPoint(candidate) or zone:ClampXZ(candidate)
		local playerDistance = nearestPlayerDistance(grounded, playerRoots)
		local slimeDistance = nearestSlimeDistance(grounded, agents)
		local deathDistance = horizontalDistance(grounded, record.DeathPosition)

		if playerDistance >= config.RespawnPlayerClearanceStuds
			and slimeDistance >= config.RespawnSlimeClearanceStuds
			and deathDistance >= config.RespawnDeathClearanceStuds then
			local playerScore = playerDistance / math.max(0.01, config.RespawnPlayerClearanceStuds)
			local slimeScore = slimeDistance / math.max(0.01, config.RespawnSlimeClearanceStuds)
			local deathScore = deathDistance / math.max(0.01, config.RespawnDeathClearanceStuds)
			local score = math.min(playerScore, slimeScore, deathScore)
			if score > bestScore then
				bestScore = score
				bestPosition = grounded
			end
		end
	end

	return bestPosition
end

function SlimeLifecycle.Begin(agent, now, config)
	local generation = (agent.Model:GetAttribute("RespawnGeneration") or 0) + 1
	local despawnAt = now + math.max(0, config.DefeatPresentationSeconds or 0)
	local respawnAt = despawnAt + math.max(0, config.RespawnDelaySeconds or 0)

	agent.Model:SetAttribute("RespawnPending", true)
	agent.Model:SetAttribute("DefeatHoldUntil", despawnAt)
	agent.Model:SetAttribute("RespawnAt", respawnAt)
	if agent.Visual.Animation then
		agent.Visual.Animation:SetMoving(false)
	end

	return {
		Slot = agent.Slot,
		Definition = agent.Definition,
		Visual = agent.Visual,
		DeathPosition = agent.Position,
		Generation = generation,
		DespawnAt = despawnAt,
		RespawnAt = respawnAt,
		Despawned = false,
	}
end

function SlimeLifecycle.Update(record, now, zone, agents, runtimeFolder, movementConfig, config)
	if not record.Despawned and now >= record.DespawnAt then
		record.Despawned = true
		if record.Visual then
			SlimeFactory.Destroy(record.Visual)
			record.Visual = nil
		end
	end

	if not record.Despawned or now < record.RespawnAt then
		return nil, false
	end

	local spawnPosition = resolveRespawnPosition(record, zone, agents, config)
	if not spawnPosition then
		record.RespawnAt = now + math.max(0.1, config.RespawnRetrySeconds or 1)
		return nil, false
	end

	local visual, reason = SlimeFactory.Create(record.Definition, record.Slot, runtimeFolder)
	if not visual then
		record.RespawnAt = now + math.max(0.1, config.RespawnRetrySeconds or 1)
		return nil, false, reason
	end

	local grounded = zone:GroundPoint(spawnPosition)
	if grounded then
		spawnPosition = grounded
	end

	visual.Model:SetAttribute("RespawnGeneration", record.Generation)
	visual.Model:SetAttribute("RespawnPending", false)
	local agent = SlimeAgent.new(record.Slot, record.Definition, visual, spawnPosition, movementConfig)
	agent:EnterIdle(now, Random.new(record.Slot * 1009 + record.Generation * 9176))
	agent:Step(agent.Position, 0, agents, zone, 0.001)
	return agent, true
end

function SlimeLifecycle.Cancel(record)
	if record and record.Visual then
		SlimeFactory.Destroy(record.Visual)
		record.Visual = nil
	end
end

return SlimeLifecycle
