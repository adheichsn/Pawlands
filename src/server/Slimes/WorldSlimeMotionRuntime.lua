local SlimeAttackRuntime = require(script.Parent.SlimeAttackRuntime)
local SlimeAttackScheduler = require(script.Parent.SlimeAttackScheduler)
local SlimeFormation = require(script.Parent.SlimeFormation)
local SlimeHealth = require(script.Parent.SlimeHealth)
local SlimeNavigation = require(script.Parent.SlimeNavigation)
local SlimeTargeting = require(script.Parent.SlimeTargeting)
local WorldSlimeTargetRuntime = require(script.Parent.WorldSlimeTargetRuntime)

local WorldSlimeMotionRuntime = {}

local function withdrawAttackTurn(agent)
	SlimeAttackScheduler.Withdraw(agent)
end

local function combatConfigFor(context, agent)
	if context.CombatConfigFor then
		return context.CombatConfigFor(agent)
	end
	return context.CombatConfig
end

local function chaseSpeedFor(context, agent, goal)
	local config = context.ConfigFor(agent)
	local distance = agent:DistanceTo(goal)
	local startDistance = config.ChaseCatchupStartDistance
	local fullDistance = math.max(startDistance + 0.01, config.ChaseCatchupFullDistance)
	local alpha = math.clamp((distance - startDistance) / (fullDistance - startDistance), 0, 1)
	return config.ChaseSpeed + (config.ChaseCatchupMaxSpeed - config.ChaseSpeed) * alpha
end

local function resolveStrikeTarget(context, agent, strike)
	local runtimeZone = context.ZoneFor(agent)
	return runtimeZone
		and SlimeTargeting.ResolveStrike(
			strike,
			context.PetCombatService,
			context.PetVitalsService,
			runtimeZone
		)
		or nil
end

local function applyStrikeDamage(context, strike, currentTarget, amount)
	if strike.TargetKind == "Pet" then
		if not context.PetVitalsService or not strike.Player or not strike.PetUid then
			return false
		end
		local applied, vitals = context.PetVitalsService.ApplyDamage(
			strike.Player,
			strike.PetUid,
			amount
		)
		if applied and context.PetCombatFeedbackService then
			context.PetCombatFeedbackService.PublishHit(
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

function WorldSlimeMotionRuntime.GetFormationGoals(context, formationStateByPlayer)
	local groups = {}
	for _, agent in ipairs(context.Agents) do
		if (agent.State == "Chase" or agent.State == "Engage" or agent.State == "Attack")
			and agent.TargetPlayer
			and agent.TargetKind ~= "Pet"
		then
			local runtimeZone = context.ZoneFor(agent)
			if runtimeZone then
				groups[agent.TargetPlayer] = groups[agent.TargetPlayer] or {}
				groups[agent.TargetPlayer][runtimeZone] = groups[agent.TargetPlayer][runtimeZone] or {}
				table.insert(groups[agent.TargetPlayer][runtimeZone], agent)
			end
		end
	end

	local goals = {}
	for player, zoneGroups in pairs(groups) do
		local root = WorldSlimeTargetRuntime.GetRoot(player)
		if root then
			formationStateByPlayer[player] = formationStateByPlayer[player] or {}
			local playerStates = formationStateByPlayer[player]

			for runtimeZone, group in pairs(zoneGroups) do
				local config = context.ConfigFor(group[1])
				local state = playerStates[runtimeZone]
				if not state then
					state = {
						Heading = SlimeFormation.ResolveHeading(root, nil),
						LastCount = 0,
					}
					playerStates[runtimeZone] = state
				else
					state.Heading = SlimeFormation.ResolveHeading(root, state.Heading)
				end

				local slots = SlimeFormation.BuildSlots(root, #group, runtimeZone, config, state.Heading)
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
					local assigned = SlimeFormation.Assign(group, slots, config)
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
	end

	for player, zoneStates in pairs(formationStateByPlayer) do
		local activeZoneGroups = groups[player]
		if not activeZoneGroups then
			formationStateByPlayer[player] = nil
		else
			for runtimeZone in pairs(zoneStates) do
				if not activeZoneGroups[runtimeZone] then
					zoneStates[runtimeZone] = nil
				end
			end
			if next(zoneStates) == nil then
				formationStateByPlayer[player] = nil
			end
		end
	end
	return goals
end

function WorldSlimeMotionRuntime.StepAgent(context, agent, formationGoal, now, dt)
	if not SlimeHealth.IsAlive(agent.Model) then
		agent.Velocity = Vector3.zero
		if agent.Visual.Animation then
			agent.Visual.Animation:SetMoving(false)
		end
		return
	end

	local runtimeZone = context.ZoneFor(agent)
	if not runtimeZone then
		return
	end
	local config = context.ConfigFor(agent)
	local combatConfig = combatConfigFor(context, agent)

	if agent.State == "Attack" then
		SlimeAttackRuntime.Update(
			agent,
			now,
			runtimeZone,
			combatConfig,
			function(strike)
				return resolveStrikeTarget(context, agent, strike)
			end,
			function(strike, currentTarget, amount)
				return applyStrikeDamage(context, strike, currentTarget, amount)
			end
		)
		return
	end

	local rawGoal = agent.Position
	local speed = 0
	local facingGoal = nil
	local targetContext = SlimeTargeting.ResolveCurrent(
		agent,
		context.PetCombatService,
		context.PetVitalsService,
		runtimeZone
	)
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
		rawGoal = targetContext.Kind == "Pet" and targetPosition or (formationGoal or targetPosition)
		speed = chaseSpeedFor(context, agent, rawGoal)
		facingGoal = targetPosition
	elseif agent.State == "Engage" and targetPosition then
		facingGoal = targetPosition
		local facingReady = agent:IsFacing(
			targetPosition,
			combatConfig.AttackFacingToleranceDegrees
		)
		if agent.CombatReady and now >= agent.NextAttackAt and facingReady then
			if SlimeAttackRuntime.Begin(agent, targetContext, now, combatConfig) then
				return
			end
		else
			withdrawAttackTurn(agent)
		end

		if targetContext.Kind == "Pet" then
			rawGoal = agent.Position
			speed = 0
		elseif formationGoal then
			local playerDistance = agent:DistanceTo(targetPosition)
			local slotDistance = agent:DistanceTo(formationGoal)
			if playerDistance > config.SoftStageReleaseDistance then
				rawGoal = formationGoal
				speed = config.EngageRepositionSpeed
			elseif playerDistance > config.EngageInnerDistance
				and slotDistance > config.SoftStageMaxDrift
			then
				rawGoal = formationGoal
				speed = config.EngageRepositionSpeed
			else
				rawGoal = agent.Position
				speed = 0
			end
		end
	elseif agent.State == "Wander" and agent.WanderTarget then
		withdrawAttackTurn(agent)
		rawGoal = agent.WanderTarget
		speed = config.WanderSpeed
	elseif agent.State == "Return" then
		withdrawAttackTurn(agent)
		rawGoal = agent.HomePosition
		speed = config.ReturnSpeed
	else
		withdrawAttackTurn(agent)
	end

	local resolvedGoal = rawGoal
	if speed > 0 then
		resolvedGoal = SlimeNavigation.ResolveGoal(agent, rawGoal, runtimeZone, config, now)
	end
	agent:Step(resolvedGoal, speed, context.Agents, runtimeZone, dt, facingGoal)
end

return WorldSlimeMotionRuntime
