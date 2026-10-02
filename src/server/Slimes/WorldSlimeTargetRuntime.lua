local Players = game:GetService("Players")

local SlimeAttackRuntime = require(script.Parent.SlimeAttackRuntime)
local SlimeAttackScheduler = require(script.Parent.SlimeAttackScheduler)
local SlimeHealth = require(script.Parent.SlimeHealth)
local SlimeNavigation = require(script.Parent.SlimeNavigation)
local SlimeTargeting = require(script.Parent.SlimeTargeting)

local WorldSlimeTargetRuntime = {}

local function withdrawAttackTurn(agent)
	SlimeAttackScheduler.Withdraw(agent)
end

function WorldSlimeTargetRuntime.GetRoot(player)
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

local function isTargetValid(context, agent, player, disengage)
	local runtimeZone = context.ZoneFor(agent)
	if not runtimeZone then
		return false, nil
	end
	local root = WorldSlimeTargetRuntime.GetRoot(player)
	if not root or not runtimeZone:Contains(root.Position) then
		return false, nil
	end
	local config = context.ConfigFor(agent)
	local maximum = disengage and config.DisengageRange or config.AggroRange
	return agent:DistanceTo(root.Position) <= maximum, root
end

local function chooseOwnerPlayer(context, agent)
	if agent.TargetPlayer then
		local valid = isTargetValid(context, agent, agent.TargetPlayer, true)
		if valid then
			return agent.TargetPlayer
		end
	end

	local bestPlayer, bestDistance = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local valid, root = isTargetValid(context, agent, player, false)
		if valid and root then
			local distance = agent:DistanceTo(root.Position)
			if distance < bestDistance then
				bestPlayer, bestDistance = player, distance
			end
		end
	end
	return bestPlayer
end

local function chooseWanderTarget(context, agent)
	local config = context.ConfigFor(agent)
	local runtimeZone = context.ZoneFor(agent)
	local angle = context.Random:NextNumber(0, math.pi * 2)
	local scale = config.WanderMinRadiusScale
		+ context.Random:NextNumber(0, 1) * (1 - config.WanderMinRadiusScale)
	local radius = config.WanderRadius * scale
	local target = agent.HomePosition + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	return runtimeZone:ClampXZ(target)
end

local function disengage(context, agent, now)
	withdrawAttackTurn(agent)
	SlimeAttackRuntime.Cancel(agent, now, context.CombatConfig)
	SlimeTargeting.Clear(agent)
	local config = context.ConfigFor(agent)
	if agent:DistanceTo(agent.HomePosition) > config.ReturnHomeDistance then
		agent:EnterReturn()
	else
		agent:EnterIdle(now, context.Random)
	end
end

local function buildPetPressure(context)
	local pressure = {}
	for _, agent in ipairs(context.Agents) do
		if agent.TargetKind == "Pet" and agent.TargetKey then
			local runtimeZone = context.ZoneFor(agent)
			local target = runtimeZone
				and SlimeTargeting.ResolveCurrent(
					agent,
					context.PetCombatService,
					context.PetVitalsService,
					runtimeZone
				)
				or nil
			if target then
				SlimeTargeting.AddPressure(pressure, target)
			end
		end
	end
	return pressure
end

local function assignFocus(context, agent, player, now, pressure)
	local runtimeZone = context.ZoneFor(agent)
	if not runtimeZone then
		return nil
	end
	local target = SlimeTargeting.Select(
		agent,
		player,
		context.PetCombatService,
		context.PetVitalsService,
		runtimeZone,
		context.CombatConfig,
		pressure,
		context.Random
	)
	if not target then
		return nil
	end

	local changed = SlimeTargeting.Assign(agent, target, now, context.CombatConfig, context.Random)
	if changed then
		withdrawAttackTurn(agent)
		agent.FormationSlot = nil
		SlimeNavigation.Reset(agent)
	end
	if target.Kind == "Player" then
		agent.NextTargetReviewAt = now
			+ math.max(0.1, tonumber(context.CombatConfig.TargetReviewIntervalSeconds) or 0.45)
	end
	SlimeTargeting.AddPressure(pressure, target)
	return target
end

local function currentOrReviewedFocus(context, agent, player, now, pressure)
	local runtimeZone = context.ZoneFor(agent)
	local target = runtimeZone
		and SlimeTargeting.ResolveCurrent(
			agent,
			context.PetCombatService,
			context.PetVitalsService,
			runtimeZone
		)
		or nil
	if not target then
		return assignFocus(context, agent, player, now, pressure)
	end

	if target.Kind == "Player" and now >= (agent.NextTargetReviewAt or 0) then
		local reviewed = assignFocus(context, agent, player, now, pressure)
		return reviewed or target
	end

	if target.Kind == "Pet" and now >= (agent.NextTargetReviewAt or 0) then
		local takeover = runtimeZone
			and SlimeTargeting.TryPlayerTakeover(agent, runtimeZone, context.CombatConfig, now)
			or nil
		if takeover then
			pressure[target.Key] = math.max(0, (pressure[target.Key] or 0) - 1)
			local changed = SlimeTargeting.Assign(
				agent,
				takeover,
				now,
				context.CombatConfig,
				context.Random
			)
			if changed then
				withdrawAttackTurn(agent)
				agent.FormationSlot = nil
				SlimeNavigation.Reset(agent)
			end
			return takeover
		end
	end
	return target
