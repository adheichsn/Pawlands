local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local TutorialConfig = require(Shared.Config.Tutorial)
local InteractionLock = require(script.Parent.Parent.Interaction.InteractionLock)

local TutorialCueController = {}

local player = Players.LocalPlayer
local random = Random.new()
local started = false
local connections = {}
local unsubscribeLock = nil
local refs = nil
local authoredGuiEnabled = nil
local activeCue = nil
local activeMode = nil
local generation = 0
local scheduled = false
local lastSlotIndex = nil
local warnedMissing = false

-- Positions are intentionally bounded inside the Studio-authored SafeBounds rather
-- than randomized across the whole viewport. This keeps the cue clear of Roblox
-- chrome and the usual mobile control corners while still feeling slightly random.
local KEYBOARD_SLOTS = table.freeze({
	Vector2.new(0.28, 0.28),
	Vector2.new(0.50, 0.24),
	Vector2.new(0.72, 0.30),
	Vector2.new(0.26, 0.50),
	Vector2.new(0.52, 0.46),
	Vector2.new(0.74, 0.50),
	Vector2.new(0.38, 0.70),
	Vector2.new(0.64, 0.68),
})

local TOUCH_SLOTS = table.freeze({
	Vector2.new(0.32, 0.26),
	Vector2.new(0.50, 0.24),
	Vector2.new(0.68, 0.28),
	Vector2.new(0.30, 0.44),
	Vector2.new(0.52, 0.42),
	Vector2.new(0.70, 0.46),
	Vector2.new(0.38, 0.62),
	Vector2.new(0.62, 0.60),
})

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	if unsubscribeLock then
		unsubscribeLock()
		unsubscribeLock = nil
	end
end

local function resolveRefs()
	if refs
		and refs.Gui.Parent
		and refs.SafeBounds.Parent
		and refs.ClickTemplate.Parent
		and refs.TapTemplate.Parent
	then
		return refs
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local cueConfig = TutorialConfig.Cue
	local gui = playerGui and playerGui:FindFirstChild(cueConfig.GuiName)
	if not gui or not gui:IsA("ScreenGui") then
		refs = nil
		return nil
	end

	local safeBounds = gui:FindFirstChild(cueConfig.SafeBoundsName, true)
	if not safeBounds or not safeBounds:IsA("GuiObject") then
		refs = nil
		return nil
	end

	local clickTemplate = safeBounds:FindFirstChild(cueConfig.ClickTemplateName)
	local tapTemplate = safeBounds:FindFirstChild(cueConfig.TapTemplateName)
	if not clickTemplate or not clickTemplate:IsA("GuiObject")
		or not tapTemplate or not tapTemplate:IsA("GuiObject")
	then
		refs = nil
		return nil
	end

	local function validateTemplate(template)
		local icon = template:FindFirstChild("Icon", true)
		local pulseScale = template:FindFirstChild("PulseScale", true)
		return icon and icon:IsA("ImageLabel")
			and pulseScale and pulseScale:IsA("UIScale")
	end
	if not validateTemplate(clickTemplate) or not validateTemplate(tapTemplate) then
		refs = nil
		return nil
	end

	if refs == nil or refs.Gui ~= gui then
		authoredGuiEnabled = gui.Enabled
	end

	clickTemplate.Visible = false
	tapTemplate.Visible = false
	for _, child in ipairs(safeBounds:GetChildren()) do
		if child ~= activeCue
			and child:IsA("GuiObject")
			and string.sub(child.Name, 1, 8) == "Runtime_"
		then
			child:Destroy()
		end
	end

	refs = {
		Gui = gui,
		SafeBounds = safeBounds,
		ClickTemplate = clickTemplate,
		TapTemplate = tapTemplate,
	}
	return refs
end

local function currentCueMode()
	local inputType = UserInputService:GetLastInputType()
	if inputType == Enum.UserInputType.Touch then
		return TutorialConfig.InputModes.Touch
	end
	if string.find(inputType.Name, "Gamepad", 1, true) then
		-- This stage currently has Studio-authored Mouse and Tap art only. The text
		-- guidance still teaches RT on gamepad; a dedicated gamepad cue can be added
		-- later without pretending the mouse art is a controller prompt.
		return nil
	end
	if UserInputService.KeyboardEnabled or UserInputService.MouseEnabled then
		return TutorialConfig.InputModes.Keyboard
	end
	if UserInputService.TouchEnabled then
		return TutorialConfig.InputModes.Touch
	end
	return nil
