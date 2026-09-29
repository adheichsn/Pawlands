local PetInventoryService = require(script.Parent.Pets.PetInventoryService)
local PetPartyService = require(script.Parent.Pets.PetPartyService)
local StudioPetPreview = require(script.Parent.Pets.StudioPetPreview)

PetInventoryService.Start()
PetPartyService.Start(PetInventoryService)
StudioPetPreview.Start(PetPartyService, PetInventoryService)
print("[Pawlands] Pet ownership, party, and follow foundation ready.")
