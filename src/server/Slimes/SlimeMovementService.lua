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
	local root = getRoot(player)
	if not root or not zone:Contains(root.Position) then
		return false, nil
	end
	local maximum = disengage and Config.DisengageRange or Config.AggroRange
	return agent:DistanceTo(root.Position) <= maximum, root
end

local function chooseTarget(agent)
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
			agent:SetState("Defeated", nil)
			agent:SetCombatReady(false)
			agent.Velocity = Vector3.zero
			if agent.Visual.Animation then
				agent.Visual.Animation:SetMoving(false)
			end

			local lifecycle = SlimeLifecycle.Begin(agent, now, LifecycleConfig)
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
end

local function updateStates(now)
	for _, agent in ipairs(agents) do
		if not SlimeHealth.IsAlive(agent.Model) then
			withdrawAttackTurn(agent)
			SlimeAttackRuntime.Cancel(agent, now, CombatConfig)
			agent:SetState("Defeated", nil)
			agent:SetCombatReady(false)
			continue
		end

		if agent.State == "Attack" then
			local valid = agent.TargetPlayer and isTargetValid(agent, agent.TargetPlayer, true)
			if not valid then
				disengage(agent, now)
			end
			continue
		end

		local target = chooseTarget(agent)
		if target then
			local targetChanged = target ~= agent.TargetPlayer
			if targetChanged
				or agent.State == "Idle"
				or agent.State == "Wander"
				or agent.State == "Return"
			then
				withdrawAttackTurn(agent)
				agent:EnterNotice(target, now, CombatConfig)
				continue
			end

			if agent.State == "Notice" then
				withdrawAttackTurn(agent)
				if now >= agent.NoticeUntil then
					agent:SetState("Chase", target)
				end
				continue
			end

			local root = getRoot(target)
			local ready = false
			if root then
				local distance = agent:DistanceTo(root.Position)
				ready = distance <= Config.EngageReadyDistance
					and SlimeNavigation.HasLineOfSight(agent, root.Position, zone)
			end
			if ready then
				agent:SetState("Engage", target)
				agent:SetCombatReady(true)
			else
				withdrawAttackTurn(agent)
				agent:SetState("Chase", target)
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
		if (agent.State == "Chase" or agent.State == "Engage" or agent.State == "Attack") and agent.TargetPlayer then
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

local function stepAgent(agent, formationGoal, now, dt)
	if not SlimeHealth.IsAlive(agent.Model) then
		agent.Velocity = Vector3.zero
		if agent.Visual.Animation then
			agent.Visual.Animation:SetMoving(false)
		end
		return
	end

	if agent.State == "Attack" then
		SlimeAttackRuntime.Update(agent, now, zone, CombatConfig)
		return
	end

	local rawGoal = agent.Position
	local speed = 0
	local facingGoal = nil
	local targetRoot = agent.TargetPlayer and getRoot(agent.TargetPlayer) or nil

	if agent.State == "Notice" and targetRoot then
		withdrawAttackTurn(agent)
		agent:FaceToward(targetRoot.Position, dt)
		if agent.Visual.Animation then
			agent.Visual.Animation:SetMoving(false)
		end
		return
	elseif agent.State == "Chase" and formationGoal and targetRoot then
		withdrawAttackTurn(agent)
		rawGoal = formationGoal
		speed = chaseSpeedFor(agent, rawGoal)
		facingGoal = targetRoot.Position
	elseif agent.State == "Engage" and formationGoal and targetRoot then
		facingGoal = targetRoot.Position
		if agent.CombatReady and now >= agent.NextAttackAt then
			if SlimeAttackRuntime.Begin(agent, agent.TargetPlayer, targetRoot, now, CombatConfig) then
				return
			end
		else
			withdrawAttackTurn(agent)
		end

		local playerDistance = agent:DistanceTo(targetRoot.Position)
		local slotDistance = agent:DistanceTo(formationGoal)
		-- Pawtopia tutorial rule: if the Player walks into a slime, do not backpedal
		-- just to restore the full staging shell. Hold the achieved position, keep
		-- facing the Player, and let bounded separation resolve peer overlap.
		if playerDistance > Config.SoftStageReleaseDistance then
			rawGoal = formationGoal
			speed = Config.EngageRepositionSpeed
		elseif playerDistance > Config.EngageInnerDistance
			and slotDistance > Config.SoftStageMaxDrift then
			rawGoal = formationGoal
			speed = Config.EngageRepositionSpeed
		else
			rawGoal = agent.Position
			speed = 0
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

local function step(dt)
	local now = time()
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

local function spawnAgents()
	local count = math.min(Config.SpawnCount, #Catalog.Variants, #zone.Points)
	local spawnPositions = zone:GetInsetSpawnPositions(count, 0)
	local authoredLoopCount = 0

	for slot = 1, count do
		local definition = Catalog.Variants[slot]
		local visual, reason = SlimeFactory.Create(definition, slot, runtimeFolder)
		if not visual then
			warn("[Pawlands Slimes] " .. tostring(reason))
			continue
		end
		if visual.Animation and visual.Animation:HasAuthoredLoop() then
			authoredLoopCount += 1
		end

		local spawnPosition = spawnPositions[slot]
		local grounded = zone:GroundPoint(spawnPosition)
		if grounded then
			spawnPosition = grounded
		end
		visual.Model:SetAttribute("RespawnGeneration", 0)
		visual.Model:SetAttribute("RespawnPending", false)
		local agent = SlimeAgent.new(slot, definition, visual, spawnPosition, Config)
		agent:EnterIdle(time(), randomObject)
		agent:Step(agent.Position, 0, agents, zone, 0.001)
		table.insert(agents, agent)
	end
	return authoredLoopCount
end

function SlimeMovementService.Start()
	if running or not Config.Enabled then
		return
	end
	running = true
	runtimeFolder = getOrCreateRuntimeFolder()
	local resolved, reason = SlimeZone.new(Config, runtimeFolder)
	if not resolved then
		running = false
		warn("[Pawlands Slimes] " .. tostring(reason))
		if runtimeFolder then
			runtimeFolder:Destroy()
			runtimeFolder = nil
		end
		return
	end
	zone = resolved
	local authoredLoopCount = spawnAgents()

	local interval = 1 / Config.UpdateRate
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += math.min(dt, Config.MaxStep)
		while accumulator >= interval do
			step(interval)
			accumulator -= interval
		end
	end)
	print(string.format(
		"[Pawlands Slimes] Pawtopia AI + defeat/respawn lifecycle ready with %d slime(s), stable soft-square staging, FIFO tutorial pressure, and %d authored animation loop(s).",
		#agents,
		authoredLoopCount
	))
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
	accumulator = 0
end

return SlimeMovementService
