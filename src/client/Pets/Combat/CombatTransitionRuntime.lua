local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetCombat)

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
	}
	states[slot] = state
	return state
end

function CombatTransitionRuntime.step(states, slot, visualPosition, targetToken, combatGoal, followGoal, clock)
	local state = getState(states, slot)
	local previousTarget = state.TargetToken
	if targetToken ~= previousTarget then
		state.TargetToken = targetToken
		if previousTarget ~= nil then
			state.HadCombat = true
			state.Mode = targetToken ~= nil and "Retarget" or "Return"
			local recover = targetToken ~= nil and Config.RetargetRecoverSeconds or Config.ReturnRecoverSeconds
			state.HoldUntil = math.max(state.HoldUntil or 0, clock + recover + stagger(slot))
		elseif targetToken ~= nil then
			state.HadCombat = true
			state.Mode = (state.HoldUntil or 0) > clock and "Retarget" or "Combat"
		end
	end

	if state.HadCombat and (state.HoldUntil or 0) > clock and visualPosition then
		return visualPosition, {
			FollowSpeed = Config.ReturnFollowSpeed,
			MaxHorizontalSpeed = 0,
		}, true
	end

	if targetToken ~= nil and combatGoal then
		local maxSpeed = state.Mode == "Retarget"
			and Config.RetargetMaxSpeedStuds
			or Config.CombatApproachMaxSpeedStuds
		state.Mode = "Combat"
		return combatGoal, {
			FollowSpeed = Config.CombatApproachFollowSpeed,
			MaxHorizontalSpeed = maxSpeed,
		}, false
	end

	if state.HadCombat then
		state.Mode = "Return"
		if visualPosition and followGoal
			and horizontalDistance(visualPosition, followGoal) <= Config.TransitionSettleRadiusStuds
		then
			state.HadCombat = false
			state.Mode = "Follow"
			state.HoldUntil = 0
			return followGoal, nil, false
		end
		return followGoal, {
			FollowSpeed = Config.ReturnFollowSpeed,
			MaxHorizontalSpeed = Config.ReturnMaxSpeedStuds,
		}, false
	end

	return followGoal, nil, false
end

function CombatTransitionRuntime.trim(states, partyCount)
	for slot in pairs(states) do
		if slot > partyCount then
			states[slot] = nil
		end
	end
end

return CombatTransitionRuntime
