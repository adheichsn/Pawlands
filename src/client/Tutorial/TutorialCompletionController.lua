local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Pawlands = ReplicatedStorage:WaitForChild("Pawlands")
local Shared = Pawlands:WaitForChild("Shared")
local TutorialConfig = require(Shared.Config.Tutorial)

local TutorialCompletionController = {}

local player = Players.LocalPlayer
local started = false
local connections = {}
local refs = nil
local activeTweens = {}
local generation = 0
local previousStage = nil
local completionObserved = false
local pendingPlayback = false
local playing = false
local warnedMissing = false

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function cancelTweens()
	for _, tween in ipairs(activeTweens) do
		pcall(function()
			tween:Cancel()
		end)
	end
	table.clear(activeTweens)
end

local function stageOf()
	local stage = player:GetAttribute(TutorialConfig.StageAttributeName)
	if type(stage) ~= "string" then
		return TutorialConfig.Stages.NotStarted
	end
	return stage
end

local function collectPieces(container)
	local pieces = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject")
			and string.sub(child.Name, 1, #TutorialConfig.CompletionCelebration.PiecePrefix)
				== TutorialConfig.CompletionCelebration.PiecePrefix
		then
			table.insert(pieces, child)
		end
	end
	table.sort(pieces, function(a, b)
		return a.Name < b.Name
	end)
	return pieces
end

local function capturePieceDefaults(piece)
	return {
		Position = piece.Position,
		Rotation = piece.Rotation,
		BackgroundTransparency = piece.BackgroundTransparency,
		Visible = piece.Visible,
	}
end

local function resolveRefs()
	local celebration = TutorialConfig.CompletionCelebration
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild(celebration.GuiName)
	if not gui or not gui:IsA("ScreenGui") then
		return nil
	end

	local main = gui:FindFirstChild(celebration.MainName)
	local title = main and main:FindFirstChild(celebration.TitleName)
	local popScale = title and title:FindFirstChild(celebration.PopScaleName)
	local left = main and main:FindFirstChild(celebration.LeftConfettiName)
	local right = main and main:FindFirstChild(celebration.RightConfettiName)
	local sound = gui:FindFirstChild(celebration.SoundName)

	if not main or not main:IsA("GuiObject")
		or not title or not title:IsA("GuiObject")
		or not popScale or not popScale:IsA("UIScale")
		or not left or not left:IsA("GuiObject")
		or not right or not right:IsA("GuiObject")
		or not sound or not sound:IsA("Sound")
	then
		return nil
	end

	local leftPieces = collectPieces(left)
	local rightPieces = collectPieces(right)
	if #leftPieces == 0 or #rightPieces == 0 then
		return nil
	end

	local pieceDefaults = {}
	for _, piece in ipairs(leftPieces) do
		pieceDefaults[piece] = capturePieceDefaults(piece)
	end
	for _, piece in ipairs(rightPieces) do
		pieceDefaults[piece] = capturePieceDefaults(piece)
	end

	return {
		Gui = gui,
		Main = main,
		Title = title,
		PopScale = popScale,
		AuthoredPopScale = popScale.Scale,
		LeftPieces = leftPieces,
		RightPieces = rightPieces,
		PieceDefaults = pieceDefaults,
		Sound = sound,
	}
end

local function restorePiece(current, piece)
	local default = current.PieceDefaults[piece]
	if not default or not piece.Parent then
		return
	end
	piece.Position = default.Position
	piece.Rotation = default.Rotation
	piece.BackgroundTransparency = default.BackgroundTransparency
	piece.Visible = default.Visible
end

local function resetPresentation(current, disableGui)
	cancelTweens()
	if not current then
		return
	end
	if current.Sound and current.Sound.Parent then
		current.Sound:Stop()
		current.Sound.TimePosition = 0
	end
	if current.PopScale and current.PopScale.Parent then
		current.PopScale.Scale = current.AuthoredPopScale
	end
	for _, piece in ipairs(current.LeftPieces) do
		restorePiece(current, piece)
	end
	for _, piece in ipairs(current.RightPieces) do
		restorePiece(current, piece)
	end
	if disableGui and current.Gui and current.Gui.Parent then
		current.Gui.Enabled = false
	end
end

local function registerTween(tween)
	table.insert(activeTweens, tween)
	tween:Play()
	return tween
end

local function authoredNumber(gui, attributeName, fallback)
	local value = gui:GetAttribute(attributeName)
	if type(value) == "number" then
		return value
	end
	return fallback
end

local function canAnimate(token, piece)
	return started and token == generation and playing and piece.Parent ~= nil
end

local function restorePieceForBurst(current, piece, hidden)
	local default = current.PieceDefaults[piece]
	if not default or not piece.Parent then
		return
	end
	piece.Position = default.Position
	piece.Rotation = default.Rotation
	piece.Visible = true
	piece.BackgroundTransparency = hidden and 1 or default.BackgroundTransparency
end

local function launchPieceTween(piece, targetX, targetY, targetRotation, duration)
	return registerTween(TweenService:Create(
		piece,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromScale(targetX, targetY),
			Rotation = targetRotation,
		}
	))
