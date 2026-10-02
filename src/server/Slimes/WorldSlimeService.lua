local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local MovementConfig = require(Shared.Config.SlimeMovement)
local CombatConfig = require(Shared.Config.SlimeCombat)
local LifecycleConfig = require(Shared.Config.SlimeLifecycle)
local WorldSlimeConfig = require(Shared.Config.WorldSlime)

local SlimeAgent = require(script.Parent.SlimeAgent)
local SlimeAttackRuntime = require(script.Parent.SlimeAttackRuntime)
local SlimeAttackScheduler = require(script.Parent.SlimeAttackScheduler)
local SlimeFactory = require(script.Parent.SlimeFactory)
local SlimeHealth = require(script.Parent.SlimeHealth)
local SlimeLifecycle = require(script.Parent.SlimeLifecycle)
local SlimeTargeting = require(script.Parent.SlimeTargeting)
local WorldSlimeDirector = require(script.Parent.WorldSlimeDirector)
local WorldSlimeMotionRuntime = require(script.Parent.WorldSlimeMotionRuntime)
local WorldSlimeTargetRuntime = require(script.Parent.WorldSlimeTargetRuntime)

local WorldSlimeService = {}

local running = false
local heartbeatConnection = nil
local runtimeFolder = nil
local regions = {}
local agents = {}
local pendingRespawns = {}
local formationStateByPlayer = {}
local randomObject = Random.new()
local filterRefreshAt = 0
local accumulator = 0

local petCombatService = nil
local petVitalsService = nil
local petCombatFeedbackService = nil

local function zoneFor(agent)
	return agent and agent.RuntimeZone or nil
end

local function configFor(agent)
	return agent and agent.Config or MovementConfig
end

local function runtimeContext()
	return {
		Agents = agents,
		Random = randomObject,
		CombatConfig = CombatConfig,
		PetCombatService = petCombatService,
		PetVitalsService = petVitalsService,
		PetCombatFeedbackService = petCombatFeedbackService,
		ZoneFor = zoneFor,
		ConfigFor = configFor,
	}
end

local function regionById(regionId)
	for _, region in ipairs(regions) do
		if region.Id == regionId then
			return region
		end
	end
	return nil
end

local function agentsInZone(runtimeZone)
	local result = {}
	for _, agent in ipairs(agents) do
		if zoneFor(agent) == runtimeZone then
			table.insert(result, agent)
		end
	end
	return result
end

local function retireDefeatedAgents(now)
	for index = #agents, 1, -1 do
		local agent = agents[index]
		if not SlimeHealth.IsAlive(agent.Model) then
			SlimeAttackScheduler.Withdraw(agent)
			SlimeAttackRuntime.Cancel(agent, now, CombatConfig)
			SlimeTargeting.Clear(agent)
			agent:SetState("Defeated", nil)
			agent:SetCombatReady(false)
			agent.Velocity = Vector3.zero
			if agent.Visual.Animation then
				agent.Visual.Animation:SetMoving(false)
			end

			local lifecycle = SlimeLifecycle.Begin(agent, now, LifecycleConfig, true)
			lifecycle.RuntimeZone = zoneFor(agent)
			lifecycle.RuntimeRegionId = agent.RuntimeRegionId
			lifecycle.MovementConfig = configFor(agent)
			agent:Destroy()
			table.remove(agents, index)
			table.insert(pendingRespawns, lifecycle)
		end
	end
end

local function processPendingRespawns(now)
	for index = #pendingRespawns, 1, -1 do
		local lifecycle = pendingRespawns[index]
		local runtimeZone = lifecycle.RuntimeZone
		local movementConfig = lifecycle.MovementConfig or MovementConfig
		local replacement, finished, reason = SlimeLifecycle.Update(
			lifecycle,
			now,
			runtimeZone,
			agentsInZone(runtimeZone),
			runtimeFolder,
			movementConfig,
			LifecycleConfig
		)

		if reason and now >= (lifecycle.NextWarnAt or 0) then
			lifecycle.NextWarnAt = now + 5
			warn("[Pawlands WorldSlimes] Respawn retry: " .. tostring(reason))
		end

		if replacement then
			local region = regionById(lifecycle.RuntimeRegionId)
			if region then
				WorldSlimeDirector.TagAgent(replacement, region)
			else
				replacement.RuntimeKind = "World"
				replacement.RuntimeZone = runtimeZone
				replacement.RuntimeRegionId = lifecycle.RuntimeRegionId
				replacement.Model:SetAttribute("TutorialEncounter", false)
				replacement.Model:SetAttribute("WorldCombat", true)
				replacement.Model:SetAttribute("WorldRegionId", lifecycle.RuntimeRegionId or "")
			end
			table.insert(agents, replacement)
			if RunService:IsStudio() then
				print(string.format(
					"[Pawlands WorldSlimes] Respawned %s in %s (slot %d, generation %d).",
					tostring(replacement.Model:GetAttribute("SlimeId") or replacement.Model.Name),
					tostring(lifecycle.RuntimeRegionId),
					replacement.Slot,
					lifecycle.Generation
				))
			end
		end

		if finished then
			table.remove(pendingRespawns, index)
		end
	end
end

