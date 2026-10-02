local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local InventoryConfig = require(Shared.Config.Inventory)
local PetCatalog = require(Shared.Config.PetCatalog)
local PetPartyConfig = require(Shared.Config.PetParty)
local PetRarityCatalog = require(Shared.Config.PetRarityCatalog)
local InteractionLock = require(script.Parent.Parent.Interaction.InteractionLock)
local TextNotificationController = require(script.Parent.Parent.Notifications.TextNotificationController)

local InventoryController = {}

local player = Players.LocalPlayer
local started = false
local connections = {}
local uiConnections = {}
local refs = nil
local remote = nil
local snapshot = nil
local currentPage = "Pets"
local favoriteMode = false
local busy = false
local warnedMissing = false
local partyLockNoticeSerial = 0
local favoriteStrokeDefaults = nil

local function disconnect(list)
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

local function disconnectAll()
	disconnect(connections)
	disconnect(uiConnections)
end

local function child(parent, name, className)
	local instance = parent and parent:FindFirstChild(name)
	if not instance or (className and not instance:IsA(className)) then
		return nil
	end
	return instance
end

local function resolveRefs()
	if refs and refs.Gui.Parent and refs.HudButton.Parent and refs.PetTemplate.Parent then
		return refs
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and child(playerGui, InventoryConfig.GuiName, "ScreenGui")
	local hud = playerGui and child(playerGui, InventoryConfig.HudGuiName, "ScreenGui")
	local main = gui and child(gui, "Main", "Frame")
	local content = main and child(main, "Content", "Frame")
	local pages = content and child(content, "Pages", "Frame")
	local petsPage = pages and child(pages, "Pets", "Frame")
	local itemsPage = pages and child(pages, "Items", "Frame")
	local nonePage = pages and child(pages, "None", "Frame")
	local petMain = petsPage and child(petsPage, "Main", "Frame")
	local petInventory = petMain and child(petMain, "Inventory", "ScrollingFrame")
	local petTemplate = petInventory and child(petInventory, "Tile", "ImageButton")
	local petTop = petsPage and child(petsPage, "Top", "Frame")
	local partyLayout = petTop and petTop:FindFirstChildWhichIsA("UIGridLayout")
	local addFrame = petTop and child(petTop, "AddFrame", "Frame")
	local addTile = addFrame and addFrame:FindFirstChild("AddTile")
	if addTile and not addTile:IsA("GuiObject") then
		addTile = nil
	end
	local equipLabel = petsPage and child(petsPage, "EquipLabel", "TextLabel")
	local closeButton = content and child(content, "Close", "ImageButton")
	local top = main and child(main, "Top", "Frame")
	local favorite = top and child(top, "Favorite", "ImageButton")
	local favoriteLabel = favorite and favorite:FindFirstChild("Label")
	local searchFrame = top and child(top, "SearchBarFrame", "ImageLabel")
	local searchBar = searchFrame and child(searchFrame, "SearchBar", "TextBox")
	local autoOptions = top and child(top, "AutoOptions", "Frame")
	local options = top and child(top, "Options", "Frame")
	local petsTab = options and child(options, "Pets", "ImageButton")
	local itemsTab = options and child(options, "Items", "ImageButton")
	local petsLabel = petsTab and child(petsTab, "Label", "TextLabel")
	local itemsLabel = itemsTab and child(itemsTab, "Label", "TextLabel")
	local petCount = petsLabel and child(petsLabel, "BagSize", "TextLabel")
	local itemCount = itemsLabel and child(itemsLabel, "ItemSize", "TextLabel")
	local petsNotification = petsTab and child(petsTab, "Notification", "Frame")
	local itemsNotification = itemsTab and child(itemsTab, "Notification", "Frame")
	local petsNotificationLabel = petsNotification and child(petsNotification, "Label", "TextLabel")
	local itemsNotificationLabel = itemsNotification and child(itemsNotification, "Label", "TextLabel")
	local noneLabel = nonePage and child(nonePage, "Label", "TextLabel")
	local sellAll = main and child(main, "SellAll", "ImageButton")
	local configuration = main and child(main, "Configuration", "Frame")

	local hudRoot = hud and child(hud, InventoryConfig.HudRootName, "Frame")
	local hudLeft = hudRoot and child(hudRoot, InventoryConfig.HudLeftSideName, "Frame")
	local hudRow = hudLeft and child(hudLeft, InventoryConfig.HudRowName, "Frame")
	local hudButton = hudRow and child(hudRow, InventoryConfig.HudInventoryButtonName, "Frame")
	local hudKeyButton = hudButton and child(hudButton, InventoryConfig.HudKeyButtonName, "ImageButton")

	if not gui or not main or not pages or not petsPage or not itemsPage or not nonePage
		or not petInventory or not petTemplate or not petTop or not partyLayout
		or not addFrame or not addTile or not equipLabel or not closeButton
		or not favorite or not favoriteLabel or not favoriteLabel:IsA("TextLabel")
		or not searchBar or not autoOptions or not options or not petsTab or not itemsTab
		or not petCount or not itemCount or not noneLabel
		or not sellAll or not configuration or not hudButton or not hudKeyButton
	then
		refs = nil
		return nil
	end

	refs = {
		Gui = gui,
		Hud = hud,
		Main = main,
		Pages = pages,
		PetsPage = petsPage,
		ItemsPage = itemsPage,
		NonePage = nonePage,
		PetInventory = petInventory,
		PetTemplate = petTemplate,
		PetTop = petTop,
		PartyLayout = partyLayout,
		AddFrame = addFrame,
		AddTile = addTile,
		EquipLabel = equipLabel,
		CloseButton = closeButton,
		Favorite = favorite,
		FavoriteLabel = favoriteLabel,
		SearchBar = searchBar,
		AutoOptions = autoOptions,
		PetsTab = petsTab,
		ItemsTab = itemsTab,
		PetCount = petCount,
		ItemCount = itemCount,
		PetsNotification = petsNotification,
		ItemsNotification = itemsNotification,
		PetsNotificationLabel = petsNotificationLabel,
		ItemsNotificationLabel = itemsNotificationLabel,
		NoneLabel = noneLabel,
		SellAll = sellAll,
		Configuration = configuration,
		HudButton = hudButton,
		HudKeyButton = hudKeyButton,
	}
	return refs
