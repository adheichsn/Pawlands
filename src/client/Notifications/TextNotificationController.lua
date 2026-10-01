local Players = game:GetService("Players")

local TextNotificationController = {}
local player = Players.LocalPlayer
local started = false
local connections = {}
local refs = nil
local activeByKey = {}
local warnedMissing = false
local warnedSpecializedMissing = false
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

local function isImageObject(instance)
	return instance and (instance:IsA("ImageLabel") or instance:IsA("ImageButton"))
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
	local textTemplate = frame and frame:FindFirstChild("TextTile")
	if not frame or not frame:IsA("GuiObject") or not textTemplate or not textTemplate:IsA("GuiObject") then
		return nil
	end
	local templateText = findTextObject(textTemplate)
	if not templateText then
		return nil
	end
	bindPreviewIsolation(frame)
	return {
		Gui = gui,
		Frame = frame,
		TextTemplate = textTemplate,
		IndexTemplate = frame:FindFirstChild("IndexTile"),
		RewardTemplate = frame:FindFirstChild("Tile"),
	}
end

local function ensureRefs()
	if refs and refs.Gui.Parent and refs.Frame.Parent and refs.TextTemplate.Parent then
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

local function resolveIndexAnchors(tile)
	local textFrame = tile and tile:FindFirstChild("TextFrame")
	local header = textFrame and textFrame:FindFirstChild("Header")
	local label = textFrame and textFrame:FindFirstChild("Label")
	if not isTextObject(header) or not isTextObject(label) then
		return nil
	end
	return {
		Header = header,
		Label = label,
	}
end

local function resolveRewardAnchors(tile)
	local textFrame = tile and tile:FindFirstChild("TextFrame")
	local header = textFrame and textFrame:FindFirstChild("Header")
	local label = textFrame and textFrame:FindFirstChild("Label")
	local vectorFrame = textFrame and textFrame:FindFirstChild("VectorFrame")
	local vector = vectorFrame and vectorFrame:FindFirstChild("Vector")
	local quantity = vectorFrame and vectorFrame:FindFirstChild("Quantity")
	local labelStroke = label and label:FindFirstChildOfClass("UIStroke")
	local labelGradient = label and label:FindFirstChildOfClass("UIGradient")
	if not isTextObject(header)
		or not isTextObject(label)
		or not isImageObject(vector)
		or not isTextObject(quantity)
		or not labelStroke
	then
		return nil
	end
	return {
		Header = header,
		Label = label,
		Vector = vector,
		Quantity = quantity,
		LabelStroke = labelStroke,
		LabelGradient = labelGradient,
	}
end

local function applyRewardNameColor(anchors, rarityColor)
	local color = typeof(rarityColor) == "Color3" and rarityColor or Color3.new(1, 1, 1)
	if anchors.LabelGradient then
		anchors.Label.TextColor3 = Color3.new(1, 1, 1)
		anchors.LabelGradient.Color = ColorSequence.new(color)
	else
		anchors.Label.TextColor3 = color
	end
	-- The authored Label owns the outline through its child UIStroke.
	-- Keep the outline on the authored child UIStroke instead of built-in text stroke properties.
	anchors.LabelStroke.Enabled = true
	anchors.LabelStroke.Color = Color3.new(0, 0, 0)
	anchors.LabelStroke.Transparency = 0
end

local function createRecord(key, kind, payload)
	local current = ensureRefs()
	if not current then
		return nil
	end

	local template
	if kind == "Text" then
		template = current.TextTemplate
	elseif kind == "Index" then
		template = current.IndexTemplate
	elseif kind == "Reward" then
		template = current.RewardTemplate
	end
	if not template or not template:IsA("GuiObject") then
		return nil
	end

	local tile = template:Clone()
	tile.Name = "Runtime_" .. tostring(key)
	local anchors = nil
	if kind == "Text" then
		local textObject = findTextObject(tile)
		if not textObject then
			tile:Destroy()
			return nil
		end
		textObject.Text = payload.Text
		anchors = { Text = textObject }
	elseif kind == "Index" then
		anchors = resolveIndexAnchors(tile)
		if not anchors then
			tile:Destroy()
			return nil
		end
		anchors.Header.Text = payload.Header
		anchors.Label.Text = payload.Label
	elseif kind == "Reward" then
		anchors = resolveRewardAnchors(tile)
		if not anchors then
			tile:Destroy()
			return nil
		end
		anchors.Header.Text = payload.Header
		anchors.Label.Text = payload.Name
		anchors.Vector.Image = payload.Icon
		anchors.Quantity.Text = payload.Quantity
		applyRewardNameColor(anchors, payload.Color)
	else
		tile:Destroy()
		return nil
	end

	tile.Visible = true
	tile.Parent = current.Frame
	current.Gui.Enabled = true
	local record = {
		Tile = tile,
		Kind = kind,
		Payload = payload,
		Anchors = anchors,
	}
	activeByKey[key] = record
	return record
end

local function replaceRecord(key, kind, payload)
	destroyRecord(key)
	return createRecord(key, kind, payload) ~= nil
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
	if not record or not record.Tile or not record.Tile.Parent or record.Kind ~= "Text" then
		return replaceRecord(key, "Text", { Text = text })
	end
	if record.Payload.Text ~= text then
		record.Payload = { Text = text }
		record.Anchors.Text.Text = text
	end
	return true
end

function TextNotificationController.ShowIndex(key, header, label)
	if not started or type(key) ~= "string" or key == "" then
		return false
	end
	local payload = {
		Header = type(header) == "string" and header ~= "" and header or "Index:",
		Label = type(label) == "string" and label ~= "" and label or "New species found!",
	}
	return replaceRecord(key, "Index", payload)
end

function TextNotificationController.ShowReward(key, name, quantity, rarityColor, icon)
	if not started
		or type(key) ~= "string"
		or key == ""
		or type(name) ~= "string"
		or name == ""
		or type(icon) ~= "string"
		or icon == ""
	then
		return false
	end
	local payload = {
		Header = "You got:",
		Name = name,
		Icon = icon,
		Quantity = type(quantity) == "string" and quantity ~= "" and quantity or "x1",
		Color = rarityColor,
	}
	return replaceRecord(key, "Reward", payload)
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
				table.insert(pending, { Key = key, Kind = record.Kind, Payload = record.Payload })
			end
			for _, item in ipairs(pending) do
				destroyRecord(item.Key)
				createRecord(item.Key, item.Kind, item.Payload)
			end
		end
	end))
	local current = ensureRefs()
	task.delay(3, function()
		if started and not ensureRefs() and not warnedMissing then
			warnedMissing = true
			warn("[Pawlands Notifications] Studio-owned TextNotifications > Frame > TextTile template is missing required runtime anchors.")
			return
		end
		local ready = ensureRefs()
		if started and ready and not warnedSpecializedMissing then
			local indexReady = ready.IndexTemplate and resolveIndexAnchors(ready.IndexTemplate) ~= nil
			local rewardReady = ready.RewardTemplate and resolveRewardAnchors(ready.RewardTemplate) ~= nil
			if not indexReady or not rewardReady then
				warnedSpecializedMissing = true
				warn("[Pawlands Notifications] IndexTile or Tile is missing authored Header/Label/Vector/Quantity/UIStroke anchors required by starter Pet acquisition feedback.")
			end
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
