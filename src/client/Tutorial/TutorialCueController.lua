local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local TutorialConfig = require(Shared.Config.Tutorial)
local InventoryConfig = require(Shared.Config.Inventory)
local InteractionLock = require(script.Parent.Parent.Interaction.InteractionLock)

local TutorialCueController = {}

local player = Players.LocalPlayer
local random = Random.new()
local started = false
local connections = {}
local unsubscribeLock = nil
local refs = nil
local authoredGuiEnabled = nil
local authoredGuiDisplayOrder = nil
local activeCue = nil
local activeMode = nil
local activeContextKey = nil
local activeTarget = nil
local generation = 0
local scheduled = false
local scheduledMode = nil
local scheduledContextKey = nil
local scheduledTarget = nil
local equipStageEnteredAt = nil
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
		authoredGuiDisplayOrder = gui.DisplayOrder
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
		-- The Studio-authored cue set currently has Mouse and Tap art only. A dedicated
		-- gamepad cue can be added later without pretending mouse art is a controller
		-- prompt.
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

local function resolveInventoryButton()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild(InventoryConfig.HudGuiName)
	if not hud or not hud:IsA("ScreenGui") or not hud.Enabled then
		return nil
	end
	local hudRoot = hud:FindFirstChild(InventoryConfig.HudRootName)
	local leftSide = hudRoot and hudRoot:FindFirstChild(InventoryConfig.HudLeftSideName)
	local row = leftSide and leftSide:FindFirstChild(InventoryConfig.HudRowName)
	local button = row and row:FindFirstChild(InventoryConfig.HudInventoryButtonName)
	return button and button:IsA("GuiObject") and button.Visible and button or nil
end

local function resolveStarterPetTile(starterUid)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local inventoryGui = playerGui and playerGui:FindFirstChild(InventoryConfig.GuiName)
	if not inventoryGui or not inventoryGui:IsA("ScreenGui") or not inventoryGui.Enabled then
		return nil
	end

	local tile = inventoryGui:FindFirstChild(InventoryConfig.RuntimePetTilePrefix .. starterUid, true)
	if tile and tile:IsA("GuiObject") and tile.Visible then
		return tile
	end
	return nil
end

local function updateEquipStageTimer()
	local stage = player:GetAttribute(TutorialConfig.StageAttributeName)
	if stage == TutorialConfig.Stages.EquipStarterPet then
		if equipStageEnteredAt == nil then
			equipStageEnteredAt = os.clock()
		end
	else
		equipStageEnteredAt = nil
	end
end

local function eligibleContext()
	local mode = currentCueMode()
	if not mode or not playerAlive() then
		return nil
	end

	local stage = player:GetAttribute(TutorialConfig.StageAttributeName)
	if stage == TutorialConfig.Stages.LearnAttack then
		if InteractionLock.IsLocked() then
			return nil
		end
		return {
			Mode = mode,
			Kind = "WorldAttack",
			Key = "WorldAttack",
			Target = nil,
		}
	end

	if stage ~= TutorialConfig.Stages.EquipStarterPet
		or InteractionLock.IsLockedExcept("Inventory")
	then
		return nil
	end

	local starterUid = player:GetAttribute(TutorialConfig.StarterPetUidAttributeName)
	if type(starterUid) ~= "string" or starterUid == "" then
		return nil
	end

	if InteractionLock.IsLocked("Inventory") then
		local tile = resolveStarterPetTile(starterUid)
		if not tile then
			return nil
		end
		return {
			Mode = mode,
			Kind = "StarterPetTile",
			Key = "StarterPetTile:" .. starterUid,
			Target = tile,
		}
	end

	local inventoryButton = resolveInventoryButton()
	if not inventoryButton then
		return nil
	end
	return {
		Mode = mode,
		Kind = "InventoryButton",
		Key = "InventoryButton:" .. starterUid,
		Target = inventoryButton,
	}
end

local function cueDelay(context)
	if context.Kind ~= "WorldAttack" then
		local startedAt = equipStageEnteredAt or os.clock()
		return math.max(
			0,
			TutorialConfig.Cue.EquipStarterInitialDelaySeconds - (os.clock() - startedAt)
		)
	end
	return TutorialConfig.Cue.InitialDelaySeconds
end

local function restoreGuiState()
	if refs and refs.Gui and refs.Gui.Parent then
		if authoredGuiEnabled ~= nil then
			refs.Gui.Enabled = authoredGuiEnabled
		end
		if authoredGuiDisplayOrder ~= nil then
			refs.Gui.DisplayOrder = authoredGuiDisplayOrder
		end
	end
end

local function screenGuiAncestor(instance)
	local current = instance
	while current do
		if current:IsA("ScreenGui") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function syncAnchoredGuiLayer(current)
	if not current or not current.Gui or not current.Gui.Parent then
		return
	end

	local displayOrder = authoredGuiDisplayOrder or current.Gui.DisplayOrder
	if activeTarget then
		local targetGui = screenGuiAncestor(activeTarget)
		if targetGui and targetGui ~= current.Gui then
			displayOrder = math.max(displayOrder, targetGui.DisplayOrder + 1)
		end
	end
	current.Gui.DisplayOrder = displayOrder
end

local function clearCue()
	generation += 1
	scheduled = false
	scheduledMode = nil
	scheduledContextKey = nil
	scheduledTarget = nil
	activeMode = nil
	activeContextKey = nil
	activeTarget = nil
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
	local context = eligibleContext()
	return started
		and token == generation
		and activeCue == cue
		and cue ~= nil
		and cue.Parent ~= nil
		and context ~= nil
		and context.Mode == mode
		and context.Key == activeContextKey
		and context.Target == activeTarget
end

