local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.WorldSlime)

local WorldSlimePopulationRuntime = {}

local COMBAT_STATES = table.freeze({
	Notice = true,
	Chase = true,
	Engage = true,
	Attack = true,
})

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalDistance(a, b)
	return horizontal(a - b).Magnitude
end

local function aliveRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return root
end

local function playerRoots()
	local roots = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = aliveRoot(player)
		if root then
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

local function nearestSlimeDistance(position, agents, combatOnly)
	local nearest = math.huge
	for _, agent in ipairs(agents) do
		local model = agent and agent.Model
		if model and model.Parent and (not combatOnly or COMBAT_STATES[agent.State] == true) then
			nearest = math.min(nearest, horizontalDistance(position, agent.Position))
		end
	end
	return nearest
end

local function candidateScore(playerDistance, slimeDistance, combatDistance)
	local playerScore = playerDistance / math.max(0.01, Config.SpawnPlayerClearanceStuds)
	local slimeScore = slimeDistance / math.max(0.01, Config.SpawnSlimeClearanceStuds)
	local combatScore = combatDistance / math.max(0.01, Config.SpawnCombatClearanceStuds)
	return math.min(playerScore, slimeScore, combatScore)
end

function WorldSlimePopulationRuntime.CountActivePlayers(regions)
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local root = aliveRoot(player)
		if root then
			for _, region in ipairs(regions) do
				if region.Zone:Contains(root.Position) then
					count += 1
					break
				end
			end
		end
	end
	return count
end

function WorldSlimePopulationRuntime.ResolveTargetPopulation(activePlayers)
	local playerCount = math.max(0, math.floor(tonumber(activePlayers) or 0))
	for _, tier in ipairs(Config.PopulationTiers) do
		if playerCount <= tier.MaxPlayers then
			return tier.Population
		end
	end
	return Config.MaxPopulation
end

function WorldSlimePopulationRuntime.WorldIndexFromSlot(slot)
	return math.floor((tonumber(slot) or Config.SlotBase) - Config.SlotBase)
end

function WorldSlimePopulationRuntime.FindMissingWorldIndex(agents, pendingRespawns, targetPopulation)
	local occupied = {}
	for _, agent in ipairs(agents) do
		local index = WorldSlimePopulationRuntime.WorldIndexFromSlot(agent.Slot)
		if index >= 1 then
			occupied[index] = true
		end
	end
	for _, lifecycle in ipairs(pendingRespawns) do
		local index = WorldSlimePopulationRuntime.WorldIndexFromSlot(lifecycle.Slot)
		if index >= 1 then
			occupied[index] = true
		end
	end

	for index = 1, math.max(0, math.floor(targetPopulation or 0)) do
		if not occupied[index] then
			return index
		end
	end
	return nil
end

function WorldSlimePopulationRuntime.ResolveSafeSpawnPosition(
	zone,
	agents,
	seed,
	preferredPosition,
	deathPosition
)
	if not zone then
		return nil, "missing_zone"
	end

	local roots = playerRoots()
	local candidateCount = math.min(
		math.max(1, math.floor(Config.SpawnCandidateCount or 1)),
		#zone.Points
	)
	local candidates = zone:GetInsetSpawnPositions(candidateCount, seed)
	if preferredPosition then
		table.insert(candidates, 1, preferredPosition)
	end

	local bestPosition = nil
	local bestScore = -math.huge
	for _, candidate in ipairs(candidates) do
		local grounded = zone:GroundPoint(candidate)
		if grounded then
			local playerDistance = nearestPlayerDistance(grounded, roots)
			local slimeDistance = nearestSlimeDistance(grounded, agents, false)
			local combatDistance = nearestSlimeDistance(grounded, agents, true)
			local deathDistance = deathPosition and horizontalDistance(grounded, deathPosition) or math.huge

			if playerDistance >= Config.SpawnPlayerClearanceStuds
				and slimeDistance >= Config.SpawnSlimeClearanceStuds
				and combatDistance >= Config.SpawnCombatClearanceStuds
				and deathDistance >= Config.RespawnDeathClearanceStuds then
				local score = candidateScore(playerDistance, slimeDistance, combatDistance)
				if score > bestScore then
					bestScore = score
					bestPosition = grounded
				end
			end
		end
	end

	if not bestPosition then
		return nil, "no_safe_spawn_candidate"
	end
	return bestPosition, nil
end

return WorldSlimePopulationRuntime
