local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local BaseLifecycleConfig = require(Shared.Config.SlimeLifecycle)
local WorldSlimeConfig = require(Shared.Config.WorldSlime)

local SlimeAgent = require(script.Parent.SlimeAgent)
local SlimeFactory = require(script.Parent.SlimeFactory)
local SlimeLifecycle = require(script.Parent.SlimeLifecycle)
local WorldSlimePopulationRuntime = require(script.Parent.WorldSlimePopulationRuntime)

local WorldSlimeLifecycleRuntime = {}

local function lifecycleConfig(randomObject)
	local config = table.clone(BaseLifecycleConfig)
	local minimum = tonumber(WorldSlimeConfig.RespawnDelayMinSeconds) or config.RespawnDelaySeconds
	local maximum = tonumber(WorldSlimeConfig.RespawnDelayMaxSeconds) or minimum
	if maximum < minimum then
		minimum, maximum = maximum, minimum
	end
	config.RespawnDelaySeconds = randomObject:NextNumber(minimum, maximum)
	config.RespawnRetrySeconds = WorldSlimeConfig.RespawnRetrySeconds or config.RespawnRetrySeconds
	return config
end

function WorldSlimeLifecycleRuntime.Begin(agent, now, randomObject, allowRespawn)
	local config = lifecycleConfig(randomObject)
	local record = SlimeLifecycle.Begin(agent, now, config, allowRespawn)
	record.WorldLifecycleConfig = config
	return record
end

function WorldSlimeLifecycleRuntime.Update(record, now, zone, agents, runtimeFolder, movementConfig)
	local config = record.WorldLifecycleConfig or BaseLifecycleConfig
	if not record.Despawned and now >= record.DespawnAt then
		record.Despawned = true
		if record.Visual then
			SlimeFactory.Destroy(record.Visual)
			record.Visual = nil
		end
	end

	if record.Despawned and record.AllowRespawn == false then
		return nil, true
	end
	if not record.Despawned or now < record.RespawnAt then
		return nil, false
	end

	local seed = (record.Slot * 17) + (record.Generation * 31)
	local spawnPosition = WorldSlimePopulationRuntime.ResolveSafeSpawnPosition(
		zone,
		agents,
		seed,
		nil,
		record.DeathPosition
	)
	if not spawnPosition then
		record.RespawnAt = now + math.max(0.1, config.RespawnRetrySeconds or 1)
		return nil, false
	end

	local visual, reason = SlimeFactory.Create(record.Definition, record.Slot, runtimeFolder)
	if not visual then
		record.RespawnAt = now + math.max(0.1, config.RespawnRetrySeconds or 1)
		return nil, false, reason
	end

	visual.Model:SetAttribute("RespawnGeneration", record.Generation)
	visual.Model:SetAttribute("RespawnPending", false)
	local agent = SlimeAgent.new(record.Slot, record.Definition, visual, spawnPosition, movementConfig)
	agent:EnterIdle(now, Random.new(record.Slot * 1009 + record.Generation * 9176))
	agent:Step(agent.Position, 0, agents, zone, 0.001)
	return agent, true
end

function WorldSlimeLifecycleRuntime.Cancel(record)
	SlimeLifecycle.Cancel(record)
end

return WorldSlimeLifecycleRuntime