end

local function playerAlive()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function eligibleMode()
	if player:GetAttribute(TutorialConfig.StageAttributeName) ~= TutorialConfig.Stages.LearnAttack then
		return nil
	end
	if InteractionLock.IsLocked() or not playerAlive() then
		return nil
	end
	return currentCueMode()
end

local function restoreGuiState()
	if refs and refs.Gui and refs.Gui.Parent and authoredGuiEnabled ~= nil then
		refs.Gui.Enabled = authoredGuiEnabled
	end
end

local function clearCue()
	generation += 1
	scheduled = false
	activeMode = nil
	lastSlotIndex = nil
	if activeCue then
		activeCue:Destroy()
		activeCue = nil
	end
	restoreGuiState()
end

local function pickPosition(mode)
	local slots = mode == TutorialConfig.InputModes.Touch and TOUCH_SLOTS or KEYBOARD_SLOTS
	local index
	if #slots <= 1 then
		index = 1
	else
		repeat
			index = random:NextInteger(1, #slots)
		until index ~= lastSlotIndex
	end
	lastSlotIndex = index
	local point = slots[index]
	return UDim2.fromScale(point.X, point.Y)
end

local function tokenActive(token, cue, mode)
	return started
		and token == generation
		and activeCue == cue
		and cue ~= nil
		and cue.Parent ~= nil
		and eligibleMode() == mode
end

local function tweenAndWait(token, cue, mode, instance, duration, easingStyle, easingDirection, goals)
	if not tokenActive(token, cue, mode) then
		return false
	end
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle, easingDirection),
		goals
	)
	tween:Play()
	local deadline = os.clock() + duration
	while os.clock() < deadline do
		if not tokenActive(token, cue, mode) then
			tween:Cancel()
			return false
		end
		task.wait(math.min(0.04, math.max(0, deadline - os.clock())))
	end
	return tokenActive(token, cue, mode)
end

local function waitWhileActive(token, cue, mode, duration)
	local deadline = os.clock() + duration
	while os.clock() < deadline do
		if not tokenActive(token, cue, mode) then
			return false
		end
		task.wait(math.min(0.05, math.max(0, deadline - os.clock())))
	end
	return tokenActive(token, cue, mode)
end

local function runAnimation(token, cue, mode)
	local cueConfig = TutorialConfig.Cue
	local icon = cue:FindFirstChild("Icon", true)
	local pulseScale = cue:FindFirstChild("PulseScale", true)
	if not icon or not icon:IsA("ImageLabel") or not pulseScale or not pulseScale:IsA("UIScale") then
		clearCue()
		return
	end

	local authoredTransparency = icon.ImageTransparency
	local authoredScale = pulseScale.Scale
	cue.Position = pickPosition(mode)
	cue.Rotation = 0
	pulseScale.Scale = authoredScale * cueConfig.IntroScale
	icon.ImageTransparency = 1
	cue.Visible = true

	if not tweenAndWait(
		token,
		cue,
		mode,
		pulseScale,
		cueConfig.IntroSeconds,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out,
		{ Scale = authoredScale * cueConfig.PulseUpScale }
	) then
		return
	end
	if not tweenAndWait(
		token,
		cue,
		mode,
		icon,
		cueConfig.FadeSeconds,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		{ ImageTransparency = authoredTransparency }
	) then
		return
	end
	if not tweenAndWait(
		token,
		cue,
		mode,
		pulseScale,
		cueConfig.SettleSeconds,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		{ Scale = authoredScale }
	) then
		return
	end

	while tokenActive(token, cue, mode) do
		if not waitWhileActive(token, cue, mode, cueConfig.PulseRestSeconds) then
			return
		end
		if not tweenAndWait(
			token,
			cue,
			mode,
			pulseScale,
			cueConfig.PressSeconds,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In,
			{ Scale = authoredScale * cueConfig.PulseDownScale }
		) then
			return
		end
		if not tweenAndWait(
			token,
			cue,
			mode,
			pulseScale,
			cueConfig.PopSeconds,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out,
			{ Scale = authoredScale * cueConfig.PulseUpScale }
		) then
			return
		end
		if not tweenAndWait(
			token,
			cue,
			mode,
			pulseScale,
			cueConfig.SettleSeconds,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out,
			{ Scale = authoredScale }
		) then
			return
		end
		if not waitWhileActive(token, cue, mode, cueConfig.RelocateHoldSeconds) then
			return
		end
		if not tweenAndWait(
			token,
			cue,
			mode,
			icon,
			cueConfig.FadeSeconds,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In,
			{ ImageTransparency = 1 }
		) then
			return
		end
		cue.Position = pickPosition(mode)
		pulseScale.Scale = authoredScale * cueConfig.IntroScale
		if not tweenAndWait(
			token,
			cue,
			mode,
			icon,
			cueConfig.FadeSeconds,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out,
			{ ImageTransparency = authoredTransparency }
		) then
			return
		end
		if not tweenAndWait(
			token,
			cue,
			mode,
			pulseScale,
			cueConfig.IntroSeconds,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out,
			{ Scale = authoredScale }
		) then
			return
		end
	end
