local Players = game:GetService("Players")

local TextNotificationController = {}
local player = Players.LocalPlayer
local started = false
local connections = {}
local refs = nil
local activeByKey = {}
local warnedMissing = false
local isolatedFrame = nil
local previewConnections = {}

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

local function disconnectPreviewConnections()
	for _, connection in ipairs(previewConnections) do
		connection:Disconnect()
	end
	table.clear(previewConnections)
	isolatedFrame = nil
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

local function isRuntimeTile(child)
	return string.sub(child.Name, 1, 8) == "Runtime_"
end

local function isAuthoredTemplate(child)
	return child.Parent ~= nil and child.Parent == isolatedFrame
		and child:IsA("GuiObject")
		and not isRuntimeTile(child)
end

local function forceTemplateHidden(child)
	if isAuthoredTemplate(child) and child.Visible then
		child.Visible = false
	end
end

local function watchAuthoredTemplate(child)
	if not isAuthoredTemplate(child) then
		return
	end
	forceTemplateHidden(child)
	table.insert(previewConnections, child:GetPropertyChangedSignal("Visible"):Connect(function()
		if started then
			forceTemplateHidden(child)
		end
	end))
end

local function bindPreviewIsolation(frame)
	if isolatedFrame == frame then
		for _, child in ipairs(frame:GetChildren()) do
			forceTemplateHidden(child)
		end
		return
	end
	disconnectPreviewConnections()
	isolatedFrame = frame
	for _, child in ipairs(frame:GetChildren()) do
		watchAuthoredTemplate(child)
	end
	table.insert(previewConnections, frame.ChildAdded:Connect(function(child)
		watchAuthoredTemplate(child)
	end))
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
	bindPreviewIsolation(frame)
	return {
		Gui = gui,
		Frame = frame,
		Template = template,
	}
end

local function ensureRefs()
	if refs and refs.Gui.Parent and refs.Frame.Parent and refs.Template.Parent then
		bindPreviewIsolation(refs.Frame)
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
	local current = ensureRefs()
	if not current then
		return false
	end
	bindPreviewIsolation(current.Frame)
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
	disconnectPreviewConnections()
end

return TextNotificationController