end

local function secondWaveTarget(celebration, burstX, burstY, burstRotation, isLeft, index)
	-- Deterministic per-piece spread. Values intentionally extend beyond the
	-- authored corner container's 0..1 range; ClipsDescendants is authored off,
	-- so the second burst can reach farther toward the viewport center/top.
	local horizontalSeed = ((index * 37) % 101) / 100
	local verticalSeed = ((index * 53) % 101) / 100
	local horizontalPush = celebration.SecondWaveHorizontalPushMin
		+ (celebration.SecondWaveHorizontalPushMax - celebration.SecondWaveHorizontalPushMin) * horizontalSeed
	local verticalLift = celebration.SecondWaveVerticalLiftMin
		+ (celebration.SecondWaveVerticalLiftMax - celebration.SecondWaveVerticalLiftMin) * verticalSeed
	local direction = isLeft and 1 or -1
	local spinDirection = index % 2 == 0 and 1 or -1

	return burstX + direction * horizontalPush,
		burstY - verticalLift,
		burstRotation + spinDirection * (celebration.SecondWaveExtraRotation + index * 9)
end

local function playPieceDoubleBurst(current, piece, token, index, isLeft, firstBurstStart, secondBurstStart)
	local celebration = TutorialConfig.CompletionCelebration
	local burstX = piece:GetAttribute("BurstX")
	local burstY = piece:GetAttribute("BurstY")
	local burstRotation = piece:GetAttribute("BurstRotation")
	local burstDelay = piece:GetAttribute("BurstDelay")
	local burstDuration = piece:GetAttribute("BurstDuration")
	if type(burstX) ~= "number"
		or type(burstY) ~= "number"
		or type(burstRotation) ~= "number"
		or type(burstDelay) ~= "number"
		or type(burstDuration) ~= "number"
	then
		return
	end

	local firstStartAt = math.max(0, firstBurstStart + burstDelay * celebration.FirstWaveDelayScale)
	local firstDuration = math.max(0.16, burstDuration * celebration.FirstWaveDurationScale)
	task.delay(firstStartAt, function()
		if not canAnimate(token, piece) then
			return
		end
		restorePieceForBurst(current, piece, false)
		launchPieceTween(piece, burstX, burstY, burstRotation, firstDuration)
	end)

	local secondDelay = burstDelay * celebration.SecondWaveDelayScale
	local secondStartAt = math.max(0, secondBurstStart + secondDelay)
	local resetAt = math.max(0, secondStartAt - celebration.SecondWaveResetGapSeconds)
	task.delay(resetAt, function()
		if not canAnimate(token, piece) then
			return
		end
		restorePieceForBurst(current, piece, true)
	end)

	local targetX, targetY, targetRotation = secondWaveTarget(
		celebration,
		burstX,
		burstY,
		burstRotation,
		isLeft,
		index
	)
	local secondDuration = math.max(0.30, burstDuration * celebration.SecondWaveDurationScale)
	task.delay(secondStartAt, function()
		if not canAnimate(token, piece) then
			return
		end
		restorePieceForBurst(current, piece, false)
		launchPieceTween(piece, targetX, targetY, targetRotation, secondDuration)
	end)

	local fadeAt = secondStartAt + secondDuration * celebration.SecondWaveFadeFraction
	local fadeDuration = math.max(
		celebration.MinimumFadeSeconds,
		secondDuration * (1 - celebration.SecondWaveFadeFraction)
	)
	task.delay(fadeAt, function()
		if not canAnimate(token, piece) then
			return
		end
		registerTween(TweenService:Create(
			piece,
			TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		))
	end)
end

