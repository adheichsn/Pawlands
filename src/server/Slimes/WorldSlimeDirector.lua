local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local SlimeCatalog = require(Shared.Config.SlimeCatalog)
local SlimeMovementConfig = require(Shared.Config.SlimeMovement)
local WorldSlimeConfig = require(Shared.Config.WorldSlime)

local SlimeZone = require(script.Parent.SlimeZone)
local WorldSlimeProfileRuntime = require(script.Parent.WorldSlimeProfileRuntime)

local WorldSlimeDirector = {}

local definitionById = {}
for _, definition in ipairs(SlimeCatalog.Variants) do
	definitionById[definition.Id] = definition
end

local function clonePath(path)
	local copy = table.create(#path)
	for index, value in ipairs(path) do
		copy[index] = value
	end
	return copy
end

local function movementConfigFor(path)
	local config = table.clone(SlimeMovementConfig)
	config.ZonePath = path
	for key, value in pairs(WorldSlimeConfig.MovementOverrides) do
		config[key] = value
	end
	return config
end

local function resolveRegionRootPath()
	for _, rootPath in ipairs(WorldSlimeConfig.RegionRootPaths) do
		local node = workspace
		for _, name in ipairs(rootPath) do
			node = node:FindFirstChild(name)
			if not node then
				break
			end
		end
		if node then
			return clonePath(rootPath)
		end
	end
	return nil
end

local function speciesIdForWorldIndex(worldIndex)
	local scores = {}
	local totalWeight = 0
	for _, id in ipairs(WorldSlimeConfig.SpeciesOrder) do
		local weight = math.max(0, tonumber(WorldSlimeConfig.SpeciesWeights[id]) or 0)
		scores[id] = 0
		totalWeight += weight
	end
	if totalWeight <= 0 then
		return SlimeCatalog.Variants[1] and SlimeCatalog.Variants[1].Id or nil
	end

	local selectedId = nil
	for _ = 1, math.max(1, math.floor(worldIndex or 1)) do
		local bestScore = -math.huge
		selectedId = nil
		for _, id in ipairs(WorldSlimeConfig.SpeciesOrder) do
			scores[id] += math.max(0, tonumber(WorldSlimeConfig.SpeciesWeights[id]) or 0)
			if scores[id] > bestScore then
				bestScore = scores[id]
				selectedId = id
			end
		end
		if selectedId then
			scores[selectedId] -= totalWeight
		end
	end
	return selectedId
end

local function spreadIndex(localIndex, capacity)
	if capacity <= 1 then
		return 1
	end
	local half = math.ceil(capacity / 2)
	if localIndex % 2 == 1 then
		return math.min(capacity, math.floor((localIndex + 1) / 2))
	end
	return math.min(capacity, half + math.floor(localIndex / 2))
end

function WorldSlimeDirector.ResolveRegions(runtimeFolder)
	if WorldSlimeConfig.Enabled ~= true then
		return {}
	end

	local rootPath = resolveRegionRootPath()
	if not rootPath then
		warn("[Pawlands WorldSlimes] Missing Stonewood combat region root.")
		return {}
	end

	local regions = {}
	for _, regionName in ipairs(WorldSlimeConfig.RegionNames) do
		local path = clonePath(rootPath)
		table.insert(path, regionName)
		local config = movementConfigFor(path)
		config.SpawnPointName = WorldSlimeConfig.SpawnPointName

		local zone, reason = SlimeZone.new(config, runtimeFolder)
		if zone then
			table.insert(regions, {
				Id = regionName,
				Zone = zone,
				MovementConfig = config,
			})
		else
			warn(string.format(
				"[Pawlands WorldSlimes] Could not resolve %s: %s",
				regionName,
				tostring(reason)
			))
		end
	end

	return regions
end

function WorldSlimeDirector.GetCapacity(regions)
	local capacity = 0
	for _, region in ipairs(regions) do
		capacity += #region.Zone.Points
	end
	return math.min(WorldSlimeConfig.MaxPopulation, capacity)
end

function WorldSlimeDirector.BuildSpawnSpec(regions, worldIndex)
	if #regions <= 0 then
		return nil
	end
	worldIndex = math.max(1, math.floor(tonumber(worldIndex) or 1))
	if worldIndex > WorldSlimeDirector.GetCapacity(regions) then
		return nil
	end

	local regionIndex = ((worldIndex - 1) % #regions) + 1
	local localIndex = math.floor((worldIndex - 1) / #regions) + 1
	local region = regions[regionIndex]
	local maximumSlotsInRegion = math.min(
		#region.Zone.Points,
		math.ceil(WorldSlimeConfig.MaxPopulation / #regions)
	)
	if localIndex > maximumSlotsInRegion then
		return nil
	end

	local authoredPositions = region.Zone:GetInsetSpawnPositions(maximumSlotsInRegion, regionIndex * 13)
	local positionIndex = spreadIndex(localIndex, #authoredPositions)
	local speciesId = speciesIdForWorldIndex(worldIndex)
	local definition = (speciesId and definitionById[speciesId]) or SlimeCatalog.Variants[1]
	if not definition then
		return nil
	end
	local profile = WorldSlimeProfileRuntime.Resolve(definition)

	return {
		WorldIndex = worldIndex,
		Slot = WorldSlimeConfig.SlotBase + worldIndex,
		Definition = definition,
		Profile = profile,
		MovementConfig = WorldSlimeProfileRuntime.BuildMovementConfig(
			region.MovementConfig,
			profile
		),
		Region = region,
		Position = authoredPositions[positionIndex],
	}
end

function WorldSlimeDirector.BuildSpawnPlan(regions, requestedPopulation)
	local count = math.min(
		math.max(0, math.floor(tonumber(requestedPopulation) or 0)),
		WorldSlimeDirector.GetCapacity(regions)
	)
	local plan = table.create(count)
	for worldIndex = 1, count do
		local spec = WorldSlimeDirector.BuildSpawnSpec(regions, worldIndex)
		if spec then
			table.insert(plan, spec)
		end
	end
	return plan
end

function WorldSlimeDirector.TagAgent(agent, region)
	agent.RuntimeKind = "World"
	agent.RuntimeZone = region.Zone
	agent.RuntimeRegionId = region.Id

	local worldIndex = math.max(0, agent.Slot - WorldSlimeConfig.SlotBase)
	local model = agent.Model
	model:SetAttribute("TutorialEncounter", false)
	model:SetAttribute("WorldCombat", true)
	model:SetAttribute("WorldRegionId", region.Id)
	model:SetAttribute("WorldPopulationIndex", worldIndex)
end

return WorldSlimeDirector
