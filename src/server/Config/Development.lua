-- Studio-only testing preset. These pets are granted to the temporary session inventory
-- and equipped through the same ownership-validated server path used by normal equip.
return table.freeze({
	EnablePetPreview = false,
	PreviewParty = table.freeze({ "Bunny", "Cat", "Dog", "Dragon" }),
	EnablePetCommands = true,
})
