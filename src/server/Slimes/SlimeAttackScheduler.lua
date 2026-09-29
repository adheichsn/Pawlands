local SlimeAttackScheduler = {}

-- Player keys are weak so a leaving player cannot keep scheduler state alive.
local stateByPlayer = setmetatable({}, { __mode = "k" })

local function stateFor(player)
	local state = stateByPlayer[player]
	if state then
		return state
	end
	state = {
		Active = {},
		ActiveCount = 0,
		NextGlobalAttackAt = 0,
	}
	stateByPlayer[player] = state
	return state
end

function SlimeAttackScheduler.TryClaim(agent, player, now, config)
	if not agent or not player then
		return false
	end
	local state = stateFor(player)
	if state.Active[agent] then
		return true
	end
	if state.ActiveCount >= math.max(1, config.MaxConcurrentAttackers or 1) then
		return false
	end
	if now < state.NextGlobalAttackAt then
		return false
	end

	state.Active[agent] = true
	state.ActiveCount += 1
	agent.Model:SetAttribute("AttackTurnActive", true)
	return true
end

function SlimeAttackScheduler.Release(agent, player, now, gapSeconds)
	if not agent or not player then
		return
	end
	local state = stateByPlayer[player]
	if not state or not state.Active[agent] then
		agent.Model:SetAttribute("AttackTurnActive", false)
		return
	end

	state.Active[agent] = nil
	state.ActiveCount = math.max(0, state.ActiveCount - 1)
	state.NextGlobalAttackAt = math.max(
		state.NextGlobalAttackAt,
		(now or time()) + math.max(0, gapSeconds or 0)
	)
	agent.Model:SetAttribute("AttackTurnActive", false)
end

function SlimeAttackScheduler.Reset()
	for _, state in pairs(stateByPlayer) do
		for agent in pairs(state.Active) do
			if agent.Model then
				agent.Model:SetAttribute("AttackTurnActive", false)
			end
		end
	end
	table.clear(stateByPlayer)
end

return SlimeAttackScheduler
