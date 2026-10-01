local InteractionLock = {}

local activeReasons = {}
local listeners = {}

local function isAnyLocked()
	return next(activeReasons) ~= nil
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

	local wasLocked = isAnyLocked()
	if active == true then
		activeReasons[reason] = true
	else
		activeReasons[reason] = nil
	end
	local isLocked = isAnyLocked()
	if wasLocked ~= isLocked then
		notify()
	end
end

function InteractionLock.IsLocked(reason)
	if type(reason) == "string" and reason ~= "" then
		return activeReasons[reason] == true
	end
	return isAnyLocked()
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
