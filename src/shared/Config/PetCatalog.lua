-- Models remain owned by Studio under Assets/Pets/StoneIsland.
-- Different variants may share a SpeciesId to enforce one species per party.
-- StoneIsland meshes face local -X; -90 degrees maps their face to follow -Z.
-- YawOffset calibrates the artwork after movement lean; it is not player yaw.
local pets = {
	Bunny = { SpeciesId = "Bunny", ModelName = "Bunny", Movement = "Ground", YawOffset = -90 },
	Cat = { SpeciesId = "Cat", ModelName = "Cat", Movement = "Ground", YawOffset = -90 },
	Chicken = { SpeciesId = "Chicken", ModelName = "Chicken", Movement = "Ground", YawOffset = -90 },
	Cow = { SpeciesId = "Cow", ModelName = "Cow", Movement = "Ground", YawOffset = -90 },
	Dog = { SpeciesId = "Dog", ModelName = "Dog", Movement = "Ground", YawOffset = -90 },
	Dragon = { SpeciesId = "Dragon", ModelName = "Dragon", Movement = "Flying", HoverHeight = 2, YawOffset = -90 },
	Piggy = { SpeciesId = "Piggy", ModelName = "Piggy", Movement = "Ground", YawOffset = -90 },
	Raccoon = { SpeciesId = "Raccoon", ModelName = "Raccoon", Movement = "Ground", YawOffset = -90 },
	Rat = { SpeciesId = "Rat", ModelName = "Rat", Movement = "Ground", YawOffset = -90 },
	Turtle = { SpeciesId = "Turtle", ModelName = "Turtle", Movement = "Ground", YawOffset = -90 },
}

local aliases = { drago = "Dragon" }
for id, definition in pairs(pets) do
	aliases[string.lower(id)] = id
	table.freeze(definition)
end

return table.freeze({ Pets = table.freeze(pets), Aliases = table.freeze(aliases) })
