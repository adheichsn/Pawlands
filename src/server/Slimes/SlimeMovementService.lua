local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Catalog = require(Shared.Config.SlimeCatalog)
local Config = require(Shared.Config.SlimeMovement)

local SlimeAgent = require(script.Parent.SlimeAgent)
local SlimeFactory = require(script.Parent.SlimeFactory)
local SlimeZone = require(script.Parent.SlimeZone)

local SlimeMovementService = {}

local running = false
local heartbeatConnection = nil
local agents = {}
local zone = nil
local runtimeFolder = nil
local randomObject = Random.new()
local filterRefreshAt = 0
local accumulator = 0

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

local function chooseWanderPoint(agent, reserved)
	local candidates = {}
	for _, point in ipairs(zone.Points) do
		if not reserved[point] and point ~= agent.HomePoint then
			table.insert(candidates, point)
		end
	end
	if #candidates == 0 then
		for _, point in ipairs(zone.Points) do
			if not reserved[point] then
				table.insert(candidates, point)
			end
		end
	end
	if #candidates == 0 then
		return agent.HomePoint
	end

	-- Prefer a point that actually moves the slime, while randomizing among the
	-- farther half so every idle cycle does not repeat the same route.
	table.sort(candidates, function(a, b)
		return agent:DistanceTo(a.WorldPosition) > agent:DistanceTo(b.WorldPosition)
	end)
	local range = math.max(1, math.ceil(#candidates * 0.5))
	return candidates[randomObject:NextInteger(1, range)]
end

local function updateStates(now)
	local reserved = {}
	for _, agent in ipairs(agents) do
		if agent.WanderPoint then
			reserved[agent.WanderPoint] = true
		end
	end

	for _, agent in ipairs(agents) do
		local target = chooseTarget(agent)
		if target then
			local previousPoint = agent.WanderPoint
			if previousPoint then
				reserved[previousPoint] = nil
			end
			agent:SetState("Chase", target)
		elseif agent.State == "Chase" then
			agent:EnterIdle(now, randomObject)
		elseif agent.State == "Idle" then
			if now >= agent.IdleUntil then
				local point = chooseWanderPoint(agent, reserved)
				reserved[point] = true
				agent:EnterWander(point)
			end
		elseif agent.State == "Wander" then
			if not agent.WanderPoint or agent:DistanceTo(agent.WanderPoint.WorldPosition) <= Config.ArrivalRadius then
				if agent.WanderPoint then
					reserved[agent.WanderPoint] = nil
				end
				agent:EnterIdle(now, randomObject)
			end
		else
			agent:EnterIdle(now, randomObject)
		end
	end
end

local function getChaseGoals()
	local groups = {}
	for _, agent in ipairs(agents) do
		if agent.State == "Chase" and agent.TargetPlayer then
			groups[agent.TargetPlayer] = groups[agent.TargetPlayer] or {}
			table.insert(groups[agent.TargetPlayer], agent)
		end
	end

	local goals = {}
	for player, group in pairs(groups) do
		local root = getRoot(player)
		if root then
			table.sort(group, function(a, b)
				return a.Slot < b.Slot
			end)
			local count = #group
			local radius = Config.ChaseRingRadius + math.max(0, count - 1) * Config.ChaseRingSpacingBoost
			local phase = (player.UserId % 37) / 37 * math.pi * 2
			for index, agent in ipairs(group) do
				local angle = phase + ((index - 1) / count) * math.pi * 2
				local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				goals[agent] = zone:ClampXZ(root.Position + offset)
			end
		end
	end
	return goals
end

local function step(dt)
	local now = time()
	if now >= filterRefreshAt then
		filterRefreshAt = now + 1
		zone:RefreshGroundFilter()
	end

	updateStates(now)
	local chaseGoals = getChaseGoals()
	for _, agent in ipairs(agents) do
		local goal, speed
		if agent.State == "Chase" and chaseGoals[agent] then
			goal, speed = chaseGoals[agent], Config.ChaseSpeed
		elseif agent.State == "Wander" and agent.WanderPoint then
			goal, speed = agent.WanderPoint.WorldPosition, Config.WanderSpeed
		else
			goal, speed = agent.Position, 0
		end
		agent:Step(goal, speed, agents, zone, dt)
	end
end

local function spawnAgents()
	local count = math.min(Config.SpawnCount, #Catalog.Variants, #zone.Points)
	local spawnPoints = zone:GetSpreadSpawnPoints(count)
	for slot = 1, count do
		local definition = Catalog.Variants[slot]
		local visual, reason = SlimeFactory.Create(definition, slot, runtimeFolder)
		if not visual then
			warn("[Pawlands Slimes] " .. tostring(reason))
			continue
		end
		if visual.AnimationReason then
			warn("[Pawlands Slimes] Idle animation unavailable for " .. definition.Id .. ": " .. visual.AnimationReason)
		end

		local point = spawnPoints[slot]
		local groundY = zone:GroundAt(point.WorldPosition)
		local agent = SlimeAgent.new(slot, definition, visual, point, Config)
		if groundY then
			agent.Position = Vector3.new(point.WorldPosition.X, groundY, point.WorldPosition.Z)
		end
		agent:EnterIdle(time(), randomObject)
		agent:Step(agent.Position, 0, agents, zone, 0.001)
		table.insert(agents, agent)
	end
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
	spawnAgents()

	local interval = 1 / Config.UpdateRate
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += math.min(dt, Config.MaxStep)
		while accumulator >= interval do
			step(interval)
			accumulator -= interval
		end
	end)
	print(string.format("[Pawlands Slimes] Crowd movement ready with %d slime(s) and %d zone point(s).", #agents, #zone.Points))
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
	if runtimeFolder then
		runtimeFolder:Destroy()
	end
	runtimeFolder, zone = nil, nil
	accumulator = 0
end

return SlimeMovementService
