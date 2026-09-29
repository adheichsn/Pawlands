-- This preset is used ONLY while RunService:IsStudio() is true.
-- It is a visual test party, not an inventory grant or a saved starter reward.
return table.freeze({
	EnablePetPreview = true,
	PreviewParty = table.freeze({ "Bunny", "Cat", "Dog", "Dragon" }),
	EnablePetCommands = true,
})
