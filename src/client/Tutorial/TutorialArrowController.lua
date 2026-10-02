local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Pawlands = ReplicatedStorage:WaitForChild("Pawlands")
local Shared = Pawlands:WaitForChild("Shared")
local TutorialConfig = require(Shared.Config.Tutorial)
local DialogueConfig = require(Shared.Config.Dialogue)

local TutorialArrowController = {}

local player = Players.LocalPlayer
local started = false
local connections = {}
local renderConnection = nil

local TARGET_ALEX = "Alex"
local TARGET_COMBAT_ZONE = "CombatZone"

local desiredTargetKind = nil
local visual = nil
local visualKind = nil
local visualBaseSize = nil
local visualBaseModelScale = nil
local state = "Hidden"
local stateAlpha = 0
local elapsed = 0
local currentPosition = nil
local currentLookTarget = nil
local smoothedMoveDirection = nil
local despawnPosition = nil
local despawnLookTarget = nil
local missingTargetSeconds = 0
local warnedMissingAsset = false

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function stageOf()
	local stage = player:GetAttribute(TutorialConfig.StageAttributeName)
	if type(stage) ~= "string" then
		return TutorialConfig.Stages.NotStarted
	end
	return stage
end

local function dialogueActive()
	return player:GetAttribute(DialogueConfig.ActiveAttributeName) == true
end

local function targetKindForStage(stage)
	if stage == TutorialConfig.Stages.MeetAlex
		or stage == TutorialConfig.Stages.ReturnToAlex
	then
		return TARGET_ALEX
	end
	if stage == TutorialConfig.Stages.GoToZone
		or stage == TutorialConfig.Stages.PetCombatReady
	then
		return TARGET_COMBAT_ZONE
	end
	return nil
end

local function resolveDesiredTargetKind()
	if dialogueActive() then
		return nil
	end
	return targetKindForStage(stageOf())
end

local function resolveTarget(kind)
	local arrowConfig = TutorialConfig.Arrow
	local island = Workspace:FindFirstChild(arrowConfig.WorldRootName)
	if not island then
		return nil
	end

	if kind == TARGET_ALEX then
		local npcFolder = island:FindFirstChild(arrowConfig.NpcFolderName)
		local alex = npcFolder and npcFolder:FindFirstChild(arrowConfig.AlexName)
		local target = alex and alex:FindFirstChild(arrowConfig.AlexTargetPartName)
		return target and target:IsA("BasePart") and target or nil
	end

	if kind == TARGET_COMBAT_ZONE then
		local tutorial = island:FindFirstChild(arrowConfig.TutorialWorldFolderName)
		local zones = tutorial and tutorial:FindFirstChild(arrowConfig.ZonesName)
		local target = zones and zones:FindFirstChild(arrowConfig.CombatZoneName)
		return target and target:IsA("BasePart") and target or nil
	end

	return nil
end

local function getAliveCharacterRoot()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return root, humanoid
end

