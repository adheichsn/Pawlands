local SlimeAttackScheduler = {}

-- Scheduler buckets are per concrete combat target. Player targets use a
-- player:<UserId> key; pet targets use pet:<UserId>:<Uid>. This preserves the
-- existing one-at-a-time Player pressure while allowing separate pets to be
-- pressured independently.
local stateByTarget = {}
local nextTicket = 0

local function stateFor(targetKey)
	local state = stateByTarget[targetKey]
	if state then
		return state
	end
	state = {
		Active = {},
		ActiveCount = 0,
		NextGlobalAttackAt = 0,
		Queue = setmetatable({}, { __mode = "k" }),
	}
	stateByTarget[targetKey] = state
	return state
end

local function pruneQueue(state, targetKey, now, lifetime)
	for agent, request in pairs(state.Queue) do
		if not agent.Model
			or not agent.Model.Parent
			or agent.TargetKey ~= targetKey
			or not agent.CombatReady
			or now - request.LastSeen > lifetime
		then
			state.Queue[agent] = nil
		end
	end
end

function SlimeAttackScheduler.Withdraw(agent)
	for _, state in pairs(stateByTarget) do
		state.Queue[agent] = nil
	end
	if agent and agent.Model then
		agent.Model:SetAttribute("AttackQueued", false)
	end
end

function SlimeAttackScheduler.TryClaim(agent, targetKey, now, config)
	if not agent or not targetKey or not agent.Model or not agent.Model.Parent then
		return false
	end
	local state = stateFor(targetKey)
	if state.Active[agent] then
		return true
	end

	local lifetime = math.max(0.1, config.AttackQueueRequestLifetimeSeconds or 1)
	pruneQueue(state, targetKey, now, lifetime)
	local request = state.Queue[agent]
	if not request then
		nextTicket += 1
		request = { Ticket = nextTicket }
		state.Queue[agent] = request
	end
	request.LastSeen = now
	agent.Model:SetAttribute("AttackQueued", true)

	for _, other in pairs(state.Queue) do
		if other.Ticket < request.Ticket then
			return false
		end
	end
	if state.ActiveCount >= math.max(1, config.MaxConcurrentAttackers or 1) then
		return false
	end
	if now < state.NextGlobalAttackAt then
		return false
	end

	state.Queue[agent] = nil
	state.Active[agent] = true
	state.ActiveCount += 1
	agent.Model:SetAttribute("AttackQueued", false)
	agent.Model:SetAttribute("AttackTurnActive", true)
	return true
end

function SlimeAttackScheduler.Release(agent, targetKey, now, consumeCooldown, config, targetKind)
	if not agent or not targetKey then
		return
	end
	local state = stateByTarget[targetKey]
	if state then
		state.Queue[agent] = nil
	end
	if not state or not state.Active[agent] then
		if agent.Model then
			agent.Model:SetAttribute("AttackQueued", false)
			agent.Model:SetAttribute("AttackTurnActive", false)
		end
		return
	end

	state.Active[agent] = nil
	state.ActiveCount = math.max(0, state.ActiveCount - 1)
	if consumeCooldown then
		local cooldown = targetKind == "Pet"
			and (config.PetPressureCooldownSeconds or config.PlayerPressureCooldownSeconds or 0)
			or (config.PlayerPressureCooldownSeconds or 0)
		state.NextGlobalAttackAt = math.max(state.NextGlobalAttackAt, (now or time()) + math.max(0, cooldown))
	end
	agent.Model:SetAttribute("AttackQueued", false)
	agent.Model:SetAttribute("AttackTurnActive", false)
end

function SlimeAttackScheduler.Reset()
	for _, state in pairs(stateByTarget) do
		for agent in pairs(state.Active) do
			if agent.Model then
				agent.Model:SetAttribute("AttackTurnActive", false)
				agent.Model:SetAttribute("AttackQueued", false)
			end
		end
		for agent in pairs(state.Queue) do
			if agent.Model then
				agent.Model:SetAttribute("AttackQueued", false)
			end
		end
	end
	table.clear(stateByTarget)
end

return SlimeAttackScheduler
