local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetCombat)
local FollowConfig = require(Shared.Config.PetFollow)

local PetStrikeAuthority = {}

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function horizontalDistance(a, b)
	return horizontal(a - b).Magnitude
end

local function phaseOffset(slot)
	return math.max(0, slot - 1) * Config.AttackStaggerSeconds
end

local function followSlot(index, count)
	local columns = math.min(2, count)
	local row = math.floor((index - 1) / columns)
	local column = (index - 1) % columns
	local inRow = math.min(columns, count - row * columns)
	return (column - (inRow - 1) / 2) * FollowConfig.Spacing,
		FollowConfig.FirstRow + row * FollowConfig.RowDepth
end

local function estimatedFollowPosition(root, slot, partyCount)
	local look = horizontal(root.CFrame.LookVector)
	if look.Magnitude <= 0.001 then
		look = Vector3.new(0, 0, -1)
	else
		look = look.Unit
	end
	local frame = CFrame.lookAt(root.Position, root.Position + look)
	local x, z = followSlot(slot, partyCount)
	return frame:PointToWorldSpace(Vector3.new(x, 0, z))
end

local function approachPosition(current, goal, dt)
	if typeof(current) ~= "Vector3" then
		return goal
	end
	if typeof(goal) ~= "Vector3" then
		return current
	end
	local alpha = 1 - math.exp(-Config.CombatApproachFollowSpeed * math.max(0, dt))
	local desired = current:Lerp(goal, alpha)
	local delta = horizontal(desired - current)
	local maxStep = math.max(0, Config.CombatApproachMaxSpeedStuds) * math.max(0, dt)
	if delta.Magnitude > maxStep and delta.Magnitude > 0.001 then
		delta = delta.Unit * maxStep
	end
	return Vector3.new(current.X + delta.X, goal.Y, current.Z + delta.Z)
end

local function makeGuard(entry, previous, root, partyCount, clock)
	local startPosition = previous and previous.ProxyPosition
	if typeof(startPosition) ~= "Vector3" then
		startPosition = estimatedFollowPosition(root, entry.Slot, partyCount)
	end
	return {
		Uid = entry.Uid,
		SlimeModel = entry.SlimeModel,
		SlimeSlot = entry.SlimeSlot,
		ProxyPosition = startPosition,
		ReadySince = nil,
		TargetPositionAtCommit = nil,
		CommitForImpactAt = nil,
		NextImpactAt = clock + Config.AttackInitialDelaySeconds + phaseOffset(entry.Slot),
	}
end

function PetStrikeAuthority.Sync(guards, combatTargets, root, partyCount, clock, dt)
	local activeSlots = {}
	for petSlot, entry in pairs(combatTargets or {}) do
		activeSlots[petSlot] = true
		local previous = guards[petSlot]
		local guard = previous
		if not guard
			or guard.Uid ~= entry.Uid
			or guard.SlimeModel ~= entry.SlimeModel
			or guard.SlimeSlot ~= entry.SlimeSlot
		then
			guard = makeGuard(entry, previous, root, partyCount, clock)
			guards[petSlot] = guard
		end

		guard.ProxyPosition = approachPosition(guard.ProxyPosition, entry.Position, dt)
		local readyDistance = horizontalDistance(guard.ProxyPosition, entry.Position)
		local ready = readyDistance
			<= Config.AttackReadyRadiusStuds + Config.ServerProxyReadyToleranceStuds

		if ready then
			if not guard.ReadySince then
				guard.ReadySince = clock
				guard.NextImpactAt = math.max(
					guard.NextImpactAt or 0,
					clock + Config.AttackInitialDelaySeconds + phaseOffset(petSlot)
				)
			end

			local commitLead = Config.AttackDurationSeconds * Config.AttackImpactAlpha
				+ Config.ServerStrikeCommitLeadPaddingSeconds
			if clock + commitLead >= (guard.NextImpactAt or clock)
				and guard.CommitForImpactAt ~= guard.NextImpactAt
				and entry.SlimeModel
				and entry.SlimeModel.Parent
			then
				guard.TargetPositionAtCommit = entry.SlimeModel:GetPivot().Position
				guard.CommitForImpactAt = guard.NextImpactAt
			end
		else
			guard.ReadySince = nil
			guard.TargetPositionAtCommit = nil
			guard.CommitForImpactAt = nil
			guard.NextImpactAt = math.max(
				guard.NextImpactAt or 0,
				clock + Config.AttackInitialDelaySeconds + phaseOffset(petSlot)
			)
		end
	end

	for petSlot in pairs(guards) do
		if not activeSlots[petSlot] then
			guards[petSlot] = nil
		end
	end
end

function PetStrikeAuthority.ValidateImpact(guard, entry, slimePosition, clock)
	if not guard or not entry or typeof(slimePosition) ~= "Vector3" then
		return false, "MissingAuthorityState"
	end
	if not guard.ReadySince or typeof(guard.ProxyPosition) ~= "Vector3" then
		return false, "ProxyNotReady"
	end

	local nextImpactAt = tonumber(guard.NextImpactAt) or clock
	if clock + Config.ServerImpactCadenceToleranceSeconds < nextImpactAt then
		return false, "EarlyImpact"
	end

	-- Do not reject a legitimate authored impact just because an earlier impact
	-- window was missed while the server proxy was still approaching. The old
	-- late-window gate could deadlock this guard forever: once one impact was
	-- rejected as ProxyNotReady/EarlyImpact, every later client impact became
	-- LateImpact because NextImpactAt only advances after an accepted hit.
	--
	-- NextImpactAt is therefore an *earliest allowed* time, not a narrow hit
	-- appointment. Accepted hits still advance it by AttackCadenceSeconds, so
	-- spam/early impacts remain server-gated.

	local currentDistance = horizontalDistance(guard.ProxyPosition, slimePosition)
	local inCurrentRange = currentDistance <= Config.ServerStrikeMaxProxyDistanceStuds
	local committedPosition = guard.TargetPositionAtCommit
	local targetDrift = typeof(committedPosition) == "Vector3"
		and horizontalDistance(committedPosition, slimePosition)
		or math.huge
	local withinCommittedDrift = targetDrift <= Config.ServerStrikeCommitMaxTargetDriftStuds
	if not inCurrentRange and not withinCommittedDrift then
		return false, "ContactMiss"
	end
	return true, nil
end

function PetStrikeAuthority.CommitImpact(guard, slimePosition, clock)
	guard.NextImpactAt = clock + Config.AttackCadenceSeconds
	guard.TargetPositionAtCommit = typeof(slimePosition) == "Vector3" and slimePosition or nil
	guard.CommitForImpactAt = nil
end

return PetStrikeAuthority