end

local function targetReady(context, agent, target)
	if not target or typeof(target.Position) ~= "Vector3" then
		return false
	end
	local runtimeZone = context.ZoneFor(agent)
	if not runtimeZone then
		return false
	end
	local config = context.ConfigFor(agent)
	local distance = agent:DistanceTo(target.Position)
	return distance <= config.EngageReadyDistance
		and SlimeNavigation.HasLineOfSight(agent, target.Position, runtimeZone)
end

function WorldSlimeTargetRuntime.UpdateStates(context, now)
	local pressure = buildPetPressure(context)
	for _, agent in ipairs(context.Agents) do
		if not SlimeHealth.IsAlive(agent.Model) then
			withdrawAttackTurn(agent)
			SlimeAttackRuntime.Cancel(agent, now, context.CombatConfig)
			SlimeTargeting.Clear(agent)
			agent:SetState("Defeated", nil)
			agent:SetCombatReady(false)
			continue
		end

		if agent.State == "Attack" then
			local ownerValid = agent.TargetPlayer
				and isTargetValid(context, agent, agent.TargetPlayer, true)
			local runtimeZone = context.ZoneFor(agent)
			local target = runtimeZone
				and SlimeTargeting.ResolveCurrent(
					agent,
					context.PetCombatService,
					context.PetVitalsService,
					runtimeZone
				)
				or nil
			if not ownerValid then
				disengage(context, agent, now)
			elseif not target then
				SlimeAttackRuntime.Cancel(agent, now, context.CombatConfig)
				local replacement = assignFocus(
					context,
					agent,
					agent.TargetPlayer,
					now,
					pressure
				)
				if replacement then
					if targetReady(context, agent, replacement) then
						agent:SetState("Engage", agent.TargetPlayer)
						agent:SetCombatReady(true)
					else
						agent:SetState("Chase", agent.TargetPlayer)
						agent:SetCombatReady(false)
					end
				else
					disengage(context, agent, now)
				end
			end
			continue
		end

		local owner = chooseOwnerPlayer(context, agent)
		if owner then
			local ownerChanged = owner ~= agent.TargetPlayer
			if ownerChanged
				or agent.State == "Idle"
				or agent.State == "Wander"
				or agent.State == "Return"
			then
				withdrawAttackTurn(agent)
				SlimeTargeting.Clear(agent)
				agent:EnterNotice(owner, now, context.CombatConfig)
				continue
			end

			if agent.State == "Notice" then
				withdrawAttackTurn(agent)
				if now >= agent.NoticeUntil then
					local target = assignFocus(context, agent, owner, now, pressure)
					if target and targetReady(context, agent, target) then
						agent:SetState("Engage", owner)
						agent:SetCombatReady(true)
					else
						agent:SetState("Chase", owner)
						agent:SetCombatReady(false)
					end
				end
				continue
			end

			local target = currentOrReviewedFocus(context, agent, owner, now, pressure)
			if not target then
				disengage(context, agent, now)
				continue
			end
			if targetReady(context, agent, target) then
				agent:SetState("Engage", owner)
				agent:SetCombatReady(true)
			else
				withdrawAttackTurn(agent)
				agent:SetState("Chase", owner)
				agent:SetCombatReady(false)
			end
		elseif agent.State == "Notice" or agent.State == "Chase" or agent.State == "Engage" then
			disengage(context, agent, now)
		elseif agent.State == "Idle" then
			withdrawAttackTurn(agent)
			if now >= agent.IdleUntil then
				agent:EnterWander(chooseWanderTarget(context, agent))
			end
		elseif agent.State == "Wander" then
			withdrawAttackTurn(agent)
			if not agent.WanderTarget
				or agent:DistanceTo(agent.WanderTarget) <= context.ConfigFor(agent).ArrivalRadius
			then
				agent:EnterIdle(now, context.Random)
			end
		elseif agent.State == "Return" then
			withdrawAttackTurn(agent)
			if agent:DistanceTo(agent.HomePosition) <= context.ConfigFor(agent).ArrivalRadius then
				agent:EnterIdle(now, context.Random)
			end
		else
			withdrawAttackTurn(agent)
			agent:EnterIdle(now, context.Random)
		end
	end
end

return WorldSlimeTargetRuntime
