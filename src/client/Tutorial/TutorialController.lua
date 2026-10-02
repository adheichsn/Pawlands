local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Pawlands = ReplicatedStorage:WaitForChild("Pawlands")
local Shared = Pawlands:WaitForChild("Shared")
local TutorialConfig = require(Shared.Config.Tutorial)
local DialogueConfig = require(Shared.Config.Dialogue)
local InteractionLock = require(script.Parent.Parent.Interaction.InteractionLock)
local TextNotificationController = require(script.Parent.Parent.Notifications.TextNotificationController)

local TutorialController = {}
local player = Players.LocalPlayer
local started = false
local connections = {}
local heartbeatConnection = nil
local refs = nil
local accumulator = 0
local warnedMissing = false
local lastReportedInputMode = nil
local inputRemote = nil

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function descendantsByName(root, name)
	local matches = {}
	for _, item in ipairs(root:GetDescendants()) do
		if item.Name == name then
			table.insert(matches, item)
		end
	end
	return matches
end

local function findBestQuest(inside)
	local best, bestScore = nil, -1
	for _, item in ipairs(descendantsByName(inside, "Quest")) do
		if item:IsA("Frame") then
			local score = 0
			for _, anchor in ipairs({ "Objective", "BarFrame", "Progress", "Option", "ItemName", "Prefix", "Header" }) do
				if item:FindFirstChild(anchor, true) then
					score += 1
				end
			end
			if score > bestScore then
				best = item
				bestScore = score
			end
		end
	end
	return best
end

local function findText(root, name)
	local item = root and root:FindFirstChild(name, true)
	return item and (item:IsA("TextLabel") or item:IsA("TextButton")) and item or nil
end

local function findFirstText(root)
	if not root then
		return nil
	end
	if root:IsA("TextLabel") or root:IsA("TextButton") then
		return root
	end
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			return item
		end
	end
	return nil
end

local function resolveRefs()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild(TutorialConfig.QuestGuiName)
	if not gui or not gui:IsA("ScreenGui") then
		return nil
	end

	-- The current Studio tracker keeps Inside directly under its presentation tree,
	-- while older authored versions used List > Inside. Resolve either layout.
	local inside = gui:FindFirstChild("Inside", true)
	if not inside or not inside:IsA("GuiObject") then
		return nil
	end

	local quest = findBestQuest(inside)
	if not quest then
		return nil
	end

	local objective = quest:FindFirstChild("Objective", true)
	local barFrame = objective and objective:FindFirstChild("BarFrame", true)
	local bg = barFrame and barFrame:FindFirstChild("BG")
	local bar = barFrame and barFrame:FindFirstChild("Bar")
	local progress = findText(quest, "Progress")
	local itemName = findText(quest, "ItemName")
	local prefix = findText(quest, "Prefix")
	local suffix = findText(quest, "Suffix")
	local extra = findText(quest, "Extra")

	local header = nil
	local top = quest:FindFirstChild("Top")
	local topFrame = top and top:FindFirstChild("TopFrame")
	if topFrame then
		header = findText(topFrame, "Header") or findFirstText(topFrame)
	end
	if not header then
		header = findText(quest, "Header")
	end
	if not header then
		local option = quest:FindFirstChild("Option")
		local optionContent = option and option:FindFirstChild("Content")
		header = findFirstText(optionContent)
	end

	local objectiveLabel = nil
	if objective then
		local objectiveContent = objective:FindFirstChild("Content")
		objectiveLabel = findFirstText(objectiveContent)
	end

	local hasSplitObjective = prefix ~= nil and itemName ~= nil
	if not header or (not hasSplitObjective and not objectiveLabel) then
		return nil
	end

	return {
		Gui = gui,
		Inside = inside,
		Quest = quest,
		Header = header,
		Prefix = prefix,
		ItemName = itemName,
		ObjectiveLabel = objectiveLabel,
		Suffix = suffix,
		Progress = progress,
		Extra = extra,
		Bar = bar and bar:IsA("GuiObject") and bar or nil,
		BarFullWidth = bg and bg:IsA("GuiObject") and bg.Size.X
			or (bar and bar:IsA("GuiObject") and UDim.new(1, 0) or nil),
	}
end

