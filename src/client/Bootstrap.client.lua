local PetFollowController = require(script.Parent.Pets.PetFollowController)
local PlayerMovementController = require(script.Parent.Player.PlayerMovementController)
local PlayerCombatController = require(script.Parent.Combat.PlayerCombatController)

PetFollowController.Start()
PlayerMovementController.Start()
PlayerCombatController.Start()

script.Destroying:Connect(function()
	PlayerCombatController.Stop()
	PlayerMovementController.Stop()
	PetFollowController.Stop()
end)