local function pruneOrphanedAgents(now)
	for index = #agents, 1, -1 do
		local agent = agents[index]
		local model = agent and agent.Model
		if not model or model.Parent ~= runtimeFolder then
			pcall(SlimeAttackScheduler.Withdraw, agent)
			pcall(SlimeAttackRuntime.Cancel, agent, now, CombatConfig)
			pcall(SlimeTargeting.Clear, agent)
			if agent and agent.Visual and agent.Visual.Animation then
				pcall(function()
					agent.Visual.Animation:Destroy()
				end)
				agent.Visual.Animation = nil
			end
			table.remove(agents, index)
		end
	end
end

local function refreshGroundFilters()
	for _, region in ipairs(regions) do
		region.Zone:RefreshGroundFilter()
	end
end

local function step(dt)
	local now = time()
	pruneOrphanedAgents(now)
	if now >= filterRefreshAt then
		filterRefreshAt = now + 1
		refreshGroundFilters()
	end

	retireDefeatedAgents(now)
	processPendingRespawns(now)

	local context = runtimeContext()
	WorldSlimeTargetRuntime.UpdateStates(context, now)
	local formationGoals = WorldSlimeMotionRuntime.GetFormationGoals(context, formationStateByPlayer)
	for _, agent in ipairs(agents) do
		WorldSlimeMotionRuntime.StepAgent(context, agent, formationGoals[agent], now, dt)
	end
end

local function spawnInitialPopulation()
	local plan = WorldSlimeDirector.BuildSpawnPlan(regions)
	local spawnedCount = 0
	local authoredLoopCount = 0

	for _, spec in ipairs(plan) do
		local region = spec.Region
		local runtimeZone = region.Zone
		local spawnPosition = spec.Position
		local grounded = spawnPosition and runtimeZone:GroundPoint(spawnPosition)
		if grounded then
			spawnPosition = grounded
		end
		if not spawnPosition then
			warn(string.format(
				"[Pawlands WorldSlimes] Could not ground slot %d in %s.",
				spec.Slot,
				region.Id
			))
			continue
		end

		local visual, reason = SlimeFactory.Create(spec.Definition, spec.Slot, runtimeFolder)
		if not visual then
			warn("[Pawlands WorldSlimes] " .. tostring(reason))
			continue
		end
		if visual.Animation and visual.Animation:HasAuthoredLoop() then
			authoredLoopCount += 1
		end

		visual.Model:SetAttribute("RespawnGeneration", 0)
		visual.Model:SetAttribute("RespawnPending", false)
		local agent = SlimeAgent.new(
			spec.Slot,
			spec.Definition,
			visual,
			spawnPosition,
			region.MovementConfig
		)
		WorldSlimeDirector.TagAgent(agent, region)
		agent:EnterIdle(time(), randomObject)
		agent:Step(agent.Position, 0, agents, runtimeZone, 0.001)
		table.insert(agents, agent)
		spawnedCount += 1
	end

	return spawnedCount, authoredLoopCount
end

function WorldSlimeService.Start(petCombat, petVitals, petCombatFeedback)
	if running or WorldSlimeConfig.Enabled ~= true then
		return
	end
	if not petCombat or not petVitals or not petCombatFeedback then
		error("WorldSlimeService requires PetCombatService, PetVitalsService, and PetCombatFeedbackService.")
	end

	local folder = Workspace:FindFirstChild(MovementConfig.RuntimeFolderName)
	if not folder or not folder:IsA("Folder") then
		warn("[Pawlands WorldSlimes] Shared PawlandsSlimes runtime folder is not ready.")
		return
	end

	petCombatService = petCombat
	petVitalsService = petVitals
	petCombatFeedbackService = petCombatFeedback
	runtimeFolder = folder
	regions = WorldSlimeDirector.ResolveRegions(runtimeFolder)
	if #regions <= 0 then
		runtimeFolder = nil
		petCombatService = nil
		petVitalsService = nil
		petCombatFeedbackService = nil
		warn("[Pawlands WorldSlimes] No valid Stonewood regions; world combat runtime was not started.")
		return
	end

	running = true
	local spawnedCount, authoredLoopCount = spawnInitialPopulation()
	refreshGroundFilters()

	local interval = 1 / MovementConfig.UpdateRate
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += math.min(dt, MovementConfig.MaxStep)
		while accumulator >= interval do
			step(interval)
			accumulator -= interval
		end
	end)

	print(string.format(
		"[Pawlands WorldSlimes] Stonewood runtime ready with %d/%d slime(s) across %d region(s) and %d authored animation loop(s).",
		spawnedCount,
		WorldSlimeConfig.Population,
		#regions,
		authoredLoopCount
	))
end

function WorldSlimeService.Stop()
	if not running then
		return
	end
	running = false

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end

	for _, agent in ipairs(agents) do
		SlimeAttackScheduler.Withdraw(agent)
		SlimeAttackRuntime.Cancel(agent, time(), CombatConfig)
		SlimeTargeting.Clear(agent)
		agent:Destroy()
		SlimeFactory.Destroy(agent.Visual)
	end
	for _, lifecycle in ipairs(pendingRespawns) do
		SlimeLifecycle.Cancel(lifecycle)
	end

	table.clear(agents)
	table.clear(pendingRespawns)
	table.clear(formationStateByPlayer)
	table.clear(regions)

	runtimeFolder = nil
	petCombatService = nil
	petVitalsService = nil
	petCombatFeedbackService = nil
	filterRefreshAt = 0
	accumulator = 0
end

return WorldSlimeService
