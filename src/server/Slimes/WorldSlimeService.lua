local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local MovementConfig = require(Shared.Config.SlimeMovement)
local CombatConfig = require(Shared.Config.SlimeCombat)
local WorldSlimeConfig = require(Shared.Config.WorldSlime)

local SlimeAgent = require(script.Parent.SlimeAgent)
local SlimeAttackRuntime = require(script.Parent.SlimeAttackRuntime)
local SlimeAttackScheduler = require(script.Parent.SlimeAttackScheduler)
local SlimeFactory = require(script.Parent.SlimeFactory)
local SlimeHealth = require(script.Parent.SlimeHealth)
local SlimeTargeting = require(script.Parent.SlimeTargeting)
local WorldSlimeDirector = require(script.Parent.WorldSlimeDirector)
local WorldSlimeLifecycleRuntime = require(script.Parent.WorldSlimeLifecycleRuntime)
local WorldSlimeMotionRuntime = require(script.Parent.WorldSlimeMotionRuntime)
local WorldSlimePopulationRuntime = require(script.Parent.WorldSlimePopulationRuntime)
local WorldSlimeProfileRuntime = require(script.Parent.WorldSlimeProfileRuntime)
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
local populationRefreshAt = 0
local populationFillAt = 0
local populationWarnAt = 0
local populationSpawnSerial = 0
local activeStonewoodPlayers = 0
local targetPopulation = WorldSlimeConfig.Population
local populationCapacity = WorldSlimeConfig.MaxPopulation
local accumulator = 0

local petCombatService = nil
local petVitalsService = nil
local petCombatFeedbackService = nil

local function zoneFor(agent)
	return agent and agent.RuntimeZone or nil
end

local function configFor(agent)
	return WorldSlimeProfileRuntime.MovementConfigFor(agent) or MovementConfig
end

local function combatConfigFor(agent)
	return WorldSlimeProfileRuntime.CombatConfigFor(agent) or CombatConfig
end

