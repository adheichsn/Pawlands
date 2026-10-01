local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.Dialogue)
local InteractionLock = require(script.Parent.Parent.Interaction.InteractionLock)

local DialogueController = {}
local stopCurrent

local function disconnectConnections(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function getRemote()
	local pawlands = ReplicatedStorage:WaitForChild("Pawlands")
	local folder = pawlands:WaitForChild(Config.RemoteFolderName)
	return folder:WaitForChild(Config.RemoteEventName)
end

local function findGuiRefs(playerGui)
	local gui = playerGui:FindFirstChild(Config.GuiName)
	if not gui or not gui:IsA("ScreenGui") then
		return nil
	end
	local frame = gui:FindFirstChild(Config.FrameName)
	local warningText = gui:FindFirstChild(Config.WarningTextName)
	if not frame or not frame:IsA("Frame") then
		return nil
	end

	local username = frame:FindFirstChild(Config.UsernameName)
	local dialogueText = frame:FindFirstChild(Config.DialogueTextName)
	local option1 = frame:FindFirstChild(Config.Option1Name)
	local option2 = frame:FindFirstChild(Config.Option2Name)
	local typeSound = frame:FindFirstChild(Config.TypeSoundName)
	if not username or not username:IsA("TextLabel")
		or not dialogueText or not dialogueText:IsA("TextLabel")
		or not option1 or not option1:IsA("TextButton")
		or not option2 or not option2:IsA("TextButton")
	then
		return nil
	end

	return {
		Gui = gui,
		Frame = frame,
		Username = username,
		DialogueText = dialogueText,
		Option1 = option1,
		Option2 = option2,
		TypeSound = typeSound and typeSound:IsA("Sound") and typeSound or nil,
		WarningText = warningText and warningText:IsA("TextLabel") and warningText or nil,
		OnScreenPosition = frame.Position,
	}
end

local function offscreenPosition(position)
	return UDim2.new(position.X.Scale, position.X.Offset, 1.35, position.Y.Offset)
end

function DialogueController.Start()
	if stopCurrent then
		return
	end

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local remote = getRemote()
	local connections = {}
	local guiConnections = {}
	local refs
	local activeSessionId
	local currentChoices = {}
	local typingToken = 0
	local typing = false
	local pendingChoice = false
	local activeTween
	local warningToken = 0
	local transitionToken = 0
	local promptServiceWasEnabled
	local promptServiceLocked = false
	local fallbackPrompt
	local fallbackPromptWasEnabled
	local facingTween
	local facingHumanoid
	local facingAutoRotate

	local function cancelTween()
		transitionToken += 1
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
	end

	local function cancelFacingTween()
		if facingTween then
			facingTween:Cancel()
			facingTween = nil
		end
	end

	local function restoreFacing()
		cancelFacingTween()
		if facingHumanoid and facingHumanoid.Parent and facingAutoRotate ~= nil then
			facingHumanoid.AutoRotate = facingAutoRotate
		end
		facingHumanoid = nil
		facingAutoRotate = nil
	end

	local function faceNpc(npcPosition)
		restoreFacing()
		if typeof(npcPosition) ~= "Vector3" then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
			return
		end

		local delta = Vector3.new(npcPosition.X - root.Position.X, 0, npcPosition.Z - root.Position.Z)
		if delta.Magnitude <= 0.001 then
			return
		end
		facingHumanoid = humanoid
		facingAutoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false

		local target = CFrame.lookAt(root.Position, root.Position + delta.Unit, Vector3.yAxis)
		if Config.FaceNpcTweenSeconds <= 0 then
			root.CFrame = target
			return
		end
		facingTween = TweenService:Create(
			root,
			TweenInfo.new(Config.FaceNpcTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = target }
		)
		facingTween:Play()
	end

	local function restorePromptPresentation()
		if promptServiceLocked then
			pcall(function()
				ProximityPromptService.Enabled = promptServiceWasEnabled ~= false
			end)
			promptServiceLocked = false
			promptServiceWasEnabled = nil
		end
		if fallbackPrompt and fallbackPrompt.Parent and fallbackPromptWasEnabled ~= nil then
			fallbackPrompt.Enabled = fallbackPromptWasEnabled
		end
		fallbackPrompt = nil
		fallbackPromptWasEnabled = nil
	end

	local function hidePromptPresentation(prompt)
		restorePromptPresentation()
		local ok, current = pcall(function()
			return ProximityPromptService.Enabled
		end)
		if ok then
			local writeOk = pcall(function()
				ProximityPromptService.Enabled = false
			end)
			if writeOk then
				promptServiceWasEnabled = current
				promptServiceLocked = true
				return
			end
		end
		if prompt and prompt:IsA("ProximityPrompt") then
			fallbackPrompt = prompt
			fallbackPromptWasEnabled = prompt.Enabled
			prompt.Enabled = false
		end
	end

	local function engageInteraction(payload)
		InteractionLock.Set("Dialogue", true)
		hidePromptPresentation(payload and payload.Prompt or nil)
		faceNpc(payload and payload.NpcPosition or nil)
	end

	local function releaseInteraction(restorePromptNow)
		InteractionLock.Set("Dialogue", false)
		restoreFacing()
		if restorePromptNow then
			restorePromptPresentation()
		end
	end

	local function cancelTypewriter(revealAll)
		typingToken += 1
		typing = false
		if revealAll and refs and refs.DialogueText then
			refs.DialogueText.MaxVisibleGraphemes = -1
		end
	end

	local function hideChoices()
		if not refs then
			return
		end
		refs.Option1.Visible = false
		refs.Option2.Visible = false
		currentChoices = {}
	end

	local function playTypeSound(index)
		if not refs or not refs.TypeSound or refs.TypeSound.SoundId == "" then
			return
		end
		if index % Config.TypeSoundCharacterInterval ~= 0 then
			return
		end
		local sound = refs.TypeSound
		sound:Stop()
		sound.TimePosition = 0
		local minSpeed = math.floor(Config.TypeSoundPlaybackSpeedMin * 100)
		local maxSpeed = math.floor(Config.TypeSoundPlaybackSpeedMax * 100)
		if maxSpeed < minSpeed then
			minSpeed, maxSpeed = maxSpeed, minSpeed
		end
		sound.PlaybackSpeed = math.random(minSpeed, maxSpeed) / 100
		sound:Play()
	end

	local function showChoices(choices)
		if not refs or activeSessionId == nil then
			return
		end
		currentChoices = choices or {}
		refs.Option1.Visible = false
		refs.Option2.Visible = false
		if currentChoices[1] then
			refs.Option1.Text = currentChoices[1].Text or Config.ContinueText
			refs.Option1.Visible = true
		end
		if currentChoices[2] then
			refs.Option2.Text = currentChoices[2].Text or ""
			refs.Option2.Visible = true
		end
	end

	local function finishTypewriter()
		if not typing or not refs then
			return
		end
		cancelTypewriter(true)
		showChoices(currentChoices)
	end

	local function runTypewriter(text, choices)
		if not refs then
			return
		end
		cancelTypewriter(false)
		typingToken += 1
		local token = typingToken
		typing = true
		currentChoices = choices or {}
		hideChoices()
		currentChoices = choices or {}

		local label = refs.DialogueText
		label.Text = text or ""
		label.MaxVisibleGraphemes = 0
		local length = utf8.len(label.Text) or #label.Text
		if length <= 0 or Config.TypewriterSecondsPerCharacter <= 0 then
			label.MaxVisibleGraphemes = -1
			typing = false
			showChoices(currentChoices)
			return
		end

		task.spawn(function()
			for index = 1, length do
				if typingToken ~= token or not activeSessionId or not refs then
					return
				end
				label.MaxVisibleGraphemes = index
				playTypeSound(index)
				task.wait(Config.TypewriterSecondsPerCharacter)
			end
			if typingToken ~= token or not activeSessionId or not refs then
				return
			end
			typing = false
			label.MaxVisibleGraphemes = -1
			showChoices(currentChoices)
		end)
	end

	local function closePresentation(showWarning)
		cancelTypewriter(false)
		hideChoices()
		pendingChoice = false
		if not refs then
			restorePromptPresentation()
			return
		end
		cancelTween()
		local currentRefs = refs
		local token = transitionToken
		activeTween = TweenService:Create(
			currentRefs.Frame,
			TweenInfo.new(Config.CloseTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = offscreenPosition(currentRefs.OnScreenPosition) }
		)
		activeTween:Play()
		activeTween.Completed:Connect(function(playbackState)
			if playbackState ~= Enum.PlaybackState.Completed or transitionToken ~= token or refs ~= currentRefs then
				return
			end
			activeTween = nil
			currentRefs.Frame.Visible = false
			restorePromptPresentation()
			if showWarning and currentRefs.WarningText then
				warningToken += 1
				local warningSequence = warningToken
				currentRefs.WarningText.Text = Config.WalkedAwayWarningText
				currentRefs.WarningText.Visible = true
				task.delay(Config.WarningVisibleSeconds, function()
					if refs ~= currentRefs or warningToken ~= warningSequence then
						return
					end
					currentRefs.WarningText.Visible = false
					if activeSessionId == nil then
						currentRefs.Gui.Enabled = false
					end
				end)
			else
				currentRefs.Gui.Enabled = false
			end
		end)
	end

	local function openPresentation(payload)
		if not refs then
			return
		end
		warningToken += 1
		if refs.WarningText then
			refs.WarningText.Visible = false
		end
		cancelTween()
		local token = transitionToken
		refs.Gui.Enabled = true
		refs.Frame.Visible = true
		refs.Username.Text = payload.Speaker or ""
		refs.Frame.Position = offscreenPosition(refs.OnScreenPosition)
		activeTween = TweenService:Create(
			refs.Frame,
			TweenInfo.new(Config.OpenTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = refs.OnScreenPosition }
		)
		activeTween:Play()
		activeTween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed and transitionToken == token then
				activeTween = nil
			end
		end)
		runTypewriter(payload.Text, payload.Choices)
	end

	local function showNode(payload)
		if not refs then
			return
		end
		pendingChoice = false
		refs.Username.Text = payload.Speaker or refs.Username.Text
		runTypewriter(payload.Text, payload.Choices)
	end

	local function choose(index)
		if pendingChoice or activeSessionId == nil then
			return
		end
		if typing then
			finishTypewriter()
			return
		end
		local choice = currentChoices[index]
		if not choice or type(choice.Id) ~= "string" then
			return
		end
		pendingChoice = true
		hideChoices()
		remote:FireServer("Choose", activeSessionId, choice.Id)
	end

	local function unbindGui()
		disconnectConnections(guiConnections)
		cancelTween()
		cancelTypewriter(false)
		refs = nil
	end

	local function bindGui()
		unbindGui()
		refs = findGuiRefs(playerGui)
		if not refs then
			warn("[Pawlands Dialogue] Studio-owned DialogueGui hierarchy is missing required runtime anchors.")
			return false
		end
		refs.Gui.Enabled = false
		refs.Frame.Visible = false
		refs.Option1.Visible = false
		refs.Option2.Visible = false
		if refs.WarningText then
			refs.WarningText.Visible = false
		end

		table.insert(guiConnections, refs.Option1.Activated:Connect(function()
			choose(1)
		end))
		table.insert(guiConnections, refs.Option2.Activated:Connect(function()
			choose(2)
		end))
		return true
	end

	local function resetLocalSession()
		activeSessionId = nil
		pendingChoice = false
		cancelTypewriter(false)
		releaseInteraction(true)
		if refs then
			refs.Gui.Enabled = false
		end
	end

	bindGui()

	table.insert(connections, playerGui.ChildAdded:Connect(function(child)
		if child.Name == Config.GuiName then
			task.defer(bindGui)
		end
	end))
	table.insert(connections, playerGui.ChildRemoved:Connect(function(child)
		if refs and child == refs.Gui then
			if activeSessionId ~= nil then
				remote:FireServer("Close", activeSessionId)
			end
			resetLocalSession()
			unbindGui()
		end
	end))
	table.insert(connections, player.CharacterAdded:Connect(function()
		resetLocalSession()
	end))
	table.insert(connections, player.CharacterRemoving:Connect(function()
		resetLocalSession()
	end))
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or activeSessionId == nil then
			return
		end
		local advanceInput = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.E
			or input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.Return
			or input.KeyCode == Enum.KeyCode.ButtonA
		if not advanceInput then
			return
		end
		if typing then
			finishTypewriter()
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			choose(1)
		end
	end))
	table.insert(connections, remote.OnClientEvent:Connect(function(operation, sessionId, payload)
		if operation == "Open" then
			if not refs and not bindGui() then
				remote:FireServer("Close", sessionId)
				return
			end
			activeSessionId = sessionId
			pendingChoice = false
			engageInteraction(payload or {})
			openPresentation(payload or {})
		elseif operation == "Node" then
			if sessionId ~= activeSessionId then
				return
			end
			showNode(payload or {})
		elseif operation == "Close" then
			if sessionId ~= activeSessionId then
				return
			end
			activeSessionId = nil
			releaseInteraction(false)
			local reason = payload
			closePresentation(reason == "WalkedAway")
		end
	end))

	stopCurrent = function()
		if activeSessionId ~= nil then
			remote:FireServer("Close", activeSessionId)
		end
		activeSessionId = nil
		releaseInteraction(true)
		disconnectConnections(connections)
		unbindGui()
	end
end

function DialogueController.Stop()
	if stopCurrent then
		local stop = stopCurrent
		stopCurrent = nil
		stop()
	end
end

return DialogueController