local function prepareAuthoredTracker(current)
	for _, item in ipairs(descendantsByName(current.Inside, "Quest")) do
		if item:IsA("Frame") and item ~= current.Quest then
			item.Visible = false
		end
	end
	for _, name in ipairs({ "TOP", "EventFrame", "DIV" }) do
		for _, item in ipairs(current.Inside:GetChildren()) do
			if item.Name == name and item:IsA("GuiObject") then
				item.Visible = false
			end
		end
	end
	local dropdown = current.Quest:FindFirstChild("Dropdown", true)
	if dropdown and dropdown:IsA("GuiObject") then
		dropdown.Visible = false
	end
	local questionButton = current.Quest:FindFirstChild("QuestionButton", true)
	if questionButton and questionButton:IsA("GuiObject") then
		questionButton.Visible = false
	end
	if current.Suffix then
		current.Suffix.Visible = false
	end
	if current.Extra then
		current.Extra.Visible = false
	end
	current.Quest.Visible = true
end

local function stageOf()
	local stage = player:GetAttribute(TutorialConfig.StageAttributeName)
	if type(stage) ~= "string" then
		return TutorialConfig.Stages.LearnMove
	end
	return stage
end

local function currentInputMode(lastInputType)
	lastInputType = lastInputType or UserInputService:GetLastInputType()
	if lastInputType == Enum.UserInputType.Touch then
		return TutorialConfig.InputModes.Touch
	end
	if string.find(lastInputType.Name, "Gamepad", 1, true) then
		return TutorialConfig.InputModes.Gamepad
	end
	if UserInputService.KeyboardEnabled then
		return TutorialConfig.InputModes.Keyboard
	end
	if UserInputService.GamepadEnabled then
		return TutorialConfig.InputModes.Gamepad
	end
	if UserInputService.TouchEnabled then
		return TutorialConfig.InputModes.Touch
	end
	return TutorialConfig.InputModes.Keyboard
end

local function reportInputMode(inputType)
	if not inputRemote then
		return
	end
	local mode = currentInputMode(inputType)
	if mode == lastReportedInputMode then
		return
	end
	lastReportedInputMode = mode
	inputRemote:FireServer(mode)
end

local function dialogueActive()
	return player:GetAttribute(DialogueConfig.ActiveAttributeName) == true
		or InteractionLock.IsLocked("Dialogue")
end

local function renderGuidance()
	-- Inventory keeps locomotion available, but generic FTUE movement/sprint/combat
	-- hints should not sit on top of the modal. Dedicated contextual Inventory cues
	-- use TutorialCueController and are intentionally unaffected by this suppression.
	if dialogueActive() or InteractionLock.IsLocked("Inventory") then
		TextNotificationController.Clear(TutorialConfig.NotificationKey)
		return
	end
	local stage = stageOf()
	local inputMode = currentInputMode()
	local text = nil
	if stage == TutorialConfig.Stages.LearnMove then
		if inputMode == TutorialConfig.InputModes.Touch then
			text = TutorialConfig.MoveHintTouch
		elseif inputMode == TutorialConfig.InputModes.Gamepad then
			text = TutorialConfig.MoveHintGamepad
		else
			text = TutorialConfig.MoveHintKeyboard
		end
	elseif stage == TutorialConfig.Stages.LearnSprint then
		if inputMode == TutorialConfig.InputModes.Gamepad then
			text = TutorialConfig.SprintHintGamepad
		elseif inputMode == TutorialConfig.InputModes.Keyboard then
			text = TutorialConfig.SprintHintKeyboard
		end
	elseif stage == TutorialConfig.Stages.LearnAttack then
		if inputMode == TutorialConfig.InputModes.Touch then
			text = TutorialConfig.CombatHintTouch
		elseif inputMode == TutorialConfig.InputModes.Gamepad then
			text = TutorialConfig.CombatHintGamepad
		else
			text = TutorialConfig.CombatHintKeyboard
		end
	end
	if text then
		TextNotificationController.ShowText(TutorialConfig.NotificationKey, text)
	else
		TextNotificationController.Clear(TutorialConfig.NotificationKey)
	end
end

local function setObjectiveText(prefix, item)
	if not refs then
		return
	end
	if refs.Prefix and refs.ItemName then
		refs.Prefix.Text = prefix
		refs.ItemName.Text = item
	elseif refs.ObjectiveLabel then
		refs.ObjectiveLabel.Text = string.format("%s %s", prefix, item)
	end
end

local function setBar(alpha)
	if not refs or not refs.Bar or not refs.BarFullWidth then
		return
	end
	alpha = math.clamp(alpha, 0, 1)
	local fullWidth = refs.BarFullWidth
	local currentSize = refs.Bar.Size
	refs.Bar.Size = UDim2.new(
		fullWidth.Scale * alpha,
		math.floor(fullWidth.Offset * alpha),
		currentSize.Y.Scale,
		currentSize.Y.Offset
	)
end

