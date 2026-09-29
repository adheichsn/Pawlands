local PetInventoryService = require(script.Parent.Pets.PetInventoryService)
local PetPartyService = require(script.Parent.Pets.PetPartyService)
local StudioPetPreview = require(script.Parent.Pets.StudioPetPreview)
local SlimeMovementService = require(script.Parent.Slimes.SlimeMovementService)

PetInventoryService.Start()
PetPartyService.Start(PetInventoryService)
StudioPetPreview.Start(PetPartyService, PetInventoryService)
SlimeMovementService.Start()
print("[Pawlands] Pet ownership, party, follow, player movement, and slime movement foundations ready.")

script.Destroying:Connect(function()
	SlimeMovementService.Stop()
end)
