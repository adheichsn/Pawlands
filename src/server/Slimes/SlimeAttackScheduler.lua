local SlimeAttackScheduler = {}

-- Player keys are weak so leaving players cannot keep scheduler state alive.
local stateByPlayer = setmetatable({}, { __mode = "k" })
local nextTicket = 0

local function stateFor(player)
	local state = stateByPlayer[player]
	if state then
		return state
	end
	state = {
		Active = {},
		ActiveCount = 0,
		NextGlobalAttackAt = 0,
		Queue = setmetatable({}, { __mode = "k" }),
	}
	stateByPlayer[player] = state
	return state
end

local function pruneQueue(state, player, now, lifetime)
	for agent, request in pairs(state.Queue) do
		if not agent.Model
			or not agent.Model.Parent
			or agent.TargetPlayer ~= player
			or not agent.CombatReady
			or now - request.LastSeen > lifetime then
			state.Queue[agent] = nil
		end
	end
end

function SlimeAttackScheduler.Withdraw(agent)
	for _, state in pairs(stateByPlayer) do
		state.Queue[agent] = nil
	end
	if agent and agent.Model then
		agent.Model:SetAttribute("AttackQueued", false)
	end
end

-- Only attack-ready tutorial actors enter this FIFO queue. Pursuit never owns
-- the attack slot, and oldest request wins so heartbeat iteration order cannot
-- give the same slime every turn.
function SlimeAttackScheduler.TryClaim(agent, player, now, config)
	if not agent or not player or not agent.Model or not agent.Model.Parent then
		return false
	end
	local state = stateFor(player)
	if state.Active[agent] then
		return true
	end

	local lifetime = math.max(0.1, config.AttackQueueRequestLifetimeSeconds or 1)
	pruneQueue(state, player, now, lifetime)
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

function SlimeAttackScheduler.Release(agent, player, now, consumeCooldown, config)
	if not agent or not player then
		return
	end
	local state = stateByPlayer[player]
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
		state.NextGlobalAttackAt = math.max(
			state.NextGlobalAttackAt,
			(now or time()) + math.max(0, config.PlayerPressureCooldownSeconds or 0)
		)
	end
	agent.Model:SetAttribute("AttackQueued", false)
	agent.Model:SetAttribute("AttackTurnActive", false)
end

function SlimeAttackScheduler.Reset()
	for _, state in pairs(stateByPlayer) do
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
	table.clear(stateByPlayer)
end

return SlimeAttackScheduler