local function beginPlayback(current)
	local celebration = TutorialConfig.CompletionCelebration
	generation += 1
	local token = generation
	playing = true
	pendingPlayback = false
	refs = current

	resetPresentation(current, false)
	current.Gui.Enabled = true
	current.PopScale.Scale = celebration.IntroScale

	local totalDuration = authoredNumber(
		current.Gui,
		"DefaultDuration",
		celebration.DefaultDurationSeconds
	)
	local titlePopStart = authoredNumber(
		current.Gui,
		"TitlePopStart",
		celebration.TitlePopStartSeconds
	)
	local burstStart = authoredNumber(
		current.Gui,
		"ConfettiBurstStart",
		celebration.ConfettiBurstStartSeconds
	)
	-- Keep authored duration as a floor-compatible hint, but the double-burst
	-- polish needs enough room to finish cleanly even on older authored GUIs.
	totalDuration = math.max(totalDuration, celebration.MinimumDurationSeconds)
	local secondBurstStart = celebration.SecondWaveStartSeconds

	if current.Sound.SoundId ~= "" then
		current.Sound.TimePosition = 0
		current.Sound:Play()
	end

	task.delay(math.max(0, titlePopStart), function()
		if not started or token ~= generation or not playing or not current.PopScale.Parent then
			return
		end
		local popTween = registerTween(TweenService:Create(
			current.PopScale,
			TweenInfo.new(celebration.TitlePopSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = celebration.PopScale }
		))
		popTween.Completed:Once(function()
			if not started or token ~= generation or not playing or not current.PopScale.Parent then
				return
			end
			registerTween(TweenService:Create(
				current.PopScale,
				TweenInfo.new(celebration.TitleSettleSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = current.AuthoredPopScale }
			))
		end)
	end)

	for index, piece in ipairs(current.LeftPieces) do
		playPieceDoubleBurst(current, piece, token, index, true, burstStart, secondBurstStart)
	end
	for index, piece in ipairs(current.RightPieces) do
		playPieceDoubleBurst(current, piece, token, index, false, burstStart, secondBurstStart)
	end

	-- A small second title pulse lands with burst #2 without changing authored copy/layout.
	task.delay(math.max(0, secondBurstStart), function()
		if not started or token ~= generation or not playing or not current.PopScale.Parent then
			return
		end
		local pulseTween = registerTween(TweenService:Create(
			current.PopScale,
			TweenInfo.new(celebration.SecondTitlePulseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = celebration.SecondTitlePulseScale }
		))
		pulseTween.Completed:Once(function()
			if not started or token ~= generation or not playing or not current.PopScale.Parent then
				return
			end
			registerTween(TweenService:Create(
				current.PopScale,
				TweenInfo.new(celebration.SecondTitleSettleSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = current.AuthoredPopScale }
			))
		end)
	end)

	task.delay(math.max(0.1, totalDuration), function()
		if not started or token ~= generation or not playing then
			return
		end
		playing = false
		resetPresentation(current, true)
	end)
end

local function tryPlayPending()
	if not started or not pendingPlayback or playing then
		return
	end
	local current = resolveRefs()
	if not current then
		return
	end
	beginPlayback(current)
end

local function onStageChanged()
	local currentStage = stageOf()
	if currentStage == TutorialConfig.Stages.Completed
		and previousStage ~= TutorialConfig.Stages.Completed
		and not completionObserved
	then
		completionObserved = true
		pendingPlayback = true
		tryPlayPending()
	end
	previousStage = currentStage
end

function TutorialCompletionController.Start()
	if started then
		return
	end
	started = true

	local playerGui = player:WaitForChild("PlayerGui")
	previousStage = stageOf()
	-- A Player who joins with an already-completed tutorial must not replay the
	-- one-time completion celebration. Only a live non-Completed -> Completed
	-- transition in this client session is eligible.
	completionObserved = previousStage == TutorialConfig.Stages.Completed
	pendingPlayback = false
	playing = false

	table.insert(connections, player:GetAttributeChangedSignal(TutorialConfig.StageAttributeName):Connect(onStageChanged))
	table.insert(connections, playerGui.ChildAdded:Connect(function(child)
		if child.Name == TutorialConfig.CompletionCelebration.GuiName then
			refs = nil
			task.defer(tryPlayPending)
		end
	end))
	table.insert(connections, playerGui.ChildRemoved:Connect(function(child)
		if child.Name ~= TutorialConfig.CompletionCelebration.GuiName then
			return
		end
		if refs and refs.Gui == child then
			generation += 1
			playing = false
			pendingPlayback = false
			cancelTweens()
			refs = nil
		end
	end))

	task.delay(3, function()
		if not started or warnedMissing then
			return
		end
		if resolveRefs() then
			return
		end
		warnedMissing = true
		warn("[Pawlands Tutorial] Studio-owned TutorialComplete hierarchy is missing required runtime anchors after replication grace.")
	end)
end

function TutorialCompletionController.Stop()
	if not started then
		return
	end
	started = false
	generation += 1
	playing = false
	pendingPlayback = false
	disconnectAll()
	if refs then
		resetPresentation(refs, true)
	else
		cancelTweens()
	end
	refs = nil
	previousStage = nil
	completionObserved = false
	warnedMissing = false
end

return TutorialCompletionController
