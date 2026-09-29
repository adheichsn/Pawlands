-- Slime RNG reference uses this rig-compatible looping idle animation.
-- Runtime loading can still be rejected by Roblox if the asset is not permitted
-- for the Pawlands experience; movement remains functional when loading fails.
local function asset(id)
	return "rbxassetid://" .. tostring(id)
end

return table.freeze({
	Idle = asset(83416013845556),
})
