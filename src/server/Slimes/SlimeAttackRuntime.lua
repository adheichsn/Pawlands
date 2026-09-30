local RunService = game:GetService("RunService")

local SlimeAttackScheduler = require(script.Parent.SlimeAttackScheduler)

local SlimeAttackRuntime = {}

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalDistance(a, b)
	return horizontal(a - b).Magnitude
end

function SlimeAttackRuntime.Begin(agent, target, now, config)
	if agent.Strike or not target or not target.Key or typeof(target.Position) ~= "Vector3" then
		return false
	end
	if not SlimeAttackScheduler.TryClaim(agent, target.Key, now, config) then
		return false
	end

	local origin = agent.Position
	local targetPosition = target.Position
	local direction = horizontal(targetPosition - origin)
	if direction.Magnitude <= 0.001 then
		direction = agent.Facing
	else
		direction = direction.Unit
	end

	local lungeStartedAt = now + config.AttackWindupSeconds
	agent.Strike = {
		TargetKind = target.Kind,
		TargetKey = target.Key,
		Player = target.Player,
		PetSlot = target.PetSlot,
		PetUid = target.PetUid,
		ExpectedCharacter = target.Character,
		Origin = origin,
		Direction = direction,
		TargetPosition = targetPosition,
		LungeStartedAt = lungeStartedAt,
		ImpactAt = lungeStartedAt + config.AttackImpactSeconds,
		EndAt = lungeStartedAt + config.AttackStrikeSeconds,
		ImpactApplied = false,
	}
	agent:SetState("Attack", target.Player)
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
	SlimeAttackScheduler.Release(agent, strike.TargetKey, now or time(), false, config, strike.TargetKind)
	agent:RestoreGroundPose(strike.TargetPosition)
	if agent.Visual.Animation then
		agent.Visual.Animation:SetMoving(false)
	end
end

function SlimeAttackRuntime.Update(agent, now, zone, config, resolveTarget, applyDamage)
	local strike = agent.Strike
	if not strike then
		return false
	end

	local currentTarget = resolveTarget and resolveTarget(strike) or nil
	if not currentTarget or currentTarget.Key ~= strike.TargetKey or typeof(currentTarget.Position) ~= "Vector3" then
		SlimeAttackRuntime.Cancel(agent, now, config)
		return false
	end
	if strike.TargetKind == "Player" and currentTarget.Character ~= strike.ExpectedCharacter then
		SlimeAttackRuntime.Cancel(agent, now, config)
		return false
	end

	-- Target position/direction are locked when wind-up begins. This keeps both
	-- Player and pet strikes readable and prevents homing after commitment.
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
		local dodgeDistance = horizontalDistance(currentTarget.Position, strike.TargetPosition)
		local currentDistance = horizontalDistance(resolved, currentTarget.Position)
		local clearRoute = zone:HasClearRoute(resolved, currentTarget.Position, currentDistance + 0.1)
		if dodgeDistance <= config.AttackDodgeToleranceStuds
			and currentDistance <= config.AttackMaxImpactDistanceStuds
			and clearRoute
		then
			local applied = applyDamage and applyDamage(strike, currentTarget, config.AttackDamage) or false
			if applied and RunService:IsStudio() then
				local targetName = strike.TargetKind == "Pet"
					and string.format("pet %s", tostring(strike.PetUid))
					or strike.Player.Name
				print(string.format(
					"[Pawlands Slimes] %s hit %s for %d damage.",
					tostring(agent.Model:GetAttribute("SlimeId") or agent.Model.Name),
					targetName,
					config.AttackDamage
				))
			end
		end
	end

	if now >= strike.EndAt then
		agent.Strike = nil
		SlimeAttackScheduler.Release(agent, strike.TargetKey, now, true, config, strike.TargetKind)
		agent.NextAttackAt = now + config.AttackIntervalSeconds
		agent:SetState("Engage", strike.Player)
		agent:SetCombatReady(true)
		agent:RestoreGroundPose(strike.TargetPosition)
		if agent.Visual.Animation then
			agent.Visual.Animation:SetMoving(false)
		end
		return false
	end
	return true
end

return SlimeAttackRuntime