end

local function showCue(mode)
	local current = resolveRefs()
	if not current then
		return false
	end
	local template = mode == TutorialConfig.InputModes.Touch
		and current.TapTemplate
		or current.ClickTemplate
	local cue = template:Clone()
	cue.Name = TutorialConfig.Cue.RuntimeName
	cue.Visible = false
	activeCue = cue
	activeMode = mode
	cue.Parent = current.SafeBounds
	current.Gui.Enabled = true
	local token = generation
	task.spawn(runAnimation, token, cue, mode)
	return true
end

local function refresh()
	if not started then
		return
	end
	local mode = eligibleMode()
	if not mode then
		if activeCue or scheduled then
			clearCue()
		end
		return
	end

	if activeCue then
		if activeMode ~= mode then
			clearCue()
		else
			return
		end
	end
	if scheduled then
		return
	end

	scheduled = true
	generation += 1
	local token = generation
	task.delay(TutorialConfig.Cue.InitialDelaySeconds, function()
		if not started or token ~= generation then
			return
		end
		scheduled = false
		local currentMode = eligibleMode()
		if currentMode ~= mode then
			refresh()
			return
		end
		if not showCue(mode) then
			-- PlayerGui descendants can replicate a little after the ScreenGui itself.
			-- Keep this optional presentation layer silent and let DescendantAdded retry.
			return
		end
	end)
end

local function bindCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid then
		table.insert(connections, humanoid.Died:Connect(refresh))
	end
	task.defer(refresh)
end

function TutorialCueController.Start()
	if started then
		return
	end
	started = true

	local playerGui = player:WaitForChild("PlayerGui")
	table.insert(connections, player:GetAttributeChangedSignal(TutorialConfig.StageAttributeName):Connect(refresh))
	table.insert(connections, UserInputService.LastInputTypeChanged:Connect(refresh))
	table.insert(connections, player.CharacterAdded:Connect(bindCharacter))
	table.insert(connections, player.CharacterRemoving:Connect(refresh))
	table.insert(connections, playerGui.ChildAdded:Connect(function(child)
		if child.Name == TutorialConfig.Cue.GuiName then
			refs = nil
			authoredGuiEnabled = nil
			task.defer(refresh)
		end
	end))
	table.insert(connections, playerGui.DescendantAdded:Connect(function(descendant)
		if activeCue and (descendant == activeCue or descendant:IsDescendantOf(activeCue)) then
			return
		end
		if descendant.Name == TutorialConfig.Cue.ClickTemplateName
			or descendant.Name == TutorialConfig.Cue.TapTemplateName
			or descendant.Name == "Icon"
			or descendant.Name == "PulseScale"
		then
			refs = nil
			task.defer(refresh)
		end
	end))
	unsubscribeLock = InteractionLock.Subscribe(function()
		refresh()
	end)

	if player.Character then
		bindCharacter(player.Character)
	end

	task.delay(3, function()
		if not started or resolveRefs() or warnedMissing then
			return
		end
		warnedMissing = true
		warn("[Pawlands Tutorial] Studio-owned TutorialCues hierarchy is missing required runtime anchors after replication grace.")
	end)
	refresh()
end

function TutorialCueController.Stop()
	if not started then
		return
	end
	started = false
	clearCue()
	disconnectAll()
	refs = nil
	authoredGuiEnabled = nil
	warnedMissing = false
end

return TutorialCueController
