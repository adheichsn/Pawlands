local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PetCombat)

local PetCombatPresentationRuntime = {}
local statesByOwner = {}

local function horizontal(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function normalizedHorizontal(vector)
	if typeof(vector) ~= "Vector3" then
		return nil
	end
	local flat = horizontal(vector)
	if flat.Magnitude <= 0.001 then
		return nil
	end
	return flat.Unit
end

local function ownerStates(ownerUserId)
	local states = statesByOwner[ownerUserId]
	if not states then
		states = {}
		statesByOwner[ownerUserId] = states
	end
	return states
end

local function getState(ownerUserId, petSlot)
	local states = ownerStates(ownerUserId)
	local state = states[petSlot]
	if state then
		return state
	end
	state = {
		HitStartedAt = -math.huge,
		LastHitDirection = nil,
		EventKnockedOut = false,
		EventRecoverAt = 0,
		WasKnockedOut = false,
		KnockoutStartedAt = -math.huge,
		DownPosition = nil,
		FrozenYaw = nil,
		KnockoutAwayDirection = nil,
		RecoveryStartedAt = -math.huge,
	}
	states[petSlot] = state
	return state
end

local function mergeProfile(base, overrides)
	local result = {}
	for key, value in pairs(base or {}) do
		result[key] = value
	end
	for key, value in pairs(overrides or {}) do
		result[key] = value
	end
	return result
end

local function isKnockedOut(state, vitals)
	local serverNow = Workspace:GetServerTimeNow()
	-- The replicated vitals snapshot is canonical when it exists. The feedback
	-- event is only a short race/streaming fallback, so an explicit server heal
	-- (including Studio !petheal) can end the down presentation immediately.
	if type(vitals) == "table" and type(vitals.KO) == "boolean" then
		if vitals.KO ~= true then
			state.EventKnockedOut = false
			state.EventRecoverAt = 0
		end
		return vitals.KO == true
	end
	if state.EventKnockedOut and state.EventRecoverAt > serverNow then
		return true
	end
	if state.EventKnockedOut and state.EventRecoverAt <= serverNow then
		state.EventKnockedOut = false
		state.EventRecoverAt = 0
	end
	return false
end

local function resolveAwayDirection(state, visual, targetPosition)
	local direction = state.LastHitDirection
	if direction then
		return direction
	end
	if visual.Position and typeof(targetPosition) == "Vector3" then
		direction = normalizedHorizontal(visual.Position - targetPosition)
		if direction then
			return direction
		end
	end
	local yaw = visual.Yaw
	if type(yaw) == "number" then
		return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	end
	return Vector3.new(0, 0, 1)
end

function PetCombatPresentationRuntime.RecordHit(ownerUserId, petSlot, knockedOut, recoverAt, hitDirection)
	if type(ownerUserId) ~= "number" or type(petSlot) ~= "number" then
		return
	end
	petSlot = math.floor(petSlot)
	if petSlot < 1 then
		return
	end

	local state = getState(ownerUserId, petSlot)
	state.HitStartedAt = os.clock()
	state.LastHitDirection = normalizedHorizontal(hitDirection)
	if knockedOut == true then
		state.EventKnockedOut = true
		state.EventRecoverAt = math.max(tonumber(recoverAt) or 0, Workspace:GetServerTimeNow() + 0.1)
	end
end

function PetCombatPresentationRuntime.Step(ownerUserId, petSlot, visual, vitals, targetPosition, clock, target, targetYaw, attackOffset, motionProfile)
	local state = getState(ownerUserId, petSlot)
	local knockedOut = isKnockedOut(state, vitals)

	if knockedOut and not state.WasKnockedOut then
		state.KnockoutStartedAt = clock
		state.DownPosition = visual.Position
		state.FrozenYaw = visual.Yaw
		state.KnockoutAwayDirection = resolveAwayDirection(state, visual, targetPosition)
		state.RecoveryStartedAt = -math.huge
	elseif not knockedOut and state.WasKnockedOut then
		state.RecoveryStartedAt = clock
		state.EventKnockedOut = false
		state.EventRecoverAt = 0
	end
	state.WasKnockedOut = knockedOut

	local offset = attackOffset or Vector3.zero
	local suppressAttack = false
	local profile = motionProfile

	if knockedOut then
		suppressAttack = true
		offset = Vector3.zero
		local downPosition = state.DownPosition or visual.Position or target
		if downPosition then
			target = downPosition
		end
		targetYaw = state.FrozenYaw or visual.Yaw or targetYaw
		profile = mergeProfile(profile, {
			FollowSpeed = 1,
			MaxHorizontalSpeed = 0,
			TurnSpeedDegreesPerSecond = Config.CombatTurnSpeedDegreesPerSecond,
			SuppressAmbientMotion = true,
			PresentationPitchDegrees = Config.PetKnockoutPitchDegrees,
			PresentationRollDegrees = Config.PetKnockoutRollDegrees,
		})

		local pushDuration = math.max(0.01, Config.PetKnockoutPushSeconds)
		local pushAlpha = math.clamp((clock - state.KnockoutStartedAt) / pushDuration, 0, 1)
		local eased = 1 - (1 - pushAlpha) * (1 - pushAlpha)
		local away = state.KnockoutAwayDirection or Vector3.zero
		offset += away * (Config.PetKnockoutBackStuds * eased)
	else
		local hitAge = clock - state.HitStartedAt
		if hitAge >= 0 and hitAge <= Config.PetHitRecoilSeconds then
			local t = hitAge / math.max(0.01, Config.PetHitRecoilSeconds)
			local away = state.LastHitDirection or Vector3.zero
			offset += away * (math.sin(t * math.pi) * Config.PetHitRecoilStuds)
		end

		local recoveryAge = clock - state.RecoveryStartedAt
		if recoveryAge >= 0 and recoveryAge <= Config.PetRecoveryBounceSeconds then
			local t = recoveryAge / math.max(0.01, Config.PetRecoveryBounceSeconds)
			offset += Vector3.new(0, math.sin(t * math.pi) * Config.PetRecoveryBounceStuds, 0)
			local away = state.KnockoutAwayDirection or Vector3.zero
			offset += away * (Config.PetKnockoutBackStuds * (1 - t))
		end
	end

	return target, targetYaw, offset, profile, suppressAttack, knockedOut
end

function PetCombatPresentationRuntime.ClearOwner(ownerUserId)
	statesByOwner[ownerUserId] = nil
end

function PetCombatPresentationRuntime.Clear()
	table.clear(statesByOwner)
end

return PetCombatPresentationRuntime
