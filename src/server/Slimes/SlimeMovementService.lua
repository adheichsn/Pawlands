local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Catalog = require(Shared.Config.SlimeCatalog)
local Config = require(Shared.Config.SlimeMovement)

local SlimeAgent = require(script.Parent.SlimeAgent)
local SlimeFactory = require(script.Parent.SlimeFactory)
local SlimeFormation = require(script.Parent.SlimeFormation)
local SlimeNavigation = require(script.Parent.SlimeNavigation)
local SlimeZone = require(script.Parent.SlimeZone)
local SlimeHealth = require(script.Parent.SlimeHealth)

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

local function horizontalDistance(a, b)
	local delta = a - b
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
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

local function updateStates(now)
	for _, agent in ipairs(agents) do
		if not SlimeHealth.IsAlive(agent.Model) then
			agent:SetState("Defeated", nil)
			agent:SetCombatReady(false)
			continue
		end
		local target = chooseTarget(agent)
		if target then
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
				agent:SetState("Chase", target)
				agent:SetCombatReady(false)
			end
		elseif agent.State == "Chase" or agent.State == "Engage" then
			if agent:DistanceTo(agent.HomePosition) > Config.ReturnHomeDistance then
				agent:EnterReturn()
			else
				agent:EnterIdle(now, randomObject)
			end
		elseif agent.State == "Idle" then
			if now >= agent.IdleUntil then
				agent:EnterWander(chooseWanderTarget(agent))
			end
		elseif agent.State == "Wander" then
			if not agent.WanderTarget or agent:DistanceTo(agent.WanderTarget) <= Config.ArrivalRadius then
				agent:EnterIdle(now, randomObject)
			end
		elseif agent.State == "Return" then
			if agent:DistanceTo(agent.HomePosition) <= Config.ArrivalRadius then
				agent:EnterIdle(now, randomObject)
			end
		else
			agent:EnterIdle(now, randomObject)
		end
	end
end

local function getFormationGoals(now, dt)
	local groups = {}
	for _, agent in ipairs(agents) do
		if (agent.State == "Chase" or agent.State == "Engage") and agent.TargetPlayer then
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
				state = { NextAssignAt = 0, Heading = nil }
				formationStateByPlayer[player] = state
			end
			state.Heading = SlimeFormation.ResolveHeading(root, state.Heading, dt, Config)
			local slots = SlimeFormation.BuildSlots(root, #group, zone, Config, state.Heading)

			local missingSlot = false
			for _, agent in ipairs(group) do
				if not agent.FormationSlot or not slots[agent.FormationSlot] then
					missingSlot = true
					break
				end
			end

			if missingSlot or now >= state.NextAssignAt then
				local assigned = SlimeFormation.Assign(group, slots, Config)
				for agent, goal in pairs(assigned) do
					goals[agent] = goal
				end
				state.NextAssignAt = now + Config.FormationReassignSeconds
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

	local rawGoal = agent.Position
	local speed = 0
	local targetRoot = agent.TargetPlayer and getRoot(agent.TargetPlayer) or nil

	if agent.State == "Chase" and formationGoal then
		rawGoal = formationGoal
		speed = chaseSpeedFor(agent, rawGoal)
	elseif agent.State == "Engage" and formationGoal and targetRoot then
		local playerDistance = agent:DistanceTo(targetRoot.Position)
		local slotDistance = agent:DistanceTo(formationGoal)
		if playerDistance < Config.EngageInnerDistance or slotDistance > Config.FormationSlotTolerance then
			rawGoal = formationGoal
			speed = Config.EngageRepositionSpeed
		else
			agent:FaceToward(targetRoot.Position, dt)
		end
	elseif agent.State == "Wander" and agent.WanderTarget then
		rawGoal = agent.WanderTarget
		speed = Config.WanderSpeed
	elseif agent.State == "Return" then
		rawGoal = agent.HomePosition
		speed = Config.ReturnSpeed
	end

	local resolvedGoal = rawGoal
	if speed > 0 then
		resolvedGoal = SlimeNavigation.ResolveGoal(agent, rawGoal, zone, Config, now)
	end
	agent:Step(resolvedGoal, speed, agents, zone, dt)
end

local function step(dt)
	local now = time()
	if now >= filterRefreshAt then
		filterRefreshAt = now + 1
		zone:RefreshGroundFilter()
	end

	updateStates(now)
	local formationGoals = getFormationGoals(now, dt)
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
		"[Pawlands Slimes] Crowd navigation ready with %d slime(s), square engage formation, obstacle avoidance, and %d authored animation loop(s).",
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
		agent:Destroy()
		SlimeFactory.Destroy(agent.Visual)
	end
	table.clear(agents)
	table.clear(formationStateByPlayer)
	if runtimeFolder then
		runtimeFolder:Destroy()
	end
	runtimeFolder, zone = nil, nil
	accumulator = 0
end

return SlimeMovementService
