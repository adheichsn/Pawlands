local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.Dialogue)
local DialogueDefinitions = require(Shared.Dialogue.DialogueDefinitions)

local DialogueService = {}
local started = false
local remote
local promptTriggeredConnection
local remoteConnection
local playerAddedConnection
local playerRemovingConnection
local heartbeatConnection
local characterConnections = {}
local sessions = {}
local nextSessionId = 0
local distanceAccumulator = 0

local function ensureRemote()
	local pawlands = ReplicatedStorage:WaitForChild("Pawlands")
	local folder = pawlands:FindFirstChild(Config.RemoteFolderName)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Config.RemoteFolderName
		folder.Parent = pawlands
	end

	local event = folder:FindFirstChild(Config.RemoteEventName)
	if event and not event:IsA("RemoteEvent") then
		event:Destroy()
		event = nil
	end
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = Config.RemoteEventName
		event.Parent = folder
	end
	return event
end

local function findNpcModel(prompt)
	local current = prompt and prompt.Parent
	while current and current ~= Workspace do
		if current:IsA("Model") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function findNpcRoot(npcModel)
	if not npcModel then
		return nil
	end
	local root = npcModel:FindFirstChild(Config.NpcRootPartName, true)
	if root and root:IsA("BasePart") then
		return root
	end
	if npcModel.PrimaryPart and npcModel.PrimaryPart:IsA("BasePart") then
		return npcModel.PrimaryPart
	end
	return nil
end

local function findPlayerRoot(player)
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function maximumDistance(prompt)
	local promptDistance = Config.DefaultPromptDistance
	if prompt and prompt:IsA("ProximityPrompt") and prompt.MaxActivationDistance > 0 then
		promptDistance = prompt.MaxActivationDistance
	end
	return math.min(promptDistance + Config.DistanceGraceStuds, Config.MaximumServerDistance)
end

local function isSessionInRange(player, npcModel, prompt)
	local playerRoot = findPlayerRoot(player)
	local npcRoot = findNpcRoot(npcModel)
	if not playerRoot or not npcRoot then
		return false
	end
	return (playerRoot.Position - npcRoot.Position).Magnitude <= maximumDistance(prompt)
end

local function serializeNode(definition, node)
	local choices = {}
	if type(node.Choices) == "table" then
		for index, choice in ipairs(node.Choices) do
			if index > 2 then
				break
			end
			table.insert(choices, {
				Id = choice.Id,
				Text = choice.Text,
			})
		end
	else
		table.insert(choices, {
			Id = node.Next and Config.ContinueChoiceId or Config.CloseChoiceId,
			Text = Config.ContinueText,
		})
	end

	return {
		Speaker = definition.Speaker,
		Text = node.Text,
		Choices = choices,
	}
end

local function closeSession(player, reason)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	if remote then
		remote:FireClient(player, "Close", session.Id, reason or "Closed")
	end
end

local function sendCurrentNode(player, operation)
	local session = sessions[player]
	if not session then
		return
	end
	local node = session.Definition.Nodes[session.NodeId]
	if not node then
		closeSession(player, "InvalidNode")
		return
	end
	remote:FireClient(player, operation or "Node", session.Id, serializeNode(session.Definition, node))
end

local function openForPrompt(prompt, player)
	if not started or not prompt or not player or not prompt:IsDescendantOf(Workspace) then
		return
	end
	if not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
		return
	end
	if sessions[player] then
		return
	end

	local npcModel = findNpcModel(prompt)
	if not npcModel then
		return
	end
	local dialogueId = npcModel:GetAttribute(Config.DialogueIdAttribute)
	if type(dialogueId) ~= "string" or dialogueId == "" then
		dialogueId = DialogueDefinitions.ResolveIdFromNpcName(npcModel.Name)
	end
	local definition = dialogueId and DialogueDefinitions.Get(dialogueId) or nil
	if not definition or not definition.Nodes or not definition.Nodes[definition.StartNode] then
		return
	end
	if not isSessionInRange(player, npcModel, prompt) then
		return
	end

	nextSessionId += 1
	local session = {
		Id = nextSessionId,
		DialogueId = dialogueId,
		Definition = definition,
		NodeId = definition.StartNode,
		NpcModel = npcModel,
		Prompt = prompt,
	}
	sessions[player] = session
	sendCurrentNode(player, "Open")