local function renderTracker()
	if not refs or not refs.Gui.Parent then
		refs = resolveRefs()
		if refs then
			prepareAuthoredTracker(refs)
		end
	end
	if not refs then
		return
	end

	local stage = stageOf()
	local visible = not dialogueActive() and (
		stage == TutorialConfig.Stages.MeetAlex
		or stage == TutorialConfig.Stages.GoToZone
		or stage == TutorialConfig.Stages.LearnAttack
		or stage == TutorialConfig.Stages.InCombat
		or stage == TutorialConfig.Stages.ReturnToAlex
		or stage == TutorialConfig.Stages.EquipStarterPet
	)
	refs.Gui.Enabled = visible
	if not visible then
		return
	end

	refs.Header.Text = TutorialConfig.QuestTitle
	if stage == TutorialConfig.Stages.MeetAlex then
		setObjectiveText(TutorialConfig.MeetAlexPrefix, TutorialConfig.MeetAlexItem)
		if refs.Progress then
			refs.Progress.Visible = false
		end
		setBar(0)
	elseif stage == TutorialConfig.Stages.GoToZone then
		setObjectiveText(TutorialConfig.GoToZonePrefix, TutorialConfig.GoToZoneItem)
		if refs.Progress then
			refs.Progress.Visible = false
		end
		setBar(0)
	elseif stage == TutorialConfig.Stages.LearnAttack or stage == TutorialConfig.Stages.InCombat then
		local current = math.max(0, tonumber(player:GetAttribute(TutorialConfig.ProgressAttributeName)) or 0)
		local goal = math.max(1, tonumber(player:GetAttribute(TutorialConfig.GoalAttributeName)) or 1)
		setObjectiveText(TutorialConfig.CombatPrefix, TutorialConfig.CombatItem)
		if refs.Progress then
			refs.Progress.Text = string.format("%d / %d", math.min(current, goal), goal)
			refs.Progress.Visible = true
		end
		setBar(current / goal)
	elseif stage == TutorialConfig.Stages.ReturnToAlex then
		setObjectiveText(TutorialConfig.ReturnPrefix, TutorialConfig.ReturnItem)
		if refs.Progress then
			refs.Progress.Visible = false
		end
		setBar(1)
	elseif stage == TutorialConfig.Stages.EquipStarterPet then
		setObjectiveText(TutorialConfig.EquipStarterPrefix, TutorialConfig.EquipStarterItem)
		if refs.Progress then
			refs.Progress.Visible = false
		end
		setBar(0)
	end
end

local function render()
	renderTracker()
	renderGuidance()
end

local function bindPlayerGui()
	local playerGui = player:WaitForChild("PlayerGui")
	table.insert(connections, playerGui.ChildAdded:Connect(function(child)
		if child.Name == TutorialConfig.QuestGuiName then
			refs = nil
			task.defer(render)
		elseif child.Name == "TextNotifications" then
			task.defer(renderGuidance)
		end
	end))
	table.insert(connections, playerGui.DescendantAdded:Connect(function(descendant)
		if refs then
			return
		end
		local questGui = playerGui:FindFirstChild(TutorialConfig.QuestGuiName)
		if questGui and descendant:IsDescendantOf(questGui) then
			task.defer(renderTracker)
		end
	end))
end

function TutorialController.Start()
	if started then
		return
	end
	started = true
	inputRemote = Pawlands:WaitForChild(TutorialConfig.RemoteFolderName):WaitForChild(TutorialConfig.InputModeRemoteName)
	bindPlayerGui()
	for _, attributeName in ipairs({
		TutorialConfig.StageAttributeName,
		TutorialConfig.ProgressAttributeName,
		TutorialConfig.GoalAttributeName,
		DialogueConfig.ActiveAttributeName,
	}) do
		table.insert(connections, player:GetAttributeChangedSignal(attributeName):Connect(render))
	end
	table.insert(connections, UserInputService.LastInputTypeChanged:Connect(function(inputType)
		reportInputMode(inputType)
		renderGuidance()
	end))
	reportInputMode()
	task.delay(3, function()
		if not started or refs then
			return
		end
		refs = resolveRefs()
		if refs then
			prepareAuthoredTracker(refs)
			renderTracker()
		elseif not warnedMissing then
			warnedMissing = true
			warn("[Pawlands Tutorial] Studio-owned QuestTracker hierarchy is missing required runtime anchors after replication grace.")
		end
	end)
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.10 then
			accumulator = 0
			render()
		end
	end)
	render()
end

function TutorialController.Stop()
	if not started then
		return
	end
	started = false
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	disconnectAll()
	TextNotificationController.Clear(TutorialConfig.NotificationKey)
	if refs and refs.Gui and refs.Gui.Parent then
		refs.Gui.Enabled = false
	end
	refs = nil
	inputRemote = nil
	lastReportedInputMode = nil
	accumulator = 0
end

return TutorialController
