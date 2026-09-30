local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetCombat)

local CombatAttackRuntime = {}

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function phaseOffset(petSlot)
	return math.max(0, petSlot - 1) * Config.AttackStaggerSeconds
end

local function resetForTarget(state, targetToken, clock, petSlot)
	state.TargetToken = targetToken
	state.Ready = false
	state.NextAttackAt = clock + Config.AttackInitialDelaySeconds + phaseOffset(petSlot)
end

local function beginAttack(state, visualPosition, targetPosition, targetToken, clock)
	local direction = horizontal(targetPosition - visualPosition)
	if direction.Magnitude <= 0.001 then
		return false
	end
	state.AttackStartedAt = clock
	state.AttackDirection = direction.Unit
	state.AttackTargetToken = targetToken
	state.ImpactSent = false
	return true
end

local function activeOffset(state, clock, flying)
	local startedAt = state.AttackStartedAt
	local direction = state.AttackDirection
	if not startedAt or not direction then
		return Vector3.zero, false, 0
	end

	local duration = math.max(Config.AttackDurationSeconds, 0.01)
	local progress = (clock - startedAt) / duration
	if progress >= 1 then
		state.AttackStartedAt = nil
		state.AttackDirection = nil
		state.AttackTargetToken = nil
		state.ImpactSent = false
		return Vector3.zero, false, 1
	end

	local clampedProgress = math.clamp(progress, 0, 1)
	local wave = math.sin(clampedProgress * math.pi)
	local hop = flying and Config.FlyingAttackHopStuds or Config.GroundAttackHopStuds
	return direction * (wave * Config.AttackLungeStuds) + Vector3.new(0, wave * hop, 0), true, clampedProgress
end

function CombatAttackRuntime.step(states, petSlot, visual, targetToken, targetPosition, combatGoal, clock)
	local state = states[petSlot]
	if not state then
		state = {}
		states[petSlot] = state
	end

	local flying = visual.Definition.Movement == "Flying"
	local active, isActive, progress = activeOffset(state, clock, flying)
	local impact = false

	if isActive
		and not state.ImpactSent
		and state.AttackTargetToken == targetToken
		and progress >= Config.AttackImpactAlpha
	then
		state.ImpactSent = true
		impact = true
	end

	if targetToken ~= state.TargetToken then
		resetForTarget(state, targetToken, clock, petSlot)
	end

	if not targetToken or not targetPosition or not combatGoal or not visual.Position then
		state.Ready = false
		if not isActive then
			state.NextAttackAt = nil
		end
		return active, impact
	end

	local arrivalDelta = horizontal(visual.Position - combatGoal)
	local arrived = arrivalDelta.Magnitude <= Config.AttackReadyRadiusStuds
	if not arrived then
		state.Ready = false
		if not isActive then
			state.NextAttackAt = clock + Config.AttackInitialDelaySeconds + phaseOffset(petSlot)
		end
		return active, impact
	end

	if not state.Ready then
		state.Ready = true
		if not state.NextAttackAt or state.NextAttackAt < clock then
			state.NextAttackAt = clock + Config.AttackInitialDelaySeconds + phaseOffset(petSlot)
		end
	end

	if not isActive and state.NextAttackAt and clock >= state.NextAttackAt then
		if beginAttack(state, visual.Position, targetPosition, targetToken, clock) then
			state.NextAttackAt = clock + Config.AttackCadenceSeconds
			active, isActive, progress = activeOffset(state, clock, flying)
		end
	end

	return active, impact
end

function CombatAttackRuntime.trim(states, partyCount)
	for petSlot in pairs(states) do
		if petSlot > partyCount then
			states[petSlot] = nil
		end
	end
end

return CombatAttackRuntime
