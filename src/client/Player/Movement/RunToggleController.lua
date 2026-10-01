local UserInputService = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.PlayerMovement)
local InteractionLock = require(script.Parent.Parent.Parent.Interaction.InteractionLock)

local RunToggleController = {}
RunToggleController.__index = RunToggleController

local function isToggleKey(keyCode)
	for _, configured in ipairs(Config.RunToggleKeys) do
		if keyCode == configured then
			return true
		end
	end
	return false
end

function RunToggleController.new(changed)
	local self = setmetatable({
		Running = false,
		Changed = changed,
	}, RunToggleController)

	self.Connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or UserInputService:GetFocusedTextBox()
			or InteractionLock.IsLockedExcept("Inventory")
		then
			return
		end
		if not isToggleKey(input.KeyCode) then
			return
		end
		self:SetRunning(not self.Running)
	end)

	return self
end

function RunToggleController:SetRunning(value)
	value = value == true
	if self.Running == value then
		return
	end
	self.Running = value
	if self.Changed then
		self.Changed(value)
	end
end

function RunToggleController:Reset()
	self:SetRunning(false)
end

function RunToggleController:IsRunning()
	return self.Running
end

function RunToggleController:Destroy()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	self.Changed = nil
end

return RunToggleController
