return table.freeze({
	RemoteFolderName = "Remotes",
	RemoteFunctionName = "PetInventory",

	GuiName = "Inventory",
	HudGuiName = "HUD",
	HudRootName = "Hud",
	HudLeftSideName = "LeftSide",
	HudRowName = "Row1",
	HudInventoryButtonName = "InventoryButton",
	HudKeyButtonName = "KeyButton",

	RuntimePetTilePrefix = "RuntimePet_",
	RuntimeEquippedPetTilePrefix = "RuntimeEquippedPet_",
	RuntimePartySlotPrefix = "RuntimePartySlot_",
	DefaultVariantName = "Normal",
	FavoriteOffText = "Favorite: OFF",
	FavoriteOnText = "Favorite: ON",
	EquippedPetsTextFormat = "Equipped Pets (%d/%d)",
	DamageTextFormat = "%d DMG",

	PartyMutationLockedAttributeName = "PawlandsPetPartyLocked",
	PartyMutationExitGraceSeconds = 1.75,
	PartyMutationPollIntervalSeconds = 0.10,
	PartyMutationLockedReason = "Pet party can't be changed during combat.",
	PartyMutationNotificationKey = "PetPartyCombatLock",
	PartyMutationNotificationDurationSeconds = 2.4,

	Actions = table.freeze({
		Snapshot = "Snapshot",
		ToggleEquip = "ToggleEquip",
		ToggleFavorite = "ToggleFavorite",
	}),
})
