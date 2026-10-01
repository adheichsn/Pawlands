local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Catalog = require(Shared.Config.SlimeCatalog)
local Config = require(Shared.Config.SlimeMovement)
local CombatConfig = require(Shared.Config.SlimeCombat)
local LifecycleConfig = require(Shared.Config.SlimeLifecycle)

local SlimeAgent = require(script.Parent.SlimeAgent)
local SlimeAttackRuntime = require(script.Parent.SlimeAttackRuntime)
local SlimeAttackScheduler = require(script.Parent.SlimeAttackScheduler)
local SlimeFactory = require(script.Parent.SlimeFactory)
local SlimeFormation = require(script.Parent.SlimeFormation)
local SlimeNavigation = require(script.Parent.SlimeNavigation)
local SlimeTargeting = require(script.Parent.SlimeTargeting)
local SlimeZone = require(script.Parent.SlimeZone)
local SlimeHealth = require(script.Parent.SlimeHealth)
local SlimeLifecycle = require(script.Parent.SlimeLifecycle)

local SlimeMovementService = {}

local running = false
local heartbeatConnection = nil
local agents = {}
local zone = nil
local runtimeFolder = nil
local randomObject = Random.new()
local filterRefreshAt = 0
local accumulator = 0
local formationStateByPlayer = {}
local pendingRespawns = {}
local petCombatService = nil
local petVitalsService = nil
local petCombatFeedbackService = nil
local playerEligibilityResolver = nil
local respawnsEnabled = true
local tutorialEncounterActive = false
local tutorialSpawnedCount = 0
local tutorialPlannedCount = 0

local function getOrCreateRuntimeFolder()
	local existing = Workspace:FindFirstChild(Config.RuntimeFolderName)
	if existing and existing:IsA("Folder") then
		existing:ClearAllChildren()
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Config.RuntimeFolderName
	folder.Parent = Workspace
	return folder
end

local function getRoot(player)
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function isTargetValid(agent, player, disengage)
	if playerEligibilityResolver then
		local ok, eligible = pcall(playerEligibilityResolver, player)
		if not ok or eligible ~= true then
			return false, nil
		end
	end
	local root = getRoot(player)
	if not root or not zone:Contains(root.Position) then
		return false, nil
	end
	local maximum = disengage and Config.DisengageRange or Config.AggroRange
	return agent:DistanceTo(root.Position) <= maximum, root
end

local function chooseOwnerPlayer(agent)
	if agent.TargetPlayer then
		local valid = isTargetValid(agent, agent.TargetPlayer, true)
		if valid then
			return agent.TargetPlayer
		end
	end

	local bestPlayer, bestDistance = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local valid, root = isTargetValid(agent, player, false)
		if valid and root then
			local distance = agent:DistanceTo(root.Position)
			if distance < bestDistance then
				bestPlayer, bestDistance = player, distance
			end
		end
	end
	return bestPlayer
end

local function chooseWanderTarget(agent)
	local angle = randomObject:NextNumber(0, math.pi * 2)
	local scale = Config.WanderMinRadiusScale
		+ randomObject:NextNumber(0, 1) * (1 - Config.WanderMinRadiusScale)
	local radius = Config.WanderRadius * scale
	local target = agent.HomePosition + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	return zone:ClampXZ(target)
end

local function withdrawAttackTurn(agent)
	SlimeAttackScheduler.Withdraw(agent)
end

local function disengage(agent, now)
	withdrawAttackTurn(agent)
	SlimeAttackRuntime.Cancel(agent, now, CombatConfig)
	SlimeTargeting.Clear(agent)
	if agent:DistanceTo(agent.HomePosition) > Config.ReturnHomeDistance then
		agent:EnterReturn()
	else
		agent:EnterIdle(now, randomObject)
	end
end