local function runtimeContext()
	return {
		Agents = agents,
		Random = randomObject,
		CombatConfig = CombatConfig,
		CombatConfigFor = combatConfigFor,
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

local function spawnSpec(spec, now)
	if not spec or not spec.Region then
		return nil, false, "invalid_spawn_spec"
	end

	populationSpawnSerial += 1
	local seed = (spec.Slot * 37) + (populationSpawnSerial * 53)
	local spawnPosition, safeReason = WorldSlimePopulationRuntime.ResolveSafeSpawnPosition(
		spec.Region.Zone,
		agents,
		seed,
		spec.Position,
		nil
	)
	if not spawnPosition then
		return nil, false, safeReason
	end

	local visual, reason = SlimeFactory.Create(spec.Definition, spec.Slot, runtimeFolder)
	if not visual then
		return nil, false, reason
	end

	visual.Model:SetAttribute("RespawnGeneration", 0)
	visual.Model:SetAttribute("RespawnPending", false)
	local agent = SlimeAgent.new(
		spec.Slot,
		spec.Definition,
		visual,
		spawnPosition,
		spec.MovementConfig or spec.Region.MovementConfig
	)
	WorldSlimeProfileRuntime.Attach(agent, spec.Profile)
	WorldSlimeDirector.TagAgent(agent, spec.Region)
	agent:EnterIdle(now, randomObject)
	agent:Step(agent.Position, 0, agents, spec.Region.Zone, 0.001)
	table.insert(agents, agent)
	return agent, visual.Animation and visual.Animation:HasAuthoredLoop() == true, nil
end

local function retireDefeatedAgents(now)
	for index = #agents, 1, -1 do
		local agent = agents[index]
		if not SlimeHealth.IsAlive(agent.Model) then
			SlimeAttackScheduler.Withdraw(agent)
			SlimeAttackRuntime.Cancel(agent, now, combatConfigFor(agent))
			SlimeTargeting.Clear(agent)
			agent:SetState("Defeated", nil)
			agent:SetCombatReady(false)
			agent.Velocity = Vector3.zero
			if agent.Visual.Animation then
				agent.Visual.Animation:SetMoving(false)
			end

			local worldIndex = WorldSlimePopulationRuntime.WorldIndexFromSlot(agent.Slot)
			local lifecycle = WorldSlimeLifecycleRuntime.Begin(
				agent,
				now,
				randomObject,
				worldIndex >= 1 and worldIndex <= targetPopulation
			)
			lifecycle.RuntimeZone = zoneFor(agent)
			lifecycle.RuntimeRegionId = agent.RuntimeRegionId
			lifecycle.MovementConfig = agent.Config or MovementConfig
			agent:Destroy()
			table.remove(agents, index)
			table.insert(pendingRespawns, lifecycle)
		end
	end
end

local function processPendingRespawns(now)
	for index = #pendingRespawns, 1, -1 do
		local lifecycle = pendingRespawns[index]
		local worldIndex = WorldSlimePopulationRuntime.WorldIndexFromSlot(lifecycle.Slot)
		lifecycle.AllowRespawn = worldIndex >= 1 and worldIndex <= targetPopulation

		local runtimeZone = lifecycle.RuntimeZone
		local movementConfig = lifecycle.MovementConfig or MovementConfig
		local replacement, finished, reason = WorldSlimeLifecycleRuntime.Update(
			lifecycle,
			now,
			runtimeZone,
			agentsInZone(runtimeZone),
			runtimeFolder,
			movementConfig
		)

		if reason and now >= (lifecycle.NextWarnAt or 0) then
			lifecycle.NextWarnAt = now + 5
			warn("[Pawlands WorldSlimes] Respawn retry: " .. tostring(reason))
		end

		if replacement then
			local profile = WorldSlimeProfileRuntime.Resolve(replacement.Definition)
			WorldSlimeProfileRuntime.Attach(replacement, profile)
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
				replacement.Model:SetAttribute("WorldPopulationIndex", worldIndex)
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
			pcall(SlimeAttackRuntime.Cancel, agent, now, combatConfigFor(agent))
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

local function refreshPopulationTarget(now, force)
	if not force and now < populationRefreshAt then
		return
	end
	populationRefreshAt = now + math.max(0.25, WorldSlimeConfig.PopulationRefreshSeconds or 1)

	local previousPlayers = activeStonewoodPlayers
	local previousTarget = targetPopulation
	activeStonewoodPlayers = WorldSlimePopulationRuntime.CountActivePlayers(regions)
	targetPopulation = math.min(
		populationCapacity,
		WorldSlimePopulationRuntime.ResolveTargetPopulation(activeStonewoodPlayers)
	)

	if RunService:IsStudio() and (previousPlayers ~= activeStonewoodPlayers or previousTarget ~= targetPopulation) then
		print(string.format(
			"[Pawlands WorldSlimes] Stonewood population target %d -> %d for %d active player(s).",
			previousTarget,
			targetPopulation,
			activeStonewoodPlayers
		))
	end
end

local function fillPopulation(now)
	if now < populationFillAt then
		return
	end
	local worldIndex = WorldSlimePopulationRuntime.FindMissingWorldIndex(
		agents,
		pendingRespawns,
		targetPopulation
	)
	if not worldIndex then
		return
	end

	populationFillAt = now + math.max(0.1, WorldSlimeConfig.PopulationFillIntervalSeconds or 0.75)
	local spec = WorldSlimeDirector.BuildSpawnSpec(regions, worldIndex)
	if not spec then
		return
	end

	local agent, _, reason = spawnSpec(spec, now)
	if agent then
		if RunService:IsStudio() then
			print(string.format(
				"[Pawlands WorldSlimes] Filled world slot %d with %s in %s (%d/%d target).",
				worldIndex,
				tostring(agent.Model:GetAttribute("SlimeId") or agent.Model.Name),
				tostring(agent.RuntimeRegionId),
				#agents,
				targetPopulation
			))
		end
	elseif reason and now >= populationWarnAt then
		populationWarnAt = now + 5
		warn("[Pawlands WorldSlimes] Population fill waiting: " .. tostring(reason))
	end
end

local function step(dt)
	local now = time()
	pruneOrphanedAgents(now)
	if now >= filterRefreshAt then
		filterRefreshAt = now + 1
		refreshGroundFilters()
	end

	refreshPopulationTarget(now, false)
	retireDefeatedAgents(now)
	processPendingRespawns(now)
	fillPopulation(now)

	local context = runtimeContext()
	WorldSlimeTargetRuntime.UpdateStates(context, now)
	local formationGoals = WorldSlimeMotionRuntime.GetFormationGoals(context, formationStateByPlayer)
	for _, agent in ipairs(agents) do
		WorldSlimeMotionRuntime.StepAgent(context, agent, formationGoals[agent], now, dt)
	end
end

local function spawnInitialPopulation(now)
	local plan = WorldSlimeDirector.BuildSpawnPlan(regions, targetPopulation)
	local spawnedCount = 0
	local authoredLoopCount = 0

	for _, spec in ipairs(plan) do
		local agent, authoredLoop, reason = spawnSpec(spec, now)
		if agent then
			spawnedCount += 1
			if authoredLoop then
				authoredLoopCount += 1
			end
		elseif reason then
			warn(string.format(
				"[Pawlands WorldSlimes] Initial slot %d waiting: %s",
				spec.WorldIndex,
				tostring(reason)
			))
		end
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

	populationCapacity = WorldSlimeDirector.GetCapacity(regions)
	targetPopulation = math.min(WorldSlimeConfig.Population, populationCapacity)
	activeStonewoodPlayers = 0
	local now = time()
	refreshPopulationTarget(now, true)

	running = true
	local spawnedCount, authoredLoopCount = spawnInitialPopulation(now)
	refreshGroundFilters()
	populationFillAt = now + math.max(0.1, WorldSlimeConfig.PopulationFillIntervalSeconds or 0.75)

	local interval = 1 / MovementConfig.UpdateRate
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += math.min(dt, MovementConfig.MaxStep)
		while accumulator >= interval do
			step(interval)
			accumulator -= interval
		end
	end)

	print(string.format(
		"[Pawlands WorldSlimes] Stonewood runtime ready with %d/%d slime(s) across %d region(s), %d active player(s), and %d authored animation loop(s).",
		spawnedCount,
		targetPopulation,
		#regions,
		activeStonewoodPlayers,
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
		SlimeAttackRuntime.Cancel(agent, time(), combatConfigFor(agent))
		SlimeTargeting.Clear(agent)
		agent:Destroy()
		SlimeFactory.Destroy(agent.Visual)
	end
	for _, lifecycle in ipairs(pendingRespawns) do
		WorldSlimeLifecycleRuntime.Cancel(lifecycle)
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
	populationRefreshAt = 0
	populationFillAt = 0
	populationWarnAt = 0
	populationSpawnSerial = 0
	activeStonewoodPlayers = 0
	targetPopulation = WorldSlimeConfig.Population
	populationCapacity = WorldSlimeConfig.MaxPopulation
	accumulator = 0
end

return WorldSlimeService
