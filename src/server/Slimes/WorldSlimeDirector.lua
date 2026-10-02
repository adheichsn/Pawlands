local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local SlimeCatalog = require(Shared.Config.SlimeCatalog)
local SlimeMovementConfig = require(Shared.Config.SlimeMovement)
local WorldSlimeConfig = require(Shared.Config.WorldSlime)

local SlimeZone = require(script.Parent.SlimeZone)

local WorldSlimeDirector = {}

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

local function distributePopulation(regions, requested)
	local counts = table.create(#regions, 0)
	if #regions <= 0 then
		return counts, 0
	end

	local remaining = math.max(0, math.floor(tonumber(requested) or 0))
	local assigned = 0
	while remaining > 0 do
		local progressed = false
		for index, region in ipairs(regions) do
			if remaining <= 0 then
				break
			end
			if counts[index] < #region.Zone.Points then
				counts[index] += 1
				remaining -= 1
				assigned += 1
				progressed = true
			end
		end
		if not progressed then
			break
		end
	end
	return counts, assigned
end

function WorldSlimeDirector.BuildSpawnPlan(regions)
	local counts, total = distributePopulation(regions, WorldSlimeConfig.Population)
	if total <= 0 then
		return {}
	end

	local plan = table.create(total)
	local worldIndex = 0
	for regionIndex, region in ipairs(regions) do
		local count = counts[regionIndex]
		local positions = region.Zone:GetInsetSpawnPositions(count, regionIndex * 13)
		for localIndex = 1, count do
			worldIndex += 1
			local definitionIndex = ((worldIndex - 1) % #SlimeCatalog.Variants) + 1
			table.insert(plan, {
				Slot = WorldSlimeConfig.SlotBase + worldIndex,
				Definition = SlimeCatalog.Variants[definitionIndex],
				Region = region,
				Position = positions[localIndex],
			})
		end
	end
	return plan
end

function WorldSlimeDirector.TagAgent(agent, region)
	agent.RuntimeKind = "World"
	agent.RuntimeZone = region.Zone
	agent.RuntimeRegionId = region.Id

	local model = agent.Model
	model:SetAttribute("TutorialEncounter", false)
	model:SetAttribute("WorldCombat", true)
	model:SetAttribute("WorldRegionId", region.Id)
end

return WorldSlimeDirector
