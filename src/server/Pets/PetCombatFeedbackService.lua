local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pawlands = ReplicatedStorage:WaitForChild("Pawlands")
local Shared = Pawlands:WaitForChild("Shared")
local Config = require(Shared.Config.PetCombat)

local PetCombatFeedbackService = {}

local started = false
local feedbackRemote = nil

local function ensureRemoteFolder()
	local folder = Pawlands:FindFirstChild(Config.RemoteFolderName)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Config.RemoteFolderName
		folder.Parent = Pawlands
	end
	return folder
end

local function ensureFeedbackRemote()
	local folder = ensureRemoteFolder()
	local remote = folder:FindFirstChild(Config.FeedbackRemoteName)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = Config.FeedbackRemoteName
		remote.Parent = folder
	end
	return remote
end

function PetCombatFeedbackService.PublishHit(player, petSlot, knockedOut)
	if not started or not feedbackRemote then
		return
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return
	end
	if type(petSlot) ~= "number" then
		return
	end
	petSlot = math.floor(petSlot)
	if petSlot < 1 then
		return
	end

	-- The server only publishes presentation metadata after authoritative pet
	-- damage succeeds. Every client resolves its own local pet visual clone.
	feedbackRemote:FireAllClients(player.UserId, petSlot, knockedOut == true)
end

function PetCombatFeedbackService.Start()
	if started then
		return
	end
	started = true
	feedbackRemote = ensureFeedbackRemote()
end

function PetCombatFeedbackService.Stop()
	started = false
	feedbackRemote = nil
end

return PetCombatFeedbackService
