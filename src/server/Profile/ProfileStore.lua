local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.Profile)
local Schema = require(script.Parent.ProfileSchema)

local ProfileStore = {}
local persistent = not RunService:IsStudio() or Config.UseDataStoreInStudio == true
local dataStore = persistent and DataStoreService:GetDataStore(Config.DataStoreName) or nil
local memoryRecords = {}
local currentSessionId = (type(game.JobId) == "string" and game.JobId ~= "")
	and game.JobId
	or ("studio-" .. HttpService:GenerateGUID(false))

local function keyFor(userId)
	return Config.KeyPrefix .. tostring(userId)
end

local function sessionId()
	return currentSessionId
end

local function retry(attempts, callback)
	local lastError
	for attempt = 1, attempts do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < attempts then
			task.wait(Config.RetryBaseSeconds * (2 ^ (attempt - 1)))
		end
	end
	return false, lastError
end

local function sessionIsActive(session, now)
	if type(session) ~= "table" or type(session.JobId) ~= "string" or session.JobId == "" then
		return false
	end
	if session.JobId == sessionId() then
		return false
	end
	local heartbeat = tonumber(session.Heartbeat) or 0
	return now - heartbeat < Config.SessionLockTimeoutSeconds
end

local function makeSession(now)
	return {
		JobId = sessionId(),
		PlaceId = game.PlaceId,
		Heartbeat = now,
	}
end

function ProfileStore.IsPersistent()
	return persistent
end

function ProfileStore.Load(userId)
	local numericUserId = tonumber(userId)
	if not numericUserId then
		return nil, "Invalid UserId."
	end

	if not persistent then
		local current = memoryRecords[numericUserId]
		local record, reason = Schema.NormalizeRecord(current)
		if not record then
			return nil, reason
		end
		record.Session = makeSession(os.time())
		memoryRecords[numericUserId] = Schema.DeepCopy(record)
		return Schema.DeepCopy(record.Data), nil
	end

	local lastBlockedReason
	for acquireAttempt = 1, Config.SessionAcquireAttempts do
		local blockedReason
		local ok, result = retry(Config.LoadAttempts, function()
			return dataStore:UpdateAsync(keyFor(numericUserId), function(current)
				local record, reason = Schema.NormalizeRecord(current)
				if not record then
					blockedReason = reason
					return nil
				end
				local now = os.time()
				if sessionIsActive(record.Session, now) then
					blockedReason = "Profile is still active in another server."
					return nil
				end
				record.Session = makeSession(now)
				return record
			end)
		end)
		if not ok then
			return nil, "DataStore load failed: " .. tostring(result)
		end
		if not blockedReason then
			local record, reason = Schema.NormalizeRecord(result)
			if not record then
				return nil, reason
			end
			return Schema.DeepCopy(record.Data), nil
		end

		lastBlockedReason = blockedReason
		if blockedReason ~= "Profile is still active in another server." then
			break
		end
		if acquireAttempt < Config.SessionAcquireAttempts then
			task.wait(Config.SessionAcquireRetrySeconds)
		end
	end
	return nil, lastBlockedReason or "Profile session could not be acquired."
end

local function write(userId, data, release)
	local numericUserId = tonumber(userId)
	if not numericUserId then
		return false, "Invalid UserId."
	end
	local normalizedData = Schema.NormalizeData(data)

	if not persistent then
		local record = {
			SchemaVersion = Config.SchemaVersion,
			Session = nil,
			Data = normalizedData,
		}
		if not release then
			record.Session = makeSession(os.time())
		end
		memoryRecords[numericUserId] = Schema.DeepCopy(record)
		return true, nil
	end

	local blockedReason
	local ok, result = retry(Config.SaveAttempts, function()
		return dataStore:UpdateAsync(keyFor(numericUserId), function(current)
			local record, reason = Schema.NormalizeRecord(current)
			if not record then
				blockedReason = reason
				return nil
			end
			local currentSession = record.Session
			if currentSession
				and currentSession.JobId ~= ""
				and currentSession.JobId ~= sessionId()
			then
				blockedReason = "Profile session lock was lost to another server."
				return nil
			end
			record.SchemaVersion = Config.SchemaVersion
			record.Data = normalizedData
			if release then
				record.Session = nil
			else
				record.Session = makeSession(os.time())
			end
			return record
		end)
	end)
	if blockedReason then
		return false, blockedReason
	end
	if not ok then
		return false, "DataStore save failed: " .. tostring(result)
	end
	return true, nil
end

function ProfileStore.Save(userId, data)
	return write(userId, data, false)
end

function ProfileStore.Release(userId, data)
	return write(userId, data, true)
end

function ProfileStore.ResetOwned(userId)
	local numericUserId = tonumber(userId)
	if not numericUserId then
		return false, "Invalid UserId."
	end

	if not persistent then
		memoryRecords[numericUserId] = nil
		return true, nil
	end

	local blockedReason
	local ok, result = retry(Config.SaveAttempts, function()
		return dataStore:UpdateAsync(keyFor(numericUserId), function(current)
			local record, reason = Schema.NormalizeRecord(current)
			if not record then
				blockedReason = reason
				return nil
			end
			local currentSession = record.Session
			if currentSession
				and currentSession.JobId ~= ""
				and currentSession.JobId ~= sessionId()
			then
				blockedReason = "Profile session lock is owned by another server."
				return nil
			end
			return {
				SchemaVersion = Config.SchemaVersion,
				Session = nil,
				Data = Schema.NewData(),
			}
		end)
	end)
	if blockedReason then
		return false, blockedReason
	end
	if not ok then
		return false, "DataStore reset failed: " .. tostring(result)
	end
	return true, nil
end

return ProfileStore
