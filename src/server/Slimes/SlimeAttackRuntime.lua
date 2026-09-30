local RunService = game:GetService("RunService")

local SlimeAttackScheduler = require(script.Parent.SlimeAttackScheduler)

local SlimeAttackRuntime = {}

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalDistance(a, b)
	return horizontal(a - b).Magnitude
end

local function targetHumanoid(player)
	local character = player and player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil, nil
	end
	return humanoid, root, character
end

function SlimeAttackRuntime.Begin(agent, player, root, now, config)
	if agent.Strike or not player or not root then
		return false
	end
	if not SlimeAttackScheduler.TryClaim(agent, player, now, config) then
		return false
	end

	local origin = agent.Position
	local targetPosition = root.Position
	local direction = horizontal(targetPosition - origin)
	if direction.Magnitude <= 0.001 then
		direction = agent.Facing
	else
		direction = direction.Unit
	end

	local lungeStartedAt = now + config.AttackWindupSeconds
	agent.Strike = {
		Player = player,
		ExpectedCharacter = player.Character,
		Origin = origin,
		Direction = direction,
		TargetPosition = targetPosition,
		LungeStartedAt = lungeStartedAt,
		ImpactAt = lungeStartedAt + config.AttackImpactSeconds,
		EndAt = lungeStartedAt + config.AttackStrikeSeconds,
		ImpactApplied = false,
	}
	agent:SetState("Attack", player)
	agent:SetCombatReady(true)
	if agent.Visual.Animation then
		agent.Visual.Animation:SetMoving(true)
	end
	return true
end

function SlimeAttackRuntime.Cancel(agent, now, config)
	local strike = agent.Strike
	if not strike then
		SlimeAttackScheduler.Withdraw(agent)
		return
	end
	agent.Strike = nil
	SlimeAttackScheduler.Release(agent, strike.Player, now or time(), false, config)
	agent:RestoreGroundPose(strike.TargetPosition)
	if agent.Visual.Animation then
		agent.Visual.Animation:SetMoving(false)
	end
end

function SlimeAttackRuntime.Update(agent, now, zone, config)
	local strike = agent.Strike
	if not strike then
		return false
	end

	local humanoid, root, character = targetHumanoid(strike.Player)
	if not humanoid
		or not root
		or character ~= strike.ExpectedCharacter
		or not zone:Contains(root.Position) then
		SlimeAttackRuntime.Cancel(agent, now, config)
		return false
	end

	-- The strike target is locked at wind-up. Facing and lunge direction do not
	-- home after the Player moves, matching Pawtopia's readable dodge behavior.
	if now < strike.LungeStartedAt then
		agent:SetAttackPose(strike.Origin, 0, strike.TargetPosition)
		return true
	end

	local duration = math.max(0.01, strike.EndAt - strike.LungeStartedAt)
	local alpha = math.clamp((now - strike.LungeStartedAt) / duration, 0, 1)
	local pulse = math.sin(alpha * math.pi)
	local desired = strike.Origin + strike.Direction * (pulse * config.AttackLungeDistance)
	local resolved = zone:ResolveMotion(strike.Origin, zone:ClampXZ(desired))
	local hop = pulse * config.AttackHopHeight
	agent:SetAttackPose(resolved, hop, strike.TargetPosition)

	if not strike.ImpactApplied and now >= strike.ImpactAt then
		strike.ImpactApplied = true
		local dodgeDistance = horizontalDistance(root.Position, strike.TargetPosition)
		local currentDistance = horizontalDistance(resolved, root.Position)
		local clearRoute = zone:HasClearRoute(resolved, root.Position, currentDistance + 0.1)
		if dodgeDistance <= config.AttackDodgeToleranceStuds
			and currentDistance <= config.AttackMaxImpactDistanceStuds
			and clearRoute then
			local healthBefore = humanoid.Health
			humanoid:TakeDamage(config.AttackDamage)
			if character.Parent and humanoid.Health < healthBefore - 0.01 then
				character:SetAttribute(
					"SlimeHitSerial",
					(character:GetAttribute("SlimeHitSerial") or 0) + 1
				)
			end
			if RunService:IsStudio() then
				print(string.format(
					"[Pawlands Slimes] %s hit %s for %d damage.",
					tostring(agent.Model:GetAttribute("SlimeId") or agent.Model.Name),
					strike.Player.Name,
					config.AttackDamage
				))
			end
		end
	end

	if now >= strike.EndAt then
		agent.Strike = nil
		SlimeAttackScheduler.Release(agent, strike.Player, now, true, config)
		agent.NextAttackAt = now + config.AttackIntervalSeconds
		agent:SetState("Engage", strike.Player)
		agent:SetCombatReady(true)
		-- Return to the exact strike origin and preserve the locked strike facing.
		agent:RestoreGroundPose(strike.TargetPosition)
		if agent.Visual.Animation then
			agent.Visual.Animation:SetMoving(false)
		end
		return false
	end
	return true
end

return SlimeAttackRuntime