local function updateAnchoredPosition(cue)
	if not activeTarget then
		return true
	end
	local current = resolveRefs()
	if not current or not activeTarget.Parent or not activeTarget.Visible then
		return false
	end

	syncAnchoredGuiLayer(current)

	local boundsSize = current.SafeBounds.AbsoluteSize
	if boundsSize.X <= 0 or boundsSize.Y <= 0 then
		return false
	end

	local icon = cue:FindFirstChild("Icon", true)
	if not icon or not icon:IsA("GuiObject") then
		return false
	end

	local targetCenter = activeTarget.AbsolutePosition + (activeTarget.AbsoluteSize * 0.5)
	local cueAnchorScreen = cue.AbsolutePosition + Vector2.new(
		cue.AbsoluteSize.X * cue.AnchorPoint.X,
		cue.AbsoluteSize.Y * cue.AnchorPoint.Y
	)
	local iconCenter = icon.AbsolutePosition + (icon.AbsoluteSize * 0.5)
	local iconOffsetFromCueAnchor = iconCenter - cueAnchorScreen
	local desiredCueAnchor = targetCenter - iconOffsetFromCueAnchor
	local localAnchor = desiredCueAnchor - current.SafeBounds.AbsolutePosition

	cue.Position = UDim2.fromOffset(
		math.clamp(math.floor(localAnchor.X + 0.5), 0, math.floor(boundsSize.X)),
		math.clamp(math.floor(localAnchor.Y + 0.5), 0, math.floor(boundsSize.Y))
	)
	return true
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
		if not tokenActive(token, cue, mode) or not updateAnchoredPosition(cue) then
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
		if not tokenActive(token, cue, mode) or not updateAnchoredPosition(cue) then
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
	if activeTarget then
		if not updateAnchoredPosition(cue) then
			return
		end
	else
		cue.Position = pickPosition(mode)
	end
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
		if not activeTarget then
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
end

local function showCue(context)
	local current = resolveRefs()
	if not current then
		return false
	end
	local mode = context.Mode
	local template = mode == TutorialConfig.InputModes.Touch
		and current.TapTemplate
		or current.ClickTemplate
	local cue = template:Clone()
	cue.Name = context.Kind == "WorldAttack"
		and TutorialConfig.Cue.RuntimeName
		or TutorialConfig.Cue.EquipRuntimeName
	cue.Visible = false
	activeCue = cue
	activeMode = mode
	activeContextKey = context.Key
	activeTarget = context.Target
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
	local context = eligibleContext()
	if not context then
		if activeCue or scheduled then
			clearCue()
		end
		return
	end

	if activeCue and not activeCue.Parent then
		clearCue()
	end

	if activeCue then
		if activeMode ~= context.Mode
			or activeContextKey ~= context.Key
			or activeTarget ~= context.Target
		then
			clearCue()
		else
			return
		end
	end

	if scheduled then
		if scheduledMode == context.Mode
			and scheduledContextKey == context.Key
			and scheduledTarget == context.Target
		then
			return
		end
		clearCue()
	end

	scheduled = true
	scheduledMode = context.Mode
	scheduledContextKey = context.Key
	scheduledTarget = context.Target
	generation += 1
	local token = generation
	local delaySeconds = cueDelay(context)
	task.delay(delaySeconds, function()
		if not started or token ~= generation then
			return
		end
		scheduled = false
		scheduledMode = nil
		scheduledContextKey = nil
		scheduledTarget = nil

		local current = eligibleContext()
		if not current
			or current.Mode ~= context.Mode
			or current.Key ~= context.Key
			or current.Target ~= context.Target
		then
			refresh()
			return
		end

		if not showCue(current) then
			-- PlayerGui descendants can replicate a little after the ScreenGui itself.
			-- Keep this optional presentation layer silent and let UI replication retry.
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
	updateEquipStageTimer()
	table.insert(connections, player:GetAttributeChangedSignal(TutorialConfig.StageAttributeName):Connect(function()
		updateEquipStageTimer()
		refresh()
	end))
	table.insert(connections, player:GetAttributeChangedSignal(TutorialConfig.StarterPetUidAttributeName):Connect(refresh))
	table.insert(connections, UserInputService.LastInputTypeChanged:Connect(refresh))
	table.insert(connections, player.CharacterAdded:Connect(bindCharacter))
	table.insert(connections, player.CharacterRemoving:Connect(refresh))
	table.insert(connections, playerGui.ChildAdded:Connect(function(child)
		if child.Name == TutorialConfig.Cue.GuiName then
			refs = nil
			authoredGuiEnabled = nil
			authoredGuiDisplayOrder = nil
			task.defer(refresh)
		elseif child.Name == InventoryConfig.GuiName or child.Name == InventoryConfig.HudGuiName then
			task.defer(refresh)
		end
	end))
	table.insert(connections, playerGui.ChildRemoved:Connect(function(child)
		if child.Name == TutorialConfig.Cue.GuiName then
			clearCue()
			refs = nil
			authoredGuiEnabled = nil
			authoredGuiDisplayOrder = nil
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
			return
		end

		if descendant.Name == InventoryConfig.HudInventoryButtonName
			or string.sub(descendant.Name, 1, #InventoryConfig.RuntimePetTilePrefix)
				== InventoryConfig.RuntimePetTilePrefix
		then
			task.defer(refresh)
		end
	end))
	table.insert(connections, playerGui.DescendantRemoving:Connect(function(descendant)
		if activeTarget
			and (descendant == activeTarget or descendant:IsAncestorOf(activeTarget))
		then
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
	authoredGuiDisplayOrder = nil
	equipStageEnteredAt = nil
	warnedMissing = false
end

return TutorialCueController
