local InteractionLock = {}

local activeReasons = {}
local listeners = {}

local function isAnyLocked()
	return next(activeReasons) ~= nil
end

local function isLockedExcept(excludedReason)
	for reason in pairs(activeReasons) do
		if reason ~= excludedReason then
			return true
		end
	end
	return false
end

local function notify()
	local locked = isAnyLocked()
	for callback in pairs(listeners) do
		local ok, err = pcall(callback, locked)
		if not ok then
			warn("[Pawlands InteractionLock] listener failed: " .. tostring(err))
		end
	end
end

function InteractionLock.Set(reason, active)
	if type(reason) ~= "string" or reason == "" then
		return
	end

	local wasActive = activeReasons[reason] == true
	local shouldBeActive = active == true
	if wasActive == shouldBeActive then
		return
	end

	if shouldBeActive then
		activeReasons[reason] = true
	else
		activeReasons[reason] = nil
	end
	-- Notify on reason changes, not only aggregate locked/unlocked transitions.
	-- This lets scoped consumers react when another lock is added while one is
	-- already active (for example Dialogue opening while Inventory is visible).
	notify()
end

function InteractionLock.IsLocked(reason)
	if type(reason) == "string" and reason ~= "" then
		return activeReasons[reason] == true
	end
	return isAnyLocked()
end

function InteractionLock.IsLockedExcept(reason)
	if type(reason) ~= "string" or reason == "" then
		return isAnyLocked()
	end
	return isLockedExcept(reason)
end

function InteractionLock.Subscribe(callback)
	if type(callback) ~= "function" then
		return function() end
	end
	listeners[callback] = true
	callback(isAnyLocked())
	return function()
		listeners[callback] = nil
	end
end

function InteractionLock.Clear()
	if not isAnyLocked() then
		return
	end
	table.clear(activeReasons)
	notify()
end

return InteractionLock
