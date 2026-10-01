-- Shared presentation metadata for Pawlands Pet rarity tiers.
-- Rarity currently affects presentation/sorting only; combat stats remain species-authored
-- in PetCatalog so each Pet can keep its own HP/Damage identity.
local rarities = {
	Common = { Order = 1, Color = Color3.fromRGB(184, 184, 184) }, -- #B8B8B8
	Uncommon = { Order = 2, Color = Color3.fromRGB(89, 214, 111) }, -- #59D66F
	Epic = { Order = 3, Color = Color3.fromRGB(166, 108, 255) }, -- #A66CFF
	Legendary = { Order = 4, Color = Color3.fromRGB(255, 178, 63) }, -- #FFB23F
	Mythic = { Order = 5, Color = Color3.fromRGB(255, 84, 126) }, -- #FF547E
	Secret = { Order = 6, Color = Color3.fromRGB(93, 226, 255) }, -- #5DE2FF
}

for _, definition in pairs(rarities) do
	table.freeze(definition)
end

return table.freeze({
	FallbackRarity = "Common",
	Rarities = table.freeze(rarities),
})
