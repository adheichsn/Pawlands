local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Pawlands = ReplicatedStorage:WaitForChild("Pawlands")
local Shared = Pawlands:WaitForChild("Shared")
local TutorialConfig = require(Shared.Config.Tutorial)
local DialogueConfig = require(Shared.Config.Dialogue)
local PetCatalog = require(Shared.Config.PetCatalog)
local PetRarityCatalog = require(Shared.Config.PetRarityCatalog)
local InteractionLock = require(script.Parent.Parent.Interaction.InteractionLock)
local TextNotificationController = require(script.Parent.Parent.Notifications.TextNotificationController)

local StarterPetSelectionController = {}
local player = Players.LocalPlayer
local started = false
local connections = {}
local uiConnections = {}
local refs = nil
local remote = nil
local pending = false
local selectedSpecies = nil
local warnedMissing = false
local notificationGeneration = 0

local function disconnect(list)
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

local function stageOf()
	return player:GetAttribute(TutorialConfig.StageAttributeName)
end

local function findOuterStroke(card)
	for _, child in ipairs(card:GetChildren()) do
		if child:IsA("UIStroke") then
			return child
		end
	end
	return nil
end

local function findChooseButton(card)
	local named = card:FindFirstChild("Claim", true)
	if named and named:IsA("GuiButton") then
		return named
	end
	for _, descendant in ipairs(card:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			return descendant
		end
	end
	return nil
end

local function setChooseCopy(button)
	if not button then
		return
	end
	local label = button:FindFirstChild("Label")
	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		label.Text = "CHOOSE"
	elseif button:IsA("TextButton") then
		button.Text = "CHOOSE"
	end
end

local function petPresentationFor(species)
	local pet = PetCatalog.Pets[species]
	local rarityName = pet and pet.Rarity or PetRarityCatalog.FallbackRarity
	local rarity = PetRarityCatalog.Rarities[rarityName]
		or PetRarityCatalog.Rarities[PetRarityCatalog.FallbackRarity]
	return rarity and rarity.Color or Color3.new(1, 1, 1), pet and pet.Icon or nil
end

local function restoreCardVisual(cardRef)
	if not cardRef or not cardRef.Stroke or not cardRef.Stroke.Parent then
		return
	end
	TweenService:Create(
		cardRef.Stroke,
		TweenInfo.new(TutorialConfig.StarterPetStrokeTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Color = cardRef.DefaultStrokeColor,
			Transparency = cardRef.DefaultStrokeTransparency,
		}
	):Play()
end

local function renderSelectionVisual()
	if not refs then
		return
	end
	for species, cardRef in pairs(refs.Cards) do
		if selectedSpecies == species and cardRef.Stroke and cardRef.Stroke.Parent then
			TweenService:Create(
				cardRef.Stroke,
				TweenInfo.new(TutorialConfig.StarterPetStrokeTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Color = TutorialConfig.StarterPetSelectedStrokeColor,
					Transparency = 0,
				}
			):Play()
		else
			restoreCardVisual(cardRef)
		end
	end
end

local function choose(species)
	if pending or stageOf() ~= TutorialConfig.Stages.ChooseStarterPet then
		return
	end
	pending = true
	selectedSpecies = species
	renderSelectionVisual()
	remote:FireServer(species)
end

local function resolveRefs()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild(TutorialConfig.StarterPetSelectionGuiName)
	if not gui or not gui:IsA("ScreenGui") then
		return nil
	end

	local cards = {}
	for species, cardName in pairs(TutorialConfig.StarterPetChoices) do
		local card = gui:FindFirstChild(cardName, true)
		if not card or not card:IsA("GuiObject") then
			return nil
		end
		local button = findChooseButton(card)
		local stroke = findOuterStroke(card)
		if not button or not stroke then
			return nil
		end
		setChooseCopy(button)
		cards[species] = {
			Card = card,
			Button = button,
			Stroke = stroke,
			DefaultStrokeColor = stroke.Color,
			DefaultStrokeTransparency = stroke.Transparency,
		}
	end

	return {
		Gui = gui,
		Cards = cards,
	}
end

local function bindGui()
	disconnect(uiConnections)
	refs = resolveRefs()
	if not refs then
		return false
	end
	-- The authored full-screen dimmer should also cover the Roblox top-bar inset.
	refs.Gui.IgnoreGuiInset = true
	for species, cardRef in pairs(refs.Cards) do
		table.insert(uiConnections, cardRef.Button.Activated:Connect(function()
			choose(species)
		end))
	end
	renderSelectionVisual()
	return true
end

local function shouldShow()
	return stageOf() == TutorialConfig.Stages.ChooseStarterPet
		and player:GetAttribute(DialogueConfig.ActiveAttributeName) ~= true
end

local function render()
	if not refs or not refs.Gui.Parent then
		bindGui()
	end
	local visible = shouldShow() and refs ~= nil and refs.Gui.Parent ~= nil
	if refs and refs.Gui.Parent then
		refs.Gui.Enabled = visible
	end
	InteractionLock.Set("StarterPetSelection", visible)
	if not visible then
		pending = false
		selectedSpecies = nil
		renderSelectionVisual()
	end
end

local function clearGrantNotification()
	TextNotificationController.Clear("StarterPetGrantIndex")
	TextNotificationController.Clear("StarterPetGrantReward")
end

local function showGrantNotification(species)
	notificationGeneration += 1
	local generation = notificationGeneration
	local totalSeconds = TutorialConfig.StarterPetGrantNotificationSeconds
	local rewardDelaySeconds = math.min(TutorialConfig.StarterPetRewardDelaySeconds, totalSeconds)
	local color, icon = petPresentationFor(species)

	clearGrantNotification()
	TextNotificationController.ShowIndex("StarterPetGrantIndex", "Index:", "New species found!")
	task.delay(rewardDelaySeconds, function()
		if started and notificationGeneration == generation and icon then
			TextNotificationController.ShowReward("StarterPetGrantReward", species, "x1", color, icon)
		end
	end)
	task.delay(totalSeconds, function()
		if started and notificationGeneration == generation then
			clearGrantNotification()
		end
	end)
end

local function onRemote(operation, success, species, _uid, reason)
	if operation ~= "Result" then
		return
	end
	if success == true then
		showGrantNotification(tostring(species))
		pending = false
		return
	end
	pending = false
	selectedSpecies = nil
	renderSelectionVisual()
	if reason and reason ~= "" then
		warn("[Pawlands StarterPet] " .. tostring(reason))
	end
end

local function bindPlayerGui()
	local playerGui = player:WaitForChild("PlayerGui")
	table.insert(connections, playerGui.ChildAdded:Connect(function(child)
		if child.Name == TutorialConfig.StarterPetSelectionGuiName then
			task.defer(function()
				bindGui()
				render()
			end)
		end
	end))
	table.insert(connections, playerGui.ChildRemoved:Connect(function(child)
		if child.Name ~= TutorialConfig.StarterPetSelectionGuiName then
			return
		end
		disconnect(uiConnections)
		refs = nil
		pending = false
		selectedSpecies = nil
		-- Never leave movement locked behind a missing modal. If Roblox/Studio
		-- recreates the authored GUI, ChildAdded will bind it again for the same stage.
		InteractionLock.Set("StarterPetSelection", false)
	end))
end

function StarterPetSelectionController.Start()
	if started then
		return
	end
	started = true
	remote = Pawlands:WaitForChild(TutorialConfig.RemoteFolderName):WaitForChild(TutorialConfig.StarterPetChoiceRemoteName)
	bindPlayerGui()
	bindGui()
	table.insert(connections, player:GetAttributeChangedSignal(TutorialConfig.StageAttributeName):Connect(render))
	table.insert(connections, player:GetAttributeChangedSignal(DialogueConfig.ActiveAttributeName):Connect(render))
	table.insert(connections, remote.OnClientEvent:Connect(onRemote))

	task.delay(3, function()
		if started and not refs and not warnedMissing then
			warnedMissing = true
			warn("[Pawlands StarterPet] Studio-owned StarterPetSelection is missing DogCard, CatCard, BunnyCard, an outer UIStroke, or a Claim/GuiButton anchor.")
		end
	end)
	render()
end

function StarterPetSelectionController.Stop()
	if not started then
		return
	end
	started = false
	disconnect(connections)
	disconnect(uiConnections)
	InteractionLock.Set("StarterPetSelection", false)
	clearGrantNotification()
	if refs and refs.Gui and refs.Gui.Parent then
		refs.Gui.Enabled = false
	end
	refs = nil
	remote = nil
	pending = false
	selectedSpecies = nil
	notificationGeneration += 1
end

return StarterPetSelectionController
