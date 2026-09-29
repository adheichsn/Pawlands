-- Pawlands consumes Animation objects authored inside each individual Slime
-- model. No global/external animation asset is created by runtime code.
-- Keep the inaccessible Slime RNG reference blocked so an old copied model
-- cannot silently reintroduce the Studio permission error.
return table.freeze({
	BlockedAnimationIds = table.freeze({
		["rbxassetid://83416013845556"] = true,
	}),
})