local function retireDefeatedAgents(now)
	for index = #agents, 1, -1 do
		local agent = agents[index]
		if not SlimeHealth.IsAlive(agent.Model) then
			withdrawAttackTurn(agent)
			SlimeAttackRuntime.Cancel(agent, now, CombatConfig)
			SlimeTargeting.Clear(agent)
			agent:SetState("Defeated", nil)
			agent:SetCombatReady(false)
			agent.Velocity = Vector3.zero
			if agent.Visual.Animation then
				agent.Visual.Animation:SetMoving(false)
			end

			local lifecycle = SlimeLifecycle.Begin(agent, now, LifecycleConfig, respawnsEnabled)
			agent:Destroy()
			table.remove(agents, index)
			table.insert(pendingRespawns, lifecycle)
		end
	end
end

local function processPendingRespawns(now)
	for index = #pendingRespawns, 1, -1 do
		local lifecycle = pendingRespawns[index]
		local replacement, finished, reason = SlimeLifecycle.Update(
			lifecycle,
			now,
			zone,
			agents,
			runtimeFolder,
			Config,
			LifecycleConfig
		)
		if reason and now >= (lifecycle.NextWarnAt or 0) then
			lifecycle.NextWarnAt = now + 5
			warn("[Pawlands Slimes] Respawn retry: " .. tostring(reason))
		end
		if replacement then
			table.insert(agents, replacement)
			if RunService:IsStudio() then
				print(string.format(
					"[Pawlands Slimes] Respawned %s (slot %d, generation %d).",
					tostring(replacement.Model:GetAttribute("SlimeId") or replacement.Model.Name),
					replacement.Slot,
					lifecycle.Generation
				))
			end
		end
		if finished then
			table.remove(pendingRespawns, index)
		end
	end
	if tutorialEncounterActive and #agents == 0 and #pendingRespawns == 0 then
		tutorialEncounterActive = false
	end
end

local function buildPetPressure()
	local pressure = {}
	for _, agent in ipairs(agents) do
		if agent.TargetKind == "Pet" and agent.TargetKey then
			local context = SlimeTargeting.ResolveCurrent(agent, petCombatService, petVitalsService, zone)
			if context then
				SlimeTargeting.AddPressure(pressure, context)
			end
		end
	end
	return pressure
end

local function assignFocus(agent, player, now, pressure)
	local context = SlimeTargeting.Select(
		agent,
		player,
		petCombatService,
		petVitalsService,
		zone,
		CombatConfig,
		pressure,
		randomObject
	)
	if not context then
		return nil
	end
	local changed = SlimeTargeting.Assign(agent, context, now, CombatConfig, randomObject)
	if changed then
		withdrawAttackTurn(agent)
		agent.FormationSlot = nil
		SlimeNavigation.Reset(agent)
	end

	-- A Player selected here is only the safe fallback while the PetCombatService
	-- catches up or while no healthy linked Pet exists. Recheck that fallback on
	-- the short review cadence so a Pet that becomes assigned a frame later can
	-- reclaim its own duel. Deliberate Player retaliation takeover bypasses this
	-- helper and keeps the normal TargetStickMinSeconds lock below.
	if context.Kind == "Player" then
		agent.NextTargetReviewAt = now + math.max(0.1, tonumber(CombatConfig.TargetReviewIntervalSeconds) or 0.45)
	end

	SlimeTargeting.AddPressure(pressure, context)
	return context
end

local function currentOrReviewedFocus(agent, player, now, pressure)
	local context = SlimeTargeting.ResolveCurrent(agent, petCombatService, petVitalsService, zone)
	if not context then
		return assignFocus(agent, player, now, pressure)
	end

	-- Player fallback is not permanent ownership. PetCombatService publishes its
	-- combat assignment on a separate heartbeat, so the first focus decision can
	-- legitimately happen one frame before the linked Pet context exists. Once a
	-- healthy Pet is assigned to this slime, let it reclaim PrimaryOpponent.
	if context.Kind == "Player" and now >= (agent.NextTargetReviewAt or 0) then
		local reviewed = assignFocus(agent, player, now, pressure)
		return reviewed or context
	end

	-- A valid Pet opponent is sticky. Review windows do not randomly pull a slime
	-- off a Pet duel. The only voluntary takeover is deliberate Player retaliation
	-- after enough recent direct hits. That takeover receives the full stick lock.
	if context.Kind == "Pet" and now >= (agent.NextTargetReviewAt or 0) then
		local takeover = SlimeTargeting.TryPlayerTakeover(agent, zone, CombatConfig, now)
		if takeover then
			pressure[context.Key] = math.max(0, (pressure[context.Key] or 0) - 1)
			local changed = SlimeTargeting.Assign(agent, takeover, now, CombatConfig, randomObject)
			if changed then
				withdrawAttackTurn(agent)
				agent.FormationSlot = nil
				SlimeNavigation.Reset(agent)
			end
			return takeover
		end
	end
	return context
