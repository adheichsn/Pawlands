local Controller = require(script.Parent.Pets.PetFollowController)

Controller.Start()
script.Destroying:Connect(Controller.Stop)
