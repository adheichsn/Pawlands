local Players = game:GetService("Players")

local TextNotificationController = {}
local player = Players.LocalPlayer
local started = false
local connections = {}
local refs = nil
local activeByKey = {}
local warnedMissing = false

local TEMPLATE_NAMES = table.freeze({
	AdminTile = true,
	EventTile = true,
	IndexTile = true,
	LocationTile = true,
	Main = true,
	TextTile = true,
	Title = true,
})

local TEXT_NAME_PRIORITY = table.freeze({
	"Text",
	"Message",
	"Label",
	"Description",
	"Title",
})

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function isTextObject(instance)
	return instance and (instance:IsA("TextLabel") or instance:IsA("TextButton"))
end

local function findTextObject(root)
	if isTextObject(root) then
		return root
	end
	for _, name in ipairs(TEXT_NAME_PRIORITY) do
		local candidate = root:FindFirstChild(name, true)
		if isTextObject(candidate) then
			return candidate
		end
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if isTextObject(descendant) then
			return descendant
		end
	end
	return nil
end

local function hideAuthoredTemplates(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if TEMPLATE_NAMES[child.Name] and child:IsA("GuiObject") then
			child.Visible = false
		end
	end
end

local function resolveRefs()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild("TextNotifications")
	if not gui or not gui:IsA("ScreenGui") then
		return nil
	end
	local frame = gui:FindFirstChild("Frame")
	local template = frame and frame:FindFirstChild("TextTile")
	if not frame or not frame:IsA("GuiObject") or not template or not template:IsA("GuiObject") then
		return nil
	end
	local templateText = findTextObject(template)
	if not templateText then
		return nil
	end
	hideAuthoredTemplates(frame)
	return {
		Gui = gui,
		Frame = frame,
		Template = template,
	}
end

local function ensureRefs()
	if refs and refs.Gui.Parent and refs.Frame.Parent and refs.Template.Parent then
		return refs
	end
	refs = resolveRefs()
	return refs
end

local function destroyRecord(key)
	local record = activeByKey[key]
	if not record then
		return
	end
	if record.Tile and record.Tile.Parent then
		record.Tile:Destroy()
	end
	activeByKey[key] = nil
end

local function createRecord(key, text)
	local current = ensureRefs()
	if not current then
		return nil
	end
	local tile = current.Template:Clone()
	tile.Name = "Runtime_" .. tostring(key)
	local textObject = findTextObject(tile)
	if not textObject then
		tile:Destroy()
		return nil
	end
	textObject.Text = text
	tile.Visible = true
	tile.Parent = current.Frame
	current.Gui.Enabled = true
	local record = {
		Tile = tile,
		TextObject = textObject,
		Text = text,
	}
	activeByKey[key] = record
	return record
end

function TextNotificationController.ShowText(key, text)
	if not started or type(key) ~= "string" or key == "" or type(text) ~= "string" or text == "" then
		return false
	end
	local record = activeByKey[key]
	if not record or not record.Tile or not record.Tile.Parent then
		destroyRecord(key)
		return createRecord(key, text) ~= nil
	end
	if record.Text ~= text then
		record.Text = text
		record.TextObject.Text = text
	end
	return true
end

function TextNotificationController.Clear(key)
	if type(key) == "string" then
		destroyRecord(key)
	end
end

function TextNotificationController.Start()
	if started then
		return
	end
	started = true
	local playerGui = player:WaitForChild("PlayerGui")
	table.insert(connections, playerGui.ChildAdded:Connect(function(child)
		if child.Name == "TextNotifications" then
			refs = nil
			local pending = {}
			for key, record in pairs(activeByKey) do
				table.insert(pending, { Key = key, Text = record.Text })
			end
			for _, item in ipairs(pending) do
				destroyRecord(item.Key)
				createRecord(item.Key, item.Text)
			end
		end
	end))
	ensureRefs()
	task.delay(3, function()
		if started and not ensureRefs() and not warnedMissing then
			warnedMissing = true
			warn("[Pawlands Notifications] Studio-owned TextNotifications > Frame > TextTile template is missing required runtime anchors.")
		end
	end)
end

function TextNotificationController.Stop()
	if not started then
		return
	end
	started = false
	disconnectAll()
	local keys = {}
	for key in pairs(activeByKey) do
		table.insert(keys, key)
	end
	for _, key in ipairs(keys) do
		destroyRecord(key)
	end
	refs = nil
end

return TextNotificationController