end

local function targetReady(agent, context)
	if not context or typeof(context.Position) ~= "Vector3" then
		return false
	end
	local distance = agent:DistanceTo(context.Position)
	return distance <= Config.EngageReadyDistance
		and SlimeNavigation.HasLineOfSight(agent, context.Position, zone)
end

local function updateStates(now)
	local pressure = buildPetPressure()
	for _, agent in ipairs(agents) do
		if not SlimeHealth.IsAlive(agent.Model) then
			withdrawAttackTurn(agent)
			SlimeAttackRuntime.Cancel(agent, now, CombatConfig)
			SlimeTargeting.Clear(agent)
			agent:SetState("Defeated", nil)
			agent:SetCombatReady(false)
			continue
		end

		if agent.State == "Attack" then
			local ownerValid = agent.TargetPlayer and isTargetValid(agent, agent.TargetPlayer, true)
			local context = SlimeTargeting.ResolveCurrent(agent, petCombatService, petVitalsService, zone)
			if not ownerValid then
				disengage(agent, now)
			elseif not context then
				SlimeAttackRuntime.Cancel(agent, now, CombatConfig)
				local replacement = assignFocus(agent, agent.TargetPlayer, now, pressure)
				if replacement then
					if targetReady(agent, replacement) then
						agent:SetState("Engage", agent.TargetPlayer)
						agent:SetCombatReady(true)
					else
						agent:SetState("Chase", agent.TargetPlayer)
						agent:SetCombatReady(false)
					end
				else
					disengage(agent, now)
				end
			end
			continue
		end

		local owner = chooseOwnerPlayer(agent)
		if owner then
			local ownerChanged = owner ~= agent.TargetPlayer
			if ownerChanged
				or agent.State == "Idle"
				or agent.State == "Wander"
				or agent.State == "Return"
			then
				withdrawAttackTurn(agent)
				SlimeTargeting.Clear(agent)
				agent:EnterNotice(owner, now, CombatConfig)
				continue
			end

			if agent.State == "Notice" then
				withdrawAttackTurn(agent)
				if now >= agent.NoticeUntil then
					local context = assignFocus(agent, owner, now, pressure)
					if context and targetReady(agent, context) then
						agent:SetState("Engage", owner)
						agent:SetCombatReady(true)
					else
						agent:SetState("Chase", owner)
						agent:SetCombatReady(false)
					end
				end
				continue
			end

			local context = currentOrReviewedFocus(agent, owner, now, pressure)
			if not context then
				disengage(agent, now)
				continue
			end
			if targetReady(agent, context) then
				agent:SetState("Engage", owner)
				agent:SetCombatReady(true)
			else
				withdrawAttackTurn(agent)
				agent:SetState("Chase", owner)
				agent:SetCombatReady(false)
			end
		elseif agent.State == "Notice" or agent.State == "Chase" or agent.State == "Engage" then
			disengage(agent, now)
		elseif agent.State == "Idle" then
			withdrawAttackTurn(agent)
			if now >= agent.IdleUntil then
				agent:EnterWander(chooseWanderTarget(agent))
			end
		elseif agent.State == "Wander" then
			withdrawAttackTurn(agent)
			if not agent.WanderTarget or agent:DistanceTo(agent.WanderTarget) <= Config.ArrivalRadius then
				agent:EnterIdle(now, randomObject)
			end
		elseif agent.State == "Return" then
			withdrawAttackTurn(agent)
			if agent:DistanceTo(agent.HomePosition) <= Config.ArrivalRadius then
				agent:EnterIdle(now, randomObject)
			end
		else
			withdrawAttackTurn(agent)
			agent:EnterIdle(now, randomObject)
		end
	end
