-- Models remain owned by Studio under Assets/Pets/StoneIsland.
-- Different variants may share a SpeciesId to enforce one species per party.
-- StoneIsland meshes face local -X; -90 degrees maps their face to follow -Z.
-- YawOffset calibrates the artwork after movement lean; it is not player yaw.
local pets = {
	Bunny = { SpeciesId = "Bunny", ModelName = "Bunny", Movement = "Ground", YawOffset = -90, Icon = "rbxassetid://98159714295831" },
	Cat = { SpeciesId = "Cat", ModelName = "Cat", Movement = "Ground", YawOffset = -90, Icon = "rbxassetid://85987199477651" },
	Chicken = { SpeciesId = "Chicken", ModelName = "Chicken", Movement = "Ground", YawOffset = -90, Icon = "rbxassetid://136679292053828" },
	Cow = { SpeciesId = "Cow", ModelName = "Cow", Movement = "Ground", YawOffset = -90, Icon = "rbxassetid://135156787627380" },
	Dog = { SpeciesId = "Dog", ModelName = "Dog", Movement = "Ground", YawOffset = -90, Icon = "rbxassetid://90032050484312" },
	Dragon = { SpeciesId = "Dragon", ModelName = "Dragon", Movement = "Flying", HoverHeight = 2, YawOffset = -90, Icon = "rbxassetid://104047512065229" },
	Piggy = { SpeciesId = "Piggy", ModelName = "Piggy", Movement = "Ground", YawOffset = -90, Icon = "rbxassetid://126802350537519" },
	Raccoon = { SpeciesId = "Raccoon", ModelName = "Raccoon", Movement = "Ground", YawOffset = -90, Icon = "rbxassetid://122391489105244" },
	Rat = { SpeciesId = "Rat", ModelName = "Rat", Movement = "Ground", YawOffset = -90, Icon = "rbxassetid://95053074070336" },
	Turtle = { SpeciesId = "Turtle", ModelName = "Turtle", Movement = "Ground", YawOffset = -90, Icon = "rbxassetid://134759934579975" },
}

local aliases = { drago = "Dragon" }
for id, definition in pairs(pets) do
	aliases[string.lower(id)] = id
	table.freeze(definition)
end

return table.freeze({ Pets = table.freeze(pets), Aliases = table.freeze(aliases) })