end

local function processChoice(player, sessionId, choiceId)
	local session = sessions[player]
	if not session or session.Id ~= sessionId or type(choiceId) ~= "string" then
		return
	end
	if not session.NpcModel.Parent or not session.Prompt.Parent
		or not isSessionInRange(player, session.NpcModel, session.Prompt)
	then
		closeSession(player, "WalkedAway")
		return
	end

	local node = session.Definition.Nodes[session.NodeId]
	if not node then
		closeSession(player, "InvalidNode")
		return
	end

	local nextNodeId
	if type(node.Choices) == "table" then
		for _, choice in ipairs(node.Choices) do
			if choice.Id == choiceId then
				if choice.Close == true then
					closeSession(player, "Complete")
					return
				end
				nextNodeId = choice.Next
				break
			end
		end
		if not nextNodeId then
			return
		end
	elseif node.Next then
		if choiceId ~= Config.ContinueChoiceId then
			return
		end
		nextNodeId = node.Next
	else
		if choiceId ~= Config.CloseChoiceId then
			return
		end
		closeSession(player, "Complete")
		return
	end

	if not session.Definition.Nodes[nextNodeId] then
		closeSession(player, "InvalidNode")
		return
	end
	session.NodeId = nextNodeId
	sendCurrentNode(player, "Node")
end

local function processClientEvent(player, operation, sessionId, payload)
	if operation == "Choose" then
		processChoice(player, sessionId, payload)
	elseif operation == "Close" then
		local session = sessions[player]
		if session and session.Id == sessionId then
			closeSession(player, "ClientClosed")
		end
	end
end

local function disconnectCharacterRecord(record)
	if not record then
		return
	end
	if record.Added then
		record.Added:Disconnect()
	end
	if record.Removing then
		record.Removing:Disconnect()
	end
end

local function bindPlayer(player)
	disconnectCharacterRecord(characterConnections[player])
	characterConnections[player] = {
		Added = player.CharacterAdded:Connect(function()
			closeSession(player, "CharacterChanged")
		end),
		Removing = player.CharacterRemoving:Connect(function()
			closeSession(player, "CharacterChanged")
		end),
	}
end

local function unbindPlayer(player)
	closeSession(player, "PlayerRemoving")
	disconnectCharacterRecord(characterConnections[player])
	characterConnections[player] = nil
end

local function updateDistanceChecks(dt)
	distanceAccumulator += dt
	if distanceAccumulator < Config.DistanceCheckSeconds then
		return
	end
	distanceAccumulator = 0

	for player, session in pairs(sessions) do
		if not player.Parent or not session.NpcModel.Parent or not session.Prompt.Parent
			or not isSessionInRange(player, session.NpcModel, session.Prompt)
		then
			closeSession(player, "WalkedAway")
		end
	end
end

function DialogueService.Start()
	if started then
		return
	end
	started = true
	remote = ensureRemote()

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	playerAddedConnection = Players.PlayerAdded:Connect(bindPlayer)
	playerRemovingConnection = Players.PlayerRemoving:Connect(unbindPlayer)
	promptTriggeredConnection = ProximityPromptService.PromptTriggered:Connect(openForPrompt)
	remoteConnection = remote.OnServerEvent:Connect(processClientEvent)
	heartbeatConnection = RunService.Heartbeat:Connect(updateDistanceChecks)
end

function DialogueService.Stop()
	if not started then
		return
	end
	started = false

	for player in pairs(sessions) do
		closeSession(player, "ServiceStopped")
	end
	for player, record in pairs(characterConnections) do
		disconnectCharacterRecord(record)
		characterConnections[player] = nil
	end
	if promptTriggeredConnection then
		promptTriggeredConnection:Disconnect()
		promptTriggeredConnection = nil
	end
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
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	remote = nil
	distanceAccumulator = 0
end

return DialogueService