end

local function getFormationGoals()
	local groups = {}
	for _, agent in ipairs(agents) do
		if (agent.State == "Chase" or agent.State == "Engage" or agent.State == "Attack")
			and agent.TargetPlayer
			and agent.TargetKind ~= "Pet"
		then
			groups[agent.TargetPlayer] = groups[agent.TargetPlayer] or {}
			table.insert(groups[agent.TargetPlayer], agent)
		end
	end

	local goals = {}
	for player, group in pairs(groups) do
		local root = getRoot(player)
		if root then
			local state = formationStateByPlayer[player]
			if not state then
				state = {
					Heading = SlimeFormation.ResolveHeading(root, nil),
					LastCount = 0,
				}
				formationStateByPlayer[player] = state
			else
				state.Heading = SlimeFormation.ResolveHeading(root, state.Heading)
			end

			local slots = SlimeFormation.BuildSlots(root, #group, zone, Config, state.Heading)
			local needsAssignment = state.LastCount ~= #group
			if not needsAssignment then
				for _, agent in ipairs(group) do
					if not agent.FormationSlot or not slots[agent.FormationSlot] then
						needsAssignment = true
						break
					end
				end
			end

			if needsAssignment then
				local assigned = SlimeFormation.Assign(group, slots, Config)
				for agent, goal in pairs(assigned) do
					goals[agent] = goal
				end
				state.LastCount = #group
			else
				for _, agent in ipairs(group) do
					goals[agent] = slots[agent.FormationSlot]
				end
			end
		end
	end

	for player in pairs(formationStateByPlayer) do
		if not groups[player] then
			formationStateByPlayer[player] = nil
		end
	end
	return goals
end

local function chaseSpeedFor(agent, goal)
	local distance = agent:DistanceTo(goal)
	local startDistance = Config.ChaseCatchupStartDistance
	local fullDistance = math.max(startDistance + 0.01, Config.ChaseCatchupFullDistance)
	local alpha = math.clamp((distance - startDistance) / (fullDistance - startDistance), 0, 1)
	return Config.ChaseSpeed + (Config.ChaseCatchupMaxSpeed - Config.ChaseSpeed) * alpha
end

local function resolveStrikeTarget(strike)
	return SlimeTargeting.ResolveStrike(strike, petCombatService, petVitalsService, zone)
end

local function applyStrikeDamage(strike, currentTarget, amount)
	if strike.TargetKind == "Pet" then
		if not petVitalsService or not strike.Player or not strike.PetUid then
			return false
		end
		local applied, vitals = petVitalsService.ApplyDamage(strike.Player, strike.PetUid, amount)
		if applied and petCombatFeedbackService then
			petCombatFeedbackService.PublishHit(
				strike.Player,
				strike.PetSlot,
				vitals and vitals.KO == true,
				vitals and vitals.RecoverAt or 0,
				strike.Direction
			)
		end
		return applied == true
	end

	local character = currentTarget.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local healthBefore = humanoid.Health
	humanoid:TakeDamage(amount)
	if character.Parent and humanoid.Health < healthBefore - 0.01 then
		character:SetAttribute("SlimeHitSerial", (character:GetAttribute("SlimeHitSerial") or 0) + 1)
		return true
	end
	return false
end

local function stepAgent(agent, formationGoal, now, dt)
	if not SlimeHealth.IsAlive(agent.Model) then
		agent.Velocity = Vector3.zero
		if agent.Visual.Animation then
			agent.Visual.Animation:SetMoving(false)
		end
		return
	end

	if agent.State == "Attack" then
		SlimeAttackRuntime.Update(
			agent,
			now,
			zone,
			CombatConfig,
			resolveStrikeTarget,
			applyStrikeDamage
		)
		return
	end

	local rawGoal = agent.Position
	local speed = 0
	local facingGoal = nil
	local targetContext = SlimeTargeting.ResolveCurrent(agent, petCombatService, petVitalsService, zone)
	local targetPosition = targetContext and targetContext.Position or nil

	if agent.State == "Notice" and targetPosition then
		withdrawAttackTurn(agent)
		agent:FaceToward(targetPosition, dt)
		if agent.Visual.Animation then
			agent.Visual.Animation:SetMoving(false)
		end
		return
	elseif agent.State == "Chase" and targetPosition then
		withdrawAttackTurn(agent)
		if targetContext.Kind == "Pet" then
			rawGoal = targetPosition
		else
			rawGoal = formationGoal or targetPosition
		end
		speed = chaseSpeedFor(agent, rawGoal)
		facingGoal = targetPosition
	elseif agent.State == "Engage" and targetPosition then
		facingGoal = targetPosition
		local facingReady = agent:IsFacing(targetPosition, CombatConfig.AttackFacingToleranceDegrees)
		if agent.CombatReady and now >= agent.NextAttackAt and facingReady then
			if SlimeAttackRuntime.Begin(agent, targetContext, now, CombatConfig) then
				return
			end
		else
			withdrawAttackTurn(agent)
		end

		if targetContext.Kind == "Pet" then
			-- A pet target is already represented by its server-owned combat proxy.
			-- Hold the achieved duel position instead of chasing a proxy that moves
			-- with the pet's assigned slime; bounded crowd separation still applies.
			rawGoal = agent.Position
			speed = 0
		elseif formationGoal then
			local playerDistance = agent:DistanceTo(targetPosition)
			local slotDistance = agent:DistanceTo(formationGoal)
			if playerDistance > Config.SoftStageReleaseDistance then
				rawGoal = formationGoal
				speed = Config.EngageRepositionSpeed
			elseif playerDistance > Config.EngageInnerDistance
				and slotDistance > Config.SoftStageMaxDrift
			then
				rawGoal = formationGoal
				speed = Config.EngageRepositionSpeed
			else
				rawGoal = agent.Position
				speed = 0
			end
		end
	elseif agent.State == "Wander" and agent.WanderTarget then
		withdrawAttackTurn(agent)
		rawGoal = agent.WanderTarget
		speed = Config.WanderSpeed
	elseif agent.State == "Return" then
		withdrawAttackTurn(agent)
		rawGoal = agent.HomePosition
		speed = Config.ReturnSpeed
	else
		withdrawAttackTurn(agent)
	end

	local resolvedGoal = rawGoal
	if speed > 0 then
		resolvedGoal = SlimeNavigation.ResolveGoal(agent, rawGoal, zone, Config, now)
	end
	agent:Step(resolvedGoal, speed, agents, zone, dt, facingGoal)
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

local function step(dt)
	local now = time()
	pruneOrphanedAgents(now)
	if now >= filterRefreshAt then
		filterRefreshAt = now + 1
		zone:RefreshGroundFilter()
	end

	retireDefeatedAgents(now)
	processPendingRespawns(now)
	updateStates(now)
	local formationGoals = getFormationGoals()
	for _, agent in ipairs(agents) do
		stepAgent(agent, formationGoals[agent], now, dt)
	end
end

local function maximumSpawnCount()
	return math.min(Config.SpawnCount, #Catalog.Variants, #zone.Points)
end

local function spawnAgentRange(startSlot, requestedCount, layoutCount)
	local maximumCount = maximumSpawnCount()
	startSlot = math.clamp(math.floor(tonumber(startSlot) or 1), 1, maximumCount)
	local count = math.clamp(math.floor(tonumber(requestedCount) or 0), 0, maximumCount - startSlot + 1)
	if count <= 0 then
		return 0, 0
	end
	layoutCount = math.clamp(math.floor(tonumber(layoutCount) or (startSlot + count - 1)), 1, maximumCount)
	local spawnPositions = zone:GetInsetSpawnPositions(layoutCount, 0)
	local authoredLoopCount = 0
	local spawnedCount = 0

	for slot = startSlot, startSlot + count - 1 do
		local definition = Catalog.Variants[slot]
		local visual, reason = SlimeFactory.Create(definition, slot, runtimeFolder)
		if not visual then
			warn("[Pawlands Slimes] " .. tostring(reason))
			continue
		end
		if visual.Animation and visual.Animation:HasAuthoredLoop() then
			authoredLoopCount += 1
		end

		local spawnPosition = spawnPositions[slot] or spawnPositions[#spawnPositions]
		local grounded = spawnPosition and zone:GroundPoint(spawnPosition)
		if grounded then
			spawnPosition = grounded
		end
		if not spawnPosition then
			SlimeFactory.Destroy(visual)
			warn(string.format("[Pawlands Slimes] Missing authored spawn position for slot %d.", slot))
			continue
		end
		visual.Model:SetAttribute("RespawnGeneration", 0)
		visual.Model:SetAttribute("RespawnPending", false)
		visual.Model:SetAttribute("TutorialEncounter", tutorialEncounterActive)
		visual.Model:SetAttribute("TutorialSpawnSlot", slot)
		local agent = SlimeAgent.new(slot, definition, visual, spawnPosition, Config)
		agent:EnterIdle(time(), randomObject)
		agent:Step(agent.Position, 0, agents, zone, 0.001)
		table.insert(agents, agent)
		spawnedCount += 1
	end
	return authoredLoopCount, spawnedCount
end

local function spawnAgents(requestedCount)
	local maximumCount = maximumSpawnCount()
	local count = maximumCount
	if requestedCount ~= nil then
		count = math.clamp(math.floor(tonumber(requestedCount) or maximumCount), 1, maximumCount)
	end
	return spawnAgentRange(1, count, count)
end

function SlimeMovementService.Start(petCombat, petVitals, petCombatFeedback)
	if running or not Config.Enabled then
		return
	end
	if not petCombat or not petVitals or not petCombatFeedback then
		error("SlimeMovementService requires PetCombatService, PetVitalsService, and PetCombatFeedbackService.")
	end
	petCombatService = petCombat
	petVitalsService = petVitals
	petCombatFeedbackService = petCombatFeedback
	running = true
	runtimeFolder = getOrCreateRuntimeFolder()
	local resolved, reason = SlimeZone.new(Config, runtimeFolder)
	if not resolved then
		running = false
		petCombatService = nil
		petVitalsService = nil
		petCombatFeedbackService = nil
		warn("[Pawlands Slimes] " .. tostring(reason))
		if runtimeFolder then
			runtimeFolder:Destroy()
			runtimeFolder = nil
		end
		return
	end
	zone = resolved
	local authoredLoopCount = 0
	local spawnedCount = 0
	if Config.SpawnOnStart == true then
		authoredLoopCount, spawnedCount = spawnAgents()
	end

	local interval = 1 / Config.UpdateRate
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += math.min(dt, Config.MaxStep)
		while accumulator >= interval do
			step(interval)
			accumulator -= interval
		end
	end)
	if Config.SpawnOnStart == true then
		print(string.format(
			"[Pawlands Slimes] Combat runtime ready with %d slime(s) and %d authored animation loop(s).",
			spawnedCount,
			authoredLoopCount
		))
	else
		print("[Pawlands Slimes] Combat runtime ready; waiting for tutorial encounter trigger.")
	end
end

function SlimeMovementService.Stop()
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
	SlimeAttackScheduler.Reset()
	if runtimeFolder then
		runtimeFolder:Destroy()
	end
	runtimeFolder, zone = nil, nil
	petCombatService, petVitalsService, petCombatFeedbackService = nil, nil, nil
	playerEligibilityResolver = nil
	respawnsEnabled = true
	tutorialEncounterActive = false
	tutorialSpawnedCount = 0
	tutorialPlannedCount = 0
	accumulator = 0
end

function SlimeMovementService.SetPlayerEligibilityResolver(resolver)
	if resolver ~= nil and type(resolver) ~= "function" then
		error("SetPlayerEligibilityResolver expects a function or nil.")
	end
	playerEligibilityResolver = resolver
end

function SlimeMovementService.ContainsPosition(position, padding)
	return running
		and zone ~= nil
		and typeof(position) == "Vector3"
		and zone:Contains(position, padding)
		or false
end

function SlimeMovementService.GetTutorialEncounterSnapshot()
	local liveCount = 0
	local trackedCount = 0
	if runtimeFolder then
		for _, agent in ipairs(agents) do
			local model = agent.Model
			if model and model.Parent == runtimeFolder then
				trackedCount += 1
				if SlimeHealth.IsAlive(model) then
					liveCount += 1
				end
			end
		end
	end
	return {
		Active = tutorialEncounterActive,
		LiveCount = liveCount,
		TrackedCount = trackedCount,
		PendingCount = #pendingRespawns,
		SpawnedCount = tutorialSpawnedCount,
		PlannedCount = tutorialPlannedCount,
	}
end

function SlimeMovementService.BeginTutorialEncounter(requestedCount, plannedTotalCount)
	if not running or not zone or not runtimeFolder then
		return false, "Slime service is not ready."
	end
	if tutorialEncounterActive or #agents > 0 or #pendingRespawns > 0 then
		return false, "Encounter is busy."
	end
	local maximumCount = maximumSpawnCount()
	tutorialPlannedCount = math.clamp(
		math.floor(tonumber(plannedTotalCount) or tonumber(requestedCount) or maximumCount),
		1,
		maximumCount
	)
	local initialCount = math.clamp(
		math.floor(tonumber(requestedCount) or tutorialPlannedCount),
		1,
		tutorialPlannedCount
	)
	respawnsEnabled = false
	tutorialEncounterActive = true
	tutorialSpawnedCount = 0
	local authoredLoopCount, spawnedCount = spawnAgentRange(1, initialCount, tutorialPlannedCount)
	tutorialSpawnedCount = spawnedCount
	if spawnedCount <= 0 then
		tutorialEncounterActive = false
		tutorialSpawnedCount = 0
		tutorialPlannedCount = 0
		return false, "No tutorial Slimes could be spawned."
	end
	print(string.format(
		"[Pawlands Slimes] Tutorial encounter started with %d/%d slime(s) and %d authored animation loop(s).",
		spawnedCount,
		tutorialPlannedCount,
		authoredLoopCount
	))
	return true, spawnedCount
end

function SlimeMovementService.AddTutorialSlimes(requestedCount)
	if not running or not tutorialEncounterActive or not zone or not runtimeFolder then
		return false, "Tutorial encounter is not active."
	end
	local remainingCapacity = math.max(0, tutorialPlannedCount - tutorialSpawnedCount)
	local count = math.clamp(math.floor(tonumber(requestedCount) or remainingCapacity), 0, remainingCapacity)
	if count <= 0 then
		return true, 0
	end
	local startSlot = tutorialSpawnedCount + 1
	local authoredLoopCount, spawnedCount = spawnAgentRange(startSlot, count, tutorialPlannedCount)
	tutorialSpawnedCount += spawnedCount
	if spawnedCount > 0 then
		print(string.format(
			"[Pawlands Slimes] Tutorial encounter expanded by %d slime(s) (%d/%d spawned, %d authored loop(s)).",
			spawnedCount,
			tutorialSpawnedCount,
			tutorialPlannedCount,
			authoredLoopCount
		))
	end
	if spawnedCount < count then
		warn(string.format(
			"[Pawlands Slimes] Tutorial expansion requested %d slime(s) but only %d spawned.",
			count,
			spawnedCount
		))
	end
	-- A partial authored spawn is still a usable encounter. TutorialService will
	-- reduce the authoritative clear goal to the number that actually exists.
	return true, spawnedCount
end

function SlimeMovementService.CancelTutorialEncounter()
	if not running then
		return
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
	SlimeAttackScheduler.Reset()
	tutorialEncounterActive = false
	tutorialSpawnedCount = 0
	tutorialPlannedCount = 0
	respawnsEnabled = false
end

return SlimeMovementService
