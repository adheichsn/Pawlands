local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetCombat)
local WorldConfig = require(Shared.Config.WorldPetCombat)

local CombatTransitionRuntime = {}

local function horizontalDistance(a, b)
	local delta = Vector3.new(a.X - b.X, 0, a.Z - b.Z)
	return delta.Magnitude
end

local function stagger(slot)
	return math.max(0, slot - 1) * Config.TransitionStaggerSeconds
end

local function getState(states, slot)
	local state = states[slot]
	if state then
		return state
	end
	state = {
		TargetToken = nil,
		HadCombat = false,
		HoldUntil = 0,
		Mode = "Follow",
		TargetWasWorld = false,
		ReturningFromWorld = false,
	}
	states[slot] = state
	return state
end

local function isWorldTarget(targetToken)
	return targetToken and targetToken:GetAttribute("WorldCombat") == true
end

local function worldReturnProfile(distance)
	local maxSpeed = WorldConfig.ReturnNearMaxSpeedStuds
	if distance >= WorldConfig.ReturnFarDistanceStuds then
		maxSpeed = WorldConfig.ReturnVeryFarMaxSpeedStuds
	elseif distance >= WorldConfig.ReturnMediumDistanceStuds then
		maxSpeed = WorldConfig.ReturnFarMaxSpeedStuds
	elseif distance >= WorldConfig.ReturnNearDistanceStuds then
		maxSpeed = WorldConfig.ReturnMediumMaxSpeedStuds
	end
	return {
		FollowSpeed = WorldConfig.ReturnFollowSpeed,
		MaxHorizontalSpeed = maxSpeed,
		MaxHorizontalAcceleration = WorldConfig.ReturnAccelerationStudsPerSecond2,
		TurnSpeedDegreesPerSecond = WorldConfig.ReturnTurnSpeedDegreesPerSecond,
		NaturalReturn = true,
		EmergencyRecallDistance = WorldConfig.EmergencyRecallDistanceStuds,
		StuckRecallSeconds = WorldConfig.StuckRecallSeconds,
	}
end

function CombatTransitionRuntime.step(states, slot, visualPosition, targetToken, combatGoal, followGoal, clock)
	local state = getState(states, slot)
	local previousTarget = state.TargetToken
	if targetToken ~= previousTarget then
		local previousWasWorld = state.TargetWasWorld == true
		state.TargetToken = targetToken
		state.TargetWasWorld = isWorldTarget(targetToken)
		if previousTarget ~= nil then
			state.HadCombat = true
			state.ReturningFromWorld = targetToken == nil and previousWasWorld
			state.Mode = targetToken ~= nil and "Retarget" or "Return"
			local recover
			if targetToken ~= nil then
				recover = Config.RetargetRecoverSeconds
			elseif previousWasWorld then
				recover = WorldConfig.ReturnRecoverSeconds
			else
				recover = Config.ReturnRecoverSeconds
			end
			state.HoldUntil = math.max(state.HoldUntil or 0, clock + recover + stagger(slot))
		elseif targetToken ~= nil then
			state.HadCombat = true
			state.ReturningFromWorld = false
			state.Mode = (state.HoldUntil or 0) > clock and "Retarget" or "Combat"
		end
	end

	if state.HadCombat and (state.HoldUntil or 0) > clock and visualPosition then
		return visualPosition, {
			FollowSpeed = Config.ReturnFollowSpeed,
			MaxHorizontalSpeed = 0,
			TurnSpeedDegreesPerSecond = Config.ReturnTurnSpeedDegreesPerSecond,
		}, true, state.Mode
	end

	if targetToken ~= nil and combatGoal then
		local movementMode = state.Mode == "Retarget" and "Retarget" or "Combat"
		local maxSpeed = movementMode == "Retarget"
			and Config.RetargetMaxSpeedStuds
			or Config.CombatApproachMaxSpeedStuds
		local turnSpeed = movementMode == "Retarget"
			and Config.RetargetTurnSpeedDegreesPerSecond
			or Config.CombatTurnSpeedDegreesPerSecond
		state.Mode = "Combat"
		local acceleration = movementMode == "Retarget"
			and Config.RetargetAccelerationStudsPerSecond2
			or Config.CombatApproachAccelerationStudsPerSecond2
		return combatGoal, {
			FollowSpeed = Config.CombatApproachFollowSpeed,
			MaxHorizontalSpeed = maxSpeed,
			MaxHorizontalAcceleration = acceleration,
			TurnSpeedDegreesPerSecond = turnSpeed,
		}, false, movementMode
	end

	if state.HadCombat then
		state.Mode = "Return"
		local returnDistance = visualPosition and followGoal
			and horizontalDistance(visualPosition, followGoal)
			or 0
		local settleRadius = state.ReturningFromWorld
			and WorldConfig.ReturnSettleRadiusStuds
			or Config.TransitionSettleRadiusStuds
		if visualPosition and followGoal and returnDistance <= settleRadius then
			state.HadCombat = false
			state.ReturningFromWorld = false
			state.Mode = "Follow"
			state.HoldUntil = 0
			return followGoal, nil, false, "Follow"
		end
		if state.ReturningFromWorld then
			return followGoal, worldReturnProfile(returnDistance), false, "Return"
		end
		return followGoal, {
			FollowSpeed = Config.ReturnFollowSpeed,
			MaxHorizontalSpeed = Config.ReturnMaxSpeedStuds,
			MaxHorizontalAcceleration = Config.ReturnAccelerationStudsPerSecond2,
			TurnSpeedDegreesPerSecond = Config.ReturnTurnSpeedDegreesPerSecond,
		}, false, "Return"
	end

	return followGoal, nil, false, "Follow"
end

function CombatTransitionRuntime.trim(states, partyCount)
	for slot in pairs(states) do
		if slot > partyCount then
			states[slot] = nil
		end
	end
end

return CombatTransitionRuntime