end

local function partySet(party)
	local set = {}
	for _, uid in ipairs(party or {}) do
		if type(uid) == "string" then
			set[uid] = true
		end
	end
	return set
end

local function hasPrefix(name, prefix)
	return string.sub(name, 1, #prefix) == prefix
end

local function clearRuntimeChildren(container, prefixes)
	for _, item in ipairs(container:GetChildren()) do
		if item:IsA("GuiObject") then
			for _, prefix in ipairs(prefixes) do
				if hasPrefix(item.Name, prefix) then
					item:Destroy()
					break
				end
			end
		end
	end
end

local function clearRuntimeTiles(current)
	clearRuntimeChildren(current.PetInventory, { InventoryConfig.RuntimePetTilePrefix })
	clearRuntimeChildren(current.PetTop, { InventoryConfig.RuntimePartySlotPrefix })
end

local function normalizedVariant(pet)
	local variant = string.match(tostring(pet and pet.Variant or ""), "^%s*(.-)%s*$")
	if string.lower(variant) == string.lower(InventoryConfig.DefaultVariantName) then
		return ""
	end
	return variant
end

local function searchTextFor(pet)
	local definition = PetCatalog.Pets[pet.PetId]
	return string.lower(table.concat({
		tostring(pet.PetId or ""),
		tostring(pet.SpeciesId or ""),
		normalizedVariant(pet),
		tostring(definition and definition.Rarity or ""),
	}, " "))
end

local function validOwnedPetCount(value)
	local count = 0
	if type(value) ~= "table" then
		return count
	end
	for _, pet in ipairs(value.Pets or {}) do
		if type(pet) == "table" and type(pet.Uid) == "string" and PetCatalog.Pets[pet.PetId] then
			count += 1
		end
	end
	return count
end

local function rarityPresentationFor(pet)
	local definition = pet and PetCatalog.Pets[pet.PetId]
	local rarityName = definition and definition.Rarity or PetRarityCatalog.FallbackRarity
	local rarity = PetRarityCatalog.Rarities[rarityName]
	if rarity then
		return rarityName, rarity
	end
	return PetRarityCatalog.FallbackRarity, PetRarityCatalog.Rarities[PetRarityCatalog.FallbackRarity]
end

local function inventoryDisplayName(pet)
	return tostring(pet and (pet.SpeciesId or pet.PetId) or "Pet")
end

local function sortedOwnedPets(pets)
	local sorted = {}
	for _, pet in ipairs(pets or {}) do
		if type(pet) == "table" and type(pet.Uid) == "string" and PetCatalog.Pets[pet.PetId] then
			table.insert(sorted, pet)
		end
	end

	table.sort(sorted, function(a, b)
		local aFavorite = a.Favorite == true
		local bFavorite = b.Favorite == true
		if aFavorite ~= bFavorite then
			return aFavorite
		end

		local _, aRarity = rarityPresentationFor(a)
		local _, bRarity = rarityPresentationFor(b)
		local aOrder = aRarity and aRarity.Order or 0
		local bOrder = bRarity and bRarity.Order or 0
		if aOrder ~= bOrder then
			return aOrder > bOrder
		end

		local aName = string.lower(inventoryDisplayName(a))
		local bName = string.lower(inventoryDisplayName(b))
		if aName ~= bName then
			return aName < bName
		end

		return tostring(a.Uid) < tostring(b.Uid)
	end)

	return sorted
end

local function captureFavoriteStrokeDefaults(template)
	local stroke = template and template:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return nil
	end
	local gradient = stroke:FindFirstChildOfClass("UIGradient")
	return {
		StrokeEnabled = stroke.Enabled,
		StrokeColor = stroke.Color,
		GradientEnabled = gradient and gradient.Enabled or nil,
		GradientColor = gradient and gradient.Color or nil,
	}
end

local function applyFavoriteStroke(tile, isFavorite)
	local stroke = tile:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return
	end
	local gradient = stroke:FindFirstChildOfClass("UIGradient")
	if isFavorite then
		stroke.Enabled = true
		stroke.Color = InventoryConfig.FavoriteStrokeColor
		if gradient then
			gradient.Enabled = true
			gradient.Color = ColorSequence.new(InventoryConfig.FavoriteStrokeColor)
		end
	elseif favoriteStrokeDefaults then
		stroke.Enabled = favoriteStrokeDefaults.StrokeEnabled
		stroke.Color = favoriteStrokeDefaults.StrokeColor
		if gradient and favoriteStrokeDefaults.GradientEnabled ~= nil then
			gradient.Enabled = favoriteStrokeDefaults.GradientEnabled
			gradient.Color = favoriteStrokeDefaults.GradientColor
		end
	end
end

local function resetPlaceholderBadges(current)
	if current.PetsNotificationLabel then
		current.PetsNotificationLabel.Text = InventoryConfig.EmptyBadgeText
	end
	if current.ItemsNotificationLabel then
		current.ItemsNotificationLabel.Text = InventoryConfig.EmptyBadgeText
	end
	if current.PetsNotification then
		current.PetsNotification.Visible = false
	end
	if current.ItemsNotification then
		current.ItemsNotification.Visible = false
	end
end

local function bindRuntimeCounts(current, petCount, itemCount)
	local ownedPets = math.max(0, math.floor(tonumber(petCount) or 0))
	local usedItemSlots = math.max(0, math.floor(tonumber(itemCount) or 0))
	current.PetCount.Text = string.format(
		InventoryConfig.CapacityCountTextFormat,
		ownedPets,
		InventoryConfig.PetCapacity
	)
	current.ItemCount.Text = string.format(
		InventoryConfig.CapacityCountTextFormat,
		usedItemSlots,
		InventoryConfig.ItemCapacity
	)
	resetPlaceholderBadges(current)
end

local function invoke(action, uid)
	if not remote or busy then
		return nil
	end
	busy = true
	local ok, result = pcall(function()
		return remote:InvokeServer(action, uid)
	end)
	busy = false
	if not ok then
		warn("[Pawlands Inventory] request failed: " .. tostring(result))
		return nil
	end
	if type(result) ~= "table" then
		warn("[Pawlands Inventory] server returned an invalid response.")
		return nil
	end
	return result
end

local renderSnapshot

local function showPartyMutationLockedNotice()
	partyLockNoticeSerial += 1
	local serial = partyLockNoticeSerial
	TextNotificationController.ShowText(
		InventoryConfig.PartyMutationNotificationKey,
		InventoryConfig.PartyMutationLockedReason
	)
	task.delay(InventoryConfig.PartyMutationNotificationDurationSeconds, function()
		if started and serial == partyLockNoticeSerial then
			TextNotificationController.Clear(InventoryConfig.PartyMutationNotificationKey)
		end
	end)
end

local function handleTileActivated(uid)
	if busy then
		return
	end
	local action = favoriteMode and InventoryConfig.Actions.ToggleFavorite
		or InventoryConfig.Actions.ToggleEquip
	local result = invoke(action, uid)
	if result then
		if result.Success ~= true and result.Reason ~= "" then
			if result.PartyMutationLocked == true then
				showPartyMutationLockedNotice()
			else
				warn("[Pawlands Inventory] " .. tostring(result.Reason))
			end
		end
		snapshot = result
		renderSnapshot()
	end
end

local function configureTile(tile, pet, equipped, order, namePrefix)
	tile.Name = (namePrefix or InventoryConfig.RuntimePetTilePrefix) .. pet.Uid
	tile.LayoutOrder = order
	tile.Visible = true
	tile:SetAttribute("PawlandsPetUid", pet.Uid)
	tile:SetAttribute("PawlandsPetSearch", searchTextFor(pet))

	local definition = PetCatalog.Pets[pet.PetId]
	local petName = tile:FindFirstChild("PetName")
	local vector = tile:FindFirstChild("Vector")
	local favoriteIcon = tile:FindFirstChild("FavoriteIcon")
	local attackFrame = tile:FindFirstChild("AttackFrame")
	local attack = attackFrame and attackFrame:FindFirstChild("Attack")
	local variant = tile:FindFirstChild("Variant")
	local variantName = variant and variant:FindFirstChild("VariantName")
	local equippedFrame = tile:FindFirstChild("Equipped")

	if petName and petName:IsA("TextLabel") then
		local _, rarity = rarityPresentationFor(pet)
		petName.Text = inventoryDisplayName(pet)
		if rarity then
			petName.TextColor3 = rarity.Color
		end
	end
	if vector and vector:IsA("ImageLabel") and definition then
		vector.Image = definition.Icon
	end
	if favoriteIcon and favoriteIcon:IsA("GuiObject") then
		favoriteIcon.Visible = pet.Favorite == true
	end
	applyFavoriteStroke(tile, pet.Favorite == true)
	if attack and attack:IsA("TextLabel") and definition then
		attack.Text = string.format(InventoryConfig.DamageTextFormat, definition.BaseDamage)
	end
	local visibleVariant = normalizedVariant(pet)
	if variant and variant:IsA("GuiObject") then
		variant.Visible = visibleVariant ~= ""
	end
	if variantName and variantName:IsA("TextLabel") then
		variantName.Text = visibleVariant
	end
	if equippedFrame and equippedFrame:IsA("GuiObject") then
		equippedFrame.Visible = equipped == true
	end

	tile.Activated:Connect(function()
		handleTileActivated(pet.Uid)
	end)
end

local function makePartySlot(current, slotIndex, pet)
	local slot = current.AddFrame:Clone()
	slot.Name = InventoryConfig.RuntimePartySlotPrefix .. tostring(slotIndex)
	slot.LayoutOrder = slotIndex
	slot.Visible = true

	local addTile = slot:FindFirstChild("AddTile")
	if addTile and addTile:IsA("GuiObject") then
		addTile.Visible = pet == nil
		if addTile:IsA("GuiButton") then
			addTile.Active = false
			addTile.Selectable = false
		end
	end

	if pet then
		local tile = current.PetTemplate:Clone()
		configureTile(
			tile,
			pet,
			true,
			slotIndex,
			InventoryConfig.RuntimeEquippedPetTilePrefix
		)
		tile.Position = UDim2.fromOffset(0, 0)
		tile.AnchorPoint = Vector2.new(0, 0)
		tile.Size = UDim2.fromScale(1, 1)
		tile.Parent = slot
	end

	slot.Parent = current.PetTop
end

local function applyPageAndSearch()
	local current = resolveRefs()
	if not current then
		return
	end
	if currentPage ~= "Pets" then
		current.PetsPage.Visible = false
		current.ItemsPage.Visible = false
		current.NoneLabel.Text = InventoryConfig.EmptyItemsText
		current.NonePage.Visible = true
		return
	end

	if validOwnedPetCount(snapshot) == 0 then
		current.PetsPage.Visible = false
		current.ItemsPage.Visible = false
		current.NoneLabel.Text = InventoryConfig.EmptyPetsText
		current.NonePage.Visible = true
		return
	end

	local query = string.lower(string.match(current.SearchBar.Text or "", "^%s*(.-)%s*$"))
	for _, item in ipairs(current.PetInventory:GetChildren()) do
		if item:IsA("GuiObject") and hasPrefix(item.Name, InventoryConfig.RuntimePetTilePrefix) then
			local haystack = item:GetAttribute("PawlandsPetSearch")
			item.Visible = query == ""
				or (type(haystack) == "string" and string.find(haystack, query, 1, true) ~= nil)
		end
	end

	-- Keep the Pets page visible even when Search filters every owned Pet. The top
	-- strip summarizes the active party while the lower grid remains the complete
	-- owned-Pet collection, including equipped Pets.
	current.PetsPage.Visible = true
	current.ItemsPage.Visible = false
	current.NonePage.Visible = false
end

renderSnapshot = function()
	local current = resolveRefs()
	if not current or type(snapshot) ~= "table" then
		return
	end
	clearRuntimeTiles(current)
	local equipped = partySet(snapshot.Party)
	local petsByUid = {}
	for _, pet in ipairs(snapshot.Pets or {}) do
		if type(pet) == "table" and type(pet.Uid) == "string" then
			petsByUid[pet.Uid] = pet
		end
	end

	for slotIndex = 1, PetPartyConfig.MaxSize do
		local uid = snapshot.Party and snapshot.Party[slotIndex]
		local pet = uid and petsByUid[uid] or nil
		if pet and not PetCatalog.Pets[pet.PetId] then
			pet = nil
		end
		makePartySlot(current, slotIndex, pet)
	end

	local inventoryOrder = 0
	for _, pet in ipairs(sortedOwnedPets(snapshot.Pets)) do
		inventoryOrder += 1
		local tile = current.PetTemplate:Clone()
		configureTile(
			tile,
			pet,
			equipped[pet.Uid] == true,
			inventoryOrder,
			InventoryConfig.RuntimePetTilePrefix
		)
		tile.Parent = current.PetInventory
	end

	current.EquipLabel.Text = string.format(
		InventoryConfig.EquippedPetsTextFormat,
		#(snapshot.Party or {}),
		PetPartyConfig.MaxSize
	)
	bindRuntimeCounts(current, inventoryOrder)
	applyPageAndSearch()
end

local function refreshSnapshot()
	local result = invoke(InventoryConfig.Actions.Snapshot)
	if result then
		snapshot = result
		renderSnapshot()
	end
end

local function setFavoriteMode(active)
	favoriteMode = active == true
	local current = resolveRefs()
	if current then
		current.FavoriteLabel.Text = favoriteMode
			and InventoryConfig.FavoriteOnText
			or InventoryConfig.FavoriteOffText
	end
end

local function closeInventory()
	local current = resolveRefs()
	if current then
		current.Gui.Enabled = false
	end
	InteractionLock.Set("Inventory", false)
	setFavoriteMode(false)
end

local function openInventory()
	local current = resolveRefs()
	if not current then
		return
	end
	if InteractionLock.IsLocked() and not InteractionLock.IsLocked("Inventory") then
		return
	end
	current.Gui.Enabled = true
	InteractionLock.Set("Inventory", true)
	currentPage = "Pets"
	current.SearchBar.Text = ""
	setFavoriteMode(false)
	refreshSnapshot()
end

local function prepareAuthoredUi(current)
	-- Let the authored modal/dimmer reach the physical top edge instead of stopping
	-- below Roblox's top-bar inset. No GUI objects are created for this.
	current.Gui.IgnoreGuiInset = true

	-- Keep the already-bound Studio-authored Inventory + HUD instances across
	-- character respawns. Runtime rebind below still handles an external replacement.
	current.Hud.ResetOnSpawn = false
	current.Gui.ResetOnSpawn = false
	current.Gui.Enabled = false
	current.PetTemplate.Visible = false
	current.AddFrame.Visible = false
	favoriteStrokeDefaults = captureFavoriteStrokeDefaults(current.PetTemplate)
	bindRuntimeCounts(current, 0)
	current.NoneLabel.Text = InventoryConfig.EmptyPetsText

	-- Reuse the authored Top UIGridLayout and authored AddFrame size for the four
	-- party slots. Runtime does not create a layout or slot hierarchy from scratch.
	current.PartyLayout.CellSize = current.AddFrame.Size
	current.PartyLayout.FillDirection = Enum.FillDirection.Horizontal
	current.PartyLayout.FillDirectionMaxCells = PetPartyConfig.MaxSize
	current.PartyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	current.PartyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	current.PartyLayout.SortOrder = Enum.SortOrder.LayoutOrder

	current.AutoOptions.Visible = false
	current.SellAll.Visible = false
	current.Configuration.Visible = false
	current.Favorite.Visible = true
	current.SearchBar.Parent.Visible = true
	current.PetsPage.Visible = false
	current.ItemsPage.Visible = false
	current.NonePage.Visible = false
	setFavoriteMode(false)
end

local function bind(current)
	disconnect(uiConnections)
	table.insert(uiConnections, current.HudKeyButton.Activated:Connect(openInventory))
	table.insert(uiConnections, current.CloseButton.Activated:Connect(closeInventory))
	table.insert(uiConnections, current.SearchBar:GetPropertyChangedSignal("Text"):Connect(applyPageAndSearch))
	table.insert(uiConnections, current.Favorite.Activated:Connect(function()
		setFavoriteMode(not favoriteMode)
	end))
	table.insert(uiConnections, current.PetsTab.Activated:Connect(function()
		currentPage = "Pets"
		applyPageAndSearch()
	end))
	table.insert(uiConnections, current.ItemsTab.Activated:Connect(function()
		currentPage = "Items"
		applyPageAndSearch()
	end))
end

local function rebindUi()
	if not started then
		return false
	end
	disconnect(uiConnections)
	refs = nil
	local current = resolveRefs()
	if not current then
		return false
	end
	prepareAuthoredUi(current)
	bind(current)
	return true
end

function InventoryController.Start()
	if started then
		return
	end
	started = true
	local pawlands = ReplicatedStorage:WaitForChild("Pawlands")
	remote = pawlands:WaitForChild(InventoryConfig.RemoteFolderName):WaitForChild(InventoryConfig.RemoteFunctionName)
	local playerGui = player:WaitForChild("PlayerGui")
	local current = resolveRefs()
	if current then
		prepareAuthoredUi(current)
		bind(current)
	else
		task.delay(3, function()
			if not started or warnedMissing then
				return
			end
			if not rebindUi() then
				warnedMissing = true
				warn("[Pawlands Inventory] Studio-owned Inventory or HUD InventoryButton hierarchy is missing required runtime anchors.")
			end
		end)
	end

	table.insert(connections, player:GetAttributeChangedSignal(PetPartyConfig.AttributeName):Connect(function()
		local active = resolveRefs()
		if active and active.Gui.Enabled then
			refreshSnapshot()
		end
	end))
	table.insert(connections, player.CharacterRemoving:Connect(closeInventory))
	table.insert(connections, playerGui.ChildAdded:Connect(function(childGui)
		if childGui.Name == InventoryConfig.GuiName or childGui.Name == InventoryConfig.HudGuiName then
			InteractionLock.Set("Inventory", false)
			refs = nil
			task.defer(function()
				if started then
					rebindUi()
				end
			end)
		end
	end))
	table.insert(connections, playerGui.ChildRemoved:Connect(function(childGui)
		if childGui.Name ~= InventoryConfig.GuiName and childGui.Name ~= InventoryConfig.HudGuiName then
			return
		end
		InteractionLock.Set("Inventory", false)
		disconnect(uiConnections)
		refs = nil
		snapshot = nil
		currentPage = "Pets"
		favoriteMode = false
	end))
end

function InventoryController.Stop()
	if not started then
		return
	end
	started = false
	closeInventory()
	disconnectAll()
	if refs then
		clearRuntimeTiles(refs)
	end
	refs = nil
	remote = nil
	snapshot = nil
	currentPage = "Pets"
	favoriteMode = false
	busy = false
	warnedMissing = false
	favoriteStrokeDefaults = nil
	partyLockNoticeSerial += 1
	TextNotificationController.Clear(InventoryConfig.PartyMutationNotificationKey)
end

return InventoryController
