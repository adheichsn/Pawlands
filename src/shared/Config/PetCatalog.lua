-- Models remain owned by Studio under Assets/Pets/StoneIsland.
-- Different variants may share a SpeciesId to enforce one species per party.
-- StoneIsland meshes face local -X; -90 degrees maps their face to follow -Z.
-- YawOffset calibrates the artwork after movement lean; it is not player yaw.
-- Identity is design metadata only in 3B.1; it does not add role/skill mechanics.
local pets = {
	Bunny = {
		SpeciesId = "Bunny",
		ModelName = "Bunny",
		Movement = "Ground",
		YawOffset = -90,
		Icon = "rbxassetid://98159714295831",
		Rarity = "Common",
		BaseMaxHealth = 95,
		BaseDamage = 12,
		Identity = "balanced-light",
	},
	Cat = {
		SpeciesId = "Cat",
		ModelName = "Cat",
		Movement = "Ground",
		YawOffset = -90,
		Icon = "rbxassetid://85987199477651",
		Rarity = "Common",
		BaseMaxHealth = 100,
		BaseDamage = 12,
		Identity = "balanced",
	},
	Chicken = {
		SpeciesId = "Chicken",
		ModelName = "Chicken",
		Movement = "Ground",
		YawOffset = -90,
		Icon = "rbxassetid://136679292053828",
		Rarity = "Uncommon",
		BaseMaxHealth = 105,
		BaseDamage = 14,
		Identity = "offense",
	},
	Cow = {
		SpeciesId = "Cow",
		ModelName = "Cow",
		Movement = "Ground",
		YawOffset = -90,
		Icon = "rbxassetid://135156787627380",
		Rarity = "Epic",
		BaseMaxHealth = 145,
		BaseDamage = 14,
		Identity = "tanky",
	},
	Dog = {
		SpeciesId = "Dog",
		ModelName = "Dog",
		Movement = "Ground",
		YawOffset = -90,
		Icon = "rbxassetid://90032050484312",
		Rarity = "Common",
		BaseMaxHealth = 110,
		BaseDamage = 11,
		Identity = "slightly tanky",
	},
	Dragon = {
		SpeciesId = "Dragon",
		ModelName = "Dragon",
		Movement = "Flying",
		HoverHeight = 2,
		YawOffset = -90,
		Icon = "rbxassetid://104047512065229",
		Rarity = "Secret",
		BaseMaxHealth = 165,
		BaseDamage = 20,
		Identity = "strong all-rounder",
	},
	Piggy = {
		SpeciesId = "Piggy",
		ModelName = "Piggy",
		Movement = "Ground",
		YawOffset = -90,
		Icon = "rbxassetid://126802350537519",
		Rarity = "Uncommon",
		BaseMaxHealth = 120,
		BaseDamage = 13,
		Identity = "durable",
	},
	Raccoon = {
		SpeciesId = "Raccoon",
		ModelName = "Raccoon",
		Movement = "Ground",
		YawOffset = -90,
		Icon = "rbxassetid://122391489105244",
		Rarity = "Mythic",
		BaseMaxHealth = 140,
		BaseDamage = 18,
		Identity = "high damage",
	},
	Rat = {
		SpeciesId = "Rat",
		ModelName = "Rat",
		Movement = "Ground",
		YawOffset = -90,
		Icon = "rbxassetid://95053074070336",
		Rarity = "Epic",
		BaseMaxHealth = 110,
		BaseDamage = 16,
		Identity = "glass-cannon-ish",
	},
	Turtle = {
		SpeciesId = "Turtle",
		ModelName = "Turtle",
		Movement = "Ground",
		YawOffset = -90,
		Icon = "rbxassetid://134759934579975",
		Rarity = "Legendary",
		BaseMaxHealth = 175,
		BaseDamage = 15,
		Identity = "tank",
	},
}

local aliases = { drago = "Dragon" }
for id, definition in pairs(pets) do
	aliases[string.lower(id)] = id
	table.freeze(definition)
end

return table.freeze({ Pets = table.freeze(pets), Aliases = table.freeze(aliases) })