local function configureVisualInstance(instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.CastShadow = false
	end
	for _, child in ipairs(instance:GetChildren()) do
		configureVisualInstance(child)
	end
end

local function destroyVisual()
	if visual then
		visual:Destroy()
	end
	visual = nil
	visualKind = nil
	visualBaseSize = nil
	visualBaseModelScale = nil
	state = "Hidden"
	stateAlpha = 0
	currentPosition = nil
	currentLookTarget = nil
	smoothedMoveDirection = nil
	despawnPosition = nil
	despawnLookTarget = nil
	missingTargetSeconds = 0
end

local function setVisualScale(scale)
	if not visual then
		return
	end
	scale = math.max(scale, 0.001)
	if visual:IsA("BasePart") then
		if visualBaseSize then
			visual.Size = visualBaseSize * scale
		end
	elseif visual:IsA("Model") and visualBaseModelScale then
		visual:ScaleTo(visualBaseModelScale * scale)
	end
end

local function setVisualPivot(cframe)
	if not visual then
		return
	end
	if visual:IsA("BasePart") then
		visual.CFrame = cframe
	elseif visual:IsA("Model") then
		visual:PivotTo(cframe)
	end
end

local function createVisual(targetKind)
	local arrowConfig = TutorialConfig.Arrow
	local assets = ReplicatedStorage:FindFirstChild(arrowConfig.AssetRootName)
	local tutorialAssets = assets and assets:FindFirstChild(arrowConfig.AssetTutorialFolderName)
	local template = tutorialAssets and tutorialAssets:FindFirstChild(arrowConfig.AssetName)
	if not template or (not template:IsA("BasePart") and not template:IsA("Model")) then
		if not warnedMissingAsset then
			warnedMissingAsset = true
			warn("[Pawlands Tutorial] Studio-owned 3D tutorial ArrowModel is missing or invalid.")
		end
		return false
	end

	visual = template:Clone()
	visual.Name = arrowConfig.RuntimeName
	configureVisualInstance(visual)
	if visual:IsA("BasePart") then
		visualBaseSize = visual.Size
	else
		visualBaseModelScale = visual:GetScale()
	end
	visual.Parent = Workspace
	visualKind = targetKind
	setVisualScale(arrowConfig.MinAnimScale)
	state = "Spawn"
	stateAlpha = 0
	currentPosition = nil
	currentLookTarget = nil
	smoothedMoveDirection = nil
	despawnPosition = nil
	despawnLookTarget = nil
	missingTargetSeconds = 0
	return true
end

local function beginDespawn()
	if not visual then
		return
	end
	if state == "Despawn" then
		return
	end
	state = "Despawn"
	stateAlpha = 0
	despawnPosition = currentPosition
	despawnLookTarget = currentLookTarget
end

local function refreshDesiredTarget()
	local nextKind = resolveDesiredTargetKind()
	if nextKind == desiredTargetKind then
		return
	end
	desiredTargetKind = nextKind
	missingTargetSeconds = 0
	if not desiredTargetKind then
		beginDespawn()
	end
end

local function easeOutCubic(alpha)
	return 1 - (1 - alpha) ^ 3
end

local function updateVisual(dt)
	refreshDesiredTarget()

	if not desiredTargetKind then
		if not visual then
			return
		end
	else
		local target = resolveTarget(desiredTargetKind)
		local root, humanoid = getAliveCharacterRoot()
		if not target or not root or not humanoid then
			missingTargetSeconds += dt
			if visual and missingTargetSeconds >= TutorialConfig.Arrow.TargetMissingGraceSeconds then
				destroyVisual()
			end
			return
		end
		missingTargetSeconds = 0

		if not visual then
			if not createVisual(desiredTargetKind) then
				return
			end
		elseif visualKind ~= desiredTargetKind then
			visualKind = desiredTargetKind
		end

		elapsed += dt
		local arrowConfig = TutorialConfig.Arrow
		local rootPosition = root.Position
		local targetPosition = target.Position
		local distance = (targetPosition - rootPosition).Magnitude

		local moveDirection = humanoid.MoveDirection
		local planarMove = Vector3.new(moveDirection.X, 0, moveDirection.Z)
		local moving = planarMove.Magnitude > 0.05
		planarMove = moving and planarMove.Unit or Vector3.zero
		if not smoothedMoveDirection then
			smoothedMoveDirection = planarMove
		else
			smoothedMoveDirection = smoothedMoveDirection:Lerp(
				planarMove,
				math.clamp(dt * arrowConfig.MoveDirectionLerpSpeed, 0, 1)
			)
		end

		local behindDirection
		if smoothedMoveDirection.Magnitude > 0.05 then
			behindDirection = -smoothedMoveDirection.Unit
		else
			local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if flatLook.Magnitude < 0.001 then
				flatLook = Vector3.new(0, 0, -1)
			end
			behindDirection = -flatLook.Unit
		end

		local backOffset = moving and arrowConfig.BackOffsetWhenMoving or arrowConfig.BackOffsetWhenIdle
		local farBob = math.sin(elapsed * arrowConfig.BobSpeed) * arrowConfig.PlayerBobAmount
		local nearBob = math.sin(elapsed * arrowConfig.BobSpeed) * arrowConfig.TargetBobAmount
		local farPosition = rootPosition
			+ behindDirection * backOffset
			+ Vector3.new(0, arrowConfig.HeightAbovePlayer + farBob, 0)
		local nearPosition = targetPosition + Vector3.new(0, arrowConfig.AboveTargetHeight + nearBob, 0)

		local blend = 0
		if distance <= arrowConfig.TransitionDistance then
			blend = 1 - math.clamp(
				(distance - arrowConfig.NearDistance)
					/ math.max(arrowConfig.TransitionDistance - arrowConfig.NearDistance, 0.001),
				0,
				1
			)
		end

		local targetWorldPosition = farPosition:Lerp(nearPosition, blend)
		if state ~= "Despawn" then
			if not currentPosition then
				currentPosition = targetWorldPosition
			else
				currentPosition = currentPosition:Lerp(
					targetWorldPosition,
					math.clamp(dt * arrowConfig.PositionLerpSpeed, 0, 1)
				)
			end

			local farLookTarget = targetPosition + Vector3.new(0, currentPosition.Y - rootPosition.Y - 0.55, 0)
			local nearLookTarget = targetPosition + Vector3.new(0, 0.08, 0)
			local desiredLookTarget = farLookTarget:Lerp(nearLookTarget, blend)
			if not currentLookTarget then
				currentLookTarget = desiredLookTarget
			else
				currentLookTarget = currentLookTarget:Lerp(
					desiredLookTarget,
					math.clamp(dt * arrowConfig.RotationLerpSpeed, 0, 1)
				)
			end
		end
	end

	if not visual then
		return
	end

	local arrowConfig = TutorialConfig.Arrow
	if state == "Spawn" then
		stateAlpha = math.clamp(stateAlpha + dt / math.max(arrowConfig.SpawnTime, 0.001), 0, 1)
		if stateAlpha >= 1 then
			state = "Active"
		end
	elseif state == "Despawn" then
		stateAlpha = math.clamp(stateAlpha + dt / math.max(arrowConfig.DespawnTime, 0.001), 0, 1)
		if stateAlpha >= 1 then
			destroyVisual()
			return
		end
	end

	local renderPosition = currentPosition or despawnPosition
	local renderLookTarget = currentLookTarget or despawnLookTarget
	if state == "Despawn" then
		renderPosition = despawnPosition or renderPosition
		renderLookTarget = despawnLookTarget or renderLookTarget
	end
	if not renderPosition or not renderLookTarget then
		return
	end
	if (renderLookTarget - renderPosition).Magnitude < 0.01 then
		renderLookTarget = renderPosition + Vector3.new(0, 0, -1)
	end

	local scaleAlpha = 1
	if state == "Spawn" then
		scaleAlpha = arrowConfig.MinAnimScale
			+ (1 - arrowConfig.MinAnimScale) * easeOutCubic(stateAlpha)
	elseif state == "Despawn" then
		local remaining = 1 - stateAlpha
		scaleAlpha = arrowConfig.MinAnimScale
			+ (1 - arrowConfig.MinAnimScale) * remaining
	end

	local lookCFrame = CFrame.lookAt(renderPosition, renderLookTarget)
	local rotation = arrowConfig.RotationOffset
	local correction = CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
	setVisualPivot(lookCFrame * correction)
	setVisualScale(arrowConfig.ArrowScale * scaleAlpha)
end

function TutorialArrowController.Start()
	if started then
		return
	end
	started = true
	warnedMissingAsset = false
	desiredTargetKind = resolveDesiredTargetKind()

	table.insert(connections, player:GetAttributeChangedSignal(TutorialConfig.StageAttributeName):Connect(refreshDesiredTarget))
	table.insert(connections, player:GetAttributeChangedSignal(DialogueConfig.ActiveAttributeName):Connect(refreshDesiredTarget))
	table.insert(connections, player.CharacterAdded:Connect(function()
		destroyVisual()
		desiredTargetKind = resolveDesiredTargetKind()
	end))

	renderConnection = RunService.RenderStepped:Connect(updateVisual)
end

function TutorialArrowController.Stop()
	if not started then
		return
	end
	started = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	disconnectAll()
	destroyVisual()
	desiredTargetKind = nil
	elapsed = 0
end

return TutorialArrowController
