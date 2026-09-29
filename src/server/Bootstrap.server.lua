local PetPartyService = require(script.Parent.Pets.PetPartyService)
local StudioPetPreview = require(script.Parent.Pets.StudioPetPreview)

PetPartyService.Start()
StudioPetPreview.Start(PetPartyService)
print("[Pawlands] Pet follow foundation ready.")
