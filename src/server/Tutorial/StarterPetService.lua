local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local TutorialConfig = require(Shared.Config.Tutorial)

local StarterPetService = {}
local started = false
local remote = nil
local remoteConnection = nil
local playerAddedConnection = nil
local playerRemovingConnection = nil
local inventoryService = nil
local tutorialService = nil
local profileService = nil
local requestInFlight = {}

local function ensureRemote()
	local pawlands = ReplicatedStorage:WaitForChild("Pawlands")
	local folder = pawlands:FindFirstChild(TutorialConfig.RemoteFolderName)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = TutorialConfig.RemoteFolderName
		folder.Parent = pawlands
	end

	local event = folder:FindFirstChild(TutorialConfig.StarterPetChoiceRemoteName)
	if event and not event:IsA("RemoteEvent") then
		event:Destroy()
		event = nil
	end
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = TutorialConfig.StarterPetChoiceRemoteName
		event.Parent = folder
	end
	return event
end

local function initializePlayer(player)
	if profileService then
		local profile = profileService.AwaitReady(player)
		if not profile or player.Parent ~= Players then
			return
		end
	end
	if player:GetAttribute(TutorialConfig.StarterPetGrantedAttributeName) == nil then
		player:SetAttribute(TutorialConfig.StarterPetGrantedAttributeName, false)
	end
	if player:GetAttribute(TutorialConfig.StarterPetUidAttributeName) == nil then
		player:SetAttribute(TutorialConfig.StarterPetUidAttributeName, "")
	end
	if player:GetAttribute(TutorialConfig.StarterPetSpeciesAttributeName) == nil then
		player:SetAttribute(TutorialConfig.StarterPetSpeciesAttributeName, "")
	end

	if player:GetAttribute(TutorialConfig.StarterPetGrantedAttributeName) == true
		and tutorialService
		and tutorialService.CanChooseStarterPet(player)
	then
		tutorialService.CompleteStarterPetChoice(player)
	end
end

local function reply(player, success, speciesId, uid, reason)
	if remote and player.Parent == Players then
		remote:FireClient(player, "Result", success == true, speciesId or "", uid or "", reason or "")
	end
end

local function chooseStarterPet(player, requestedSpecies)
	if not started or player.Parent ~= Players or type(requestedSpecies) ~= "string" then
		return
	end
	if requestInFlight[player] then
		reply(player, false, requestedSpecies, nil, "Starter Pet choice is already being processed.")
		return
	end
	if TutorialConfig.StarterPetChoices[requestedSpecies] == nil then
		reply(player, false, requestedSpecies, nil, "Invalid starter Pet choice.")
		return
	end
	if player:GetAttribute(TutorialConfig.StarterPetGrantedAttributeName) == true then
		reply(player, false, requestedSpecies, nil, "Starter Pet has already been granted.")
		return
	end
	if not tutorialService.CanChooseStarterPet(player) then
		reply(player, false, requestedSpecies, nil, "Starter Pet choice is not available at this tutorial stage.")
		return
	end

	requestInFlight[player] = true
	local pet, reason = inventoryService.Grant(player, requestedSpecies)
	if not pet then
		requestInFlight[player] = nil
		reply(player, false, requestedSpecies, nil, reason or "Starter Pet grant failed.")
		return
	end

	player:SetAttribute(TutorialConfig.StarterPetGrantedAttributeName, true)
	player:SetAttribute(TutorialConfig.StarterPetUidAttributeName, pet.Uid)
	player:SetAttribute(TutorialConfig.StarterPetSpeciesAttributeName, pet.SpeciesId)

	local advanced = tutorialService.CompleteStarterPetChoice(player)
	requestInFlight[player] = nil
	if not advanced then
		warn(string.format(
			"[Pawlands StarterPet] %s received %s but tutorial stage could not advance.",
			player.Name,
			tostring(pet.SpeciesId)
		))
	end
	reply(player, true, pet.SpeciesId, pet.Uid, nil)
end

function StarterPetService.Start(petInventoryService, tutorialProgressionService, playerProfileService)
	if started then
		return
	end
	if not petInventoryService or not tutorialProgressionService or not playerProfileService then
		error("StarterPetService requires PetInventoryService, TutorialService, and PlayerProfileService.")
	end
	started = true
	inventoryService = petInventoryService
	tutorialService = tutorialProgressionService
	profileService = playerProfileService
	remote = ensureRemote()
	remoteConnection = remote.OnServerEvent:Connect(chooseStarterPet)

	for _, player in ipairs(Players:GetPlayers()) do
		initializePlayer(player)
	end
	playerAddedConnection = Players.PlayerAdded:Connect(initializePlayer)
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		requestInFlight[player] = nil
	end)
end

function StarterPetService.Stop()
	if not started then
		return
	end
	started = false
	if remoteConnection then
		remoteConnection:Disconnect()
		remoteConnection = nil
	end
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	table.clear(requestInFlight)
	remote = nil
	inventoryService = nil
	tutorialService = nil
	profileService = nil
end

return StarterPetService
