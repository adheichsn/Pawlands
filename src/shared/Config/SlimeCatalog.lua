-- Studio-owned slime models live under ReplicatedStorage/Assets/Slimes/StoneIsland.
-- The order is stable so spawn slots and chase-ring slots remain deterministic.
local variants = {
	{ Id = "goopy", ModelName = "goopy" },
	{ Id = "derpy", ModelName = "derpy" },
	{ Id = "sunset", ModelName = "sunset" },
	{ Id = "fin", ModelName = "fin" },
}

for _, definition in ipairs(variants) do
	table.freeze(definition)
end

return table.freeze({
	AssetPath = table.freeze({ "Assets", "Slimes", "StoneIsland" }),
	Variants = table.freeze(variants),
})
