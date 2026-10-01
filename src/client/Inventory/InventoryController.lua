local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local InventoryConfig = require(Shared.Config.Inventory)
local PetCatalog = require(Shared.Config.PetCatalog)
local PetPartyConfig = require(Shared.Config.PetParty)
local InteractionLock = require(script.Parent.Parent.Interaction.InteractionLock)

local InventoryController = {}

local player = Players.LocalPlayer
local started = false
local connections = {}
local refs = nil
local remote = nil
local snapshot = nil
local currentPage = "Pets"
local favoriteMode = false
local busy = false
local warnedMissing = false

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
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
	local sellAll = main and child(main, "SellAll", "ImageButton")
	local configuration = main and child(main, "Configuration", "Frame")

	local hudRoot = hud and child(hud, InventoryConfig.HudRootName, "Frame")
	local hudLeft = hudRoot and child(hudRoot, InventoryConfig.HudLeftSideName, "Frame")
	local hudRow = hudLeft and child(hudLeft, InventoryConfig.HudRowName, "Frame")
	local hudButton = hudRow and child(hudRow, InventoryConfig.HudInventoryButtonName, "Frame")
	local hudKeyButton = hudButton and child(hudButton, InventoryConfig.HudKeyButtonName, "ImageButton")

	if not gui or not main or not pages or not petsPage or not itemsPage or not nonePage
		or not petInventory or not petTemplate or not equipLabel or not closeButton
		or not favorite or not favoriteLabel or not favoriteLabel:IsA("TextLabel")
		or not searchBar or not autoOptions or not options or not petsTab or not itemsTab
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
		EquipLabel = equipLabel,
		CloseButton = closeButton,
		Favorite = favorite,
		FavoriteLabel = favoriteLabel,
		SearchBar = searchBar,
		AutoOptions = autoOptions,
		PetsTab = petsTab,
		ItemsTab = itemsTab,
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

local function clearRuntimeTiles(current)
	for _, item in ipairs(current.PetInventory:GetChildren()) do
		if item:IsA("GuiObject") and string.sub(item.Name, 1, #InventoryConfig.RuntimePetTilePrefix)
			== InventoryConfig.RuntimePetTilePrefix
		then
			item:Destroy()
		end
	end
end

local function searchTextFor(pet)
	local definition = PetCatalog.Pets[pet.PetId]
	return string.lower(table.concat({
		tostring(pet.PetId or ""),
		tostring(pet.SpeciesId or ""),
		tostring(pet.Variant or ""),
		tostring(definition and definition.Rarity or ""),
	}, " "))
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

local function handleTileActivated(uid)
	if busy then
		return
	end
	local action = favoriteMode and InventoryConfig.Actions.ToggleFavorite
		or InventoryConfig.Actions.ToggleEquip
	local result = invoke(action, uid)
	if result then
		if result.Success ~= true and result.Reason ~= "" then
			warn("[Pawlands Inventory] " .. tostring(result.Reason))
		end
		snapshot = result
		renderSnapshot()
	end
end

local function configureTile(tile, pet, equipped, order)
	tile.Name = InventoryConfig.RuntimePetTilePrefix .. pet.Uid
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
		petName.Text = pet.SpeciesId or pet.PetId or "Pet"
	end
	if vector and vector:IsA("ImageLabel") and definition then
		vector.Image = definition.Icon
	end
	if favoriteIcon and favoriteIcon:IsA("GuiObject") then
		favoriteIcon.Visible = pet.Favorite == true
	end
	if attack and attack:IsA("TextLabel") and definition then
		attack.Text = string.format(InventoryConfig.DamageTextFormat, definition.BaseDamage)
	end
	if variantName and variantName:IsA("TextLabel") then
		variantName.Text = pet.Variant or "Normal"
	end
	if equippedFrame and equippedFrame:IsA("GuiObject") then
		equippedFrame.Visible = equipped == true
	end

	tile.Activated:Connect(function()
		handleTileActivated(pet.Uid)
	end)
end

local function applyPageAndSearch()
	local current = resolveRefs()
	if not current then
		return
	end
	if currentPage ~= "Pets" then
		current.PetsPage.Visible = false
		current.ItemsPage.Visible = false
		current.NonePage.Visible = true
		return
	end

	local query = string.lower(string.match(current.SearchBar.Text or "", "^%s*(.-)%s*$"))
	local visibleCount = 0
	for _, item in ipairs(current.PetInventory:GetChildren()) do
		if item:IsA("GuiObject") and string.sub(item.Name, 1, #InventoryConfig.RuntimePetTilePrefix)
			== InventoryConfig.RuntimePetTilePrefix
		then
			local haystack = item:GetAttribute("PawlandsPetSearch")
			local visible = query == ""
				or (type(haystack) == "string" and string.find(haystack, query, 1, true) ~= nil)
			item.Visible = visible
			if visible then
				visibleCount += 1
			end
		end
	end
	current.PetsPage.Visible = visibleCount > 0
	current.ItemsPage.Visible = false
	current.NonePage.Visible = visibleCount <= 0
end

renderSnapshot = function()
	local current = resolveRefs()
	if not current or type(snapshot) ~= "table" then
		return
	end
	clearRuntimeTiles(current)
	local equipped = partySet(snapshot.Party)
	for index, pet in ipairs(snapshot.Pets or {}) do
		if type(pet) == "table" and type(pet.Uid) == "string" and PetCatalog.Pets[pet.PetId] then
			local tile = current.PetTemplate:Clone()
			configureTile(tile, pet, equipped[pet.Uid], index)
			tile.Parent = current.PetInventory
		end
	end
	current.EquipLabel.Text = string.format(
		InventoryConfig.EquippedPetsTextFormat,
		#(snapshot.Party or {}),
		PetPartyConfig.MaxSize
	)
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
	-- HUD is Studio-owned but originally resets on respawn. Keep this exact cloned
	-- PlayerGui instance so the bound InventoryButton does not become stale.
	current.Hud.ResetOnSpawn = false
	current.Gui.Enabled = false
	current.PetTemplate.Visible = false
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
	table.insert(connections, current.HudKeyButton.Activated:Connect(openInventory))
	table.insert(connections, current.CloseButton.Activated:Connect(closeInventory))
	table.insert(connections, current.SearchBar:GetPropertyChangedSignal("Text"):Connect(applyPageAndSearch))
	table.insert(connections, current.Favorite.Activated:Connect(function()
		setFavoriteMode(not favoriteMode)
	end))
	table.insert(connections, current.PetsTab.Activated:Connect(function()
		currentPage = "Pets"
		applyPageAndSearch()
	end))
	table.insert(connections, current.ItemsTab.Activated:Connect(function()
		currentPage = "Items"
		applyPageAndSearch()
	end))

	local partyAttribute = PetPartyConfig.AttributeName
	table.insert(connections, player:GetAttributeChangedSignal(partyAttribute):Connect(function()
		if current.Gui.Enabled then
			refreshSnapshot()
		end
	end))
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
			local delayed = resolveRefs()
			if delayed then
				prepareAuthoredUi(delayed)
				bind(delayed)
			else
				warnedMissing = true
				warn("[Pawlands Inventory] Studio-owned Inventory or HUD InventoryButton hierarchy is missing required runtime anchors.")
			end
		end)
	end

	table.insert(connections, player.CharacterRemoving:Connect(closeInventory))
	table.insert(connections, playerGui.ChildAdded:Connect(function(childGui)
		if childGui.Name == InventoryConfig.GuiName or childGui.Name == InventoryConfig.HudGuiName then
			closeInventory()
		end
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
end

return InventoryController
