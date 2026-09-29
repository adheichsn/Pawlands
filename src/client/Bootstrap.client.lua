local PetFollowController = require(script.Parent.Pets.PetFollowController)
local PlayerMovementController = require(script.Parent.Player.PlayerMovementController)

PetFollowController.Start()
PlayerMovementController.Start()

script.Destroying:Connect(function()
	PlayerMovementController.Stop()
	PetFollowController.Stop()
end)
