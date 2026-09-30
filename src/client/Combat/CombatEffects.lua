local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local Config = require(Shared.Config.CombatEffects)

local CombatEffects = {}
local warned = {}

local function warnOnce(key, message)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

local function combatAssets()
	local assets = ReplicatedStorage:FindFirstChild(Config.AssetsRootName)
	local combat = assets and assets:FindFirstChild(Config.CombatFolderName)
	if not combat then
		warnOnce(
			"CombatAssets",
			"[Pawlands CombatEffects] Missing ReplicatedStorage/Assets/Combat Studio-authored assets."
		)
	end
	return combat
end




local function petCombatAssets()
	local combat = combatAssets()
	local petCombat = combat and combat:FindFirstChild(Config.PetCombat.FolderName)
	if not petCombat then
		warnOnce(
			"PetCombatAssets",
			"[Pawlands CombatEffects] Missing Studio-authored Combat/PetCombat assets."
		)
	end
	return petCombat
end

local function resolveTargetPart(target, preferredName)
	if not target then
		return nil
	end
	if target:IsA("BasePart") then
		return target
	end
	if target:IsA("Model") then
		local preferred = target:FindFirstChild(preferredName or Config.RootPartName, true)
		if preferred and preferred:IsA("BasePart") then
			return preferred
		end
		if target.PrimaryPart then
			return target.PrimaryPart
		end
		return target:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function playSoundTemplate(soundTemplate, parent)
	if not soundTemplate or not soundTemplate:IsA("Sound") or not parent then
		return
	end
	local sound = soundTemplate:Clone()
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, Config.SoundCleanupSeconds)
end

local function emitDescendants(container, playSounds)
	if playSounds == nil then
		playSounds = true
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
			local count = tonumber(descendant:GetAttribute("EmitCount")) or Config.DefaultEmitCount
			descendant:Emit(math.max(0, math.floor(count + 0.5)))
		elseif playSounds and descendant:IsA("Sound") then
			descendant:Play()
		end
	end

	if container:IsA("ParticleEmitter") then
		container.Enabled = false
		local count = tonumber(container:GetAttribute("EmitCount")) or Config.DefaultEmitCount
		container:Emit(math.max(0, math.floor(count + 0.5)))
	elseif playSounds and container:IsA("Sound") then
		container:Play()
	end
end

local function spawnTemplateAtPart(template, targetPart, playSounds)
	if not template or not targetPart then
		return nil
	end

	-- Battlegrounds HitEffect stores the authored presentation inside an Attachment.
	-- Clone that Attachment directly so no runtime GUI/VFX primitives are constructed.
	local authoredAttachment = template:IsA("Attachment") and template
		or template:FindFirstChildWhichIsA("Attachment", true)
	if authoredAttachment then
		local clone = authoredAttachment:Clone()
		clone.Parent = targetPart
		emitDescendants(clone, playSounds)
		Debris:AddItem(clone, Config.EffectCleanupSeconds)
		return clone
	end

	local clone = template:Clone()
	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false
		clone.CFrame = targetPart.CFrame
		clone.Parent = Workspace
	elseif clone:IsA("Model") then
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
			end
		end
		clone.Parent = Workspace
		clone:PivotTo(targetPart.CFrame)
	else
		clone.Parent = targetPart
	end

	emitDescendants(clone, playSounds)
	Debris:AddItem(clone, Config.EffectCleanupSeconds)
	return clone
end

function CombatEffects.PlaySwing(character, comboIndex)
	local combat = combatAssets()
	local playerToSlime = combat and combat:FindFirstChild(Config.PlayerToSlime.FolderName)
	local folder = playerToSlime and playerToSlime:FindFirstChild(Config.PlayerToSlime.SwingFolderName)
	local index = math.clamp(math.floor(tonumber(comboIndex) or 1), 1, 4)
	local sound = folder and folder:FindFirstChild(Config.PlayerToSlime.SwingPrefix .. tostring(index))
	local root = resolveTargetPart(character, Config.PlayerRootPartName)
	if not sound or not sound:IsA("Sound") then
		warnOnce(
			"PlayerSwing",
			"[Pawlands CombatEffects] Missing Studio-authored PlayerToSlime/SwingSFX/Swing1..4 sounds."
		)
		return
	end
	playSoundTemplate(sound, root)
end

function CombatEffects.PlayPlayerHitSlime(slimeModel, hitSerial)
	local combat = combatAssets()
	local playerToSlime = combat and combat:FindFirstChild(Config.PlayerToSlime.FolderName)
	local root = resolveTargetPart(slimeModel, Config.RootPartName)
	if not playerToSlime or not root then
		return
	end

	local effect = playerToSlime:FindFirstChild(Config.PlayerToSlime.HitEffectName)
	if effect then
		spawnTemplateAtPart(effect, root)
	else
		warnOnce(
			"PlayerHitEffect",
			"[Pawlands CombatEffects] Missing Studio-authored PlayerToSlime/HitEffect template."
		)
	end

	local soundFolder = playerToSlime:FindFirstChild(Config.PlayerToSlime.HitSoundFolderName)
	local index = ((math.max(1, math.floor(tonumber(hitSerial) or 1)) - 1) % 4) + 1
	local sound = soundFolder and soundFolder:FindFirstChild(Config.PlayerToSlime.HitPrefix .. tostring(index))
	if sound and sound:IsA("Sound") then
		playSoundTemplate(sound, root)
	else
		warnOnce(
			"PlayerHitSound",
			"[Pawlands CombatEffects] Missing Studio-authored PlayerToSlime/HitSFX/Hit1..4 sounds."
		)
	end
end

function CombatEffects.PlayPetHitSlime(slimeModel)
	local petCombat = petCombatAssets()
	local folder = petCombat and petCombat:FindFirstChild(Config.PetCombat.PetToSlime.FolderName)
	local template = folder and folder:FindFirstChild(Config.PetCombat.PetToSlime.HitTemplateName)
	local root = resolveTargetPart(slimeModel, Config.RootPartName)
	if not template then
		warnOnce(
			"PetHitSlime",
			"[Pawlands CombatEffects] Missing Studio-authored PetCombat/PetToSlime/HitSplat template."
		)
		return
	end
	spawnTemplateAtPart(template, root)
end

function CombatEffects.PlaySlimeHitPet(petModel, playSound)
	local petCombat = petCombatAssets()
	local folder = petCombat and petCombat:FindFirstChild(Config.PetCombat.SlimeToPet.FolderName)
	local template = folder and folder:FindFirstChild(Config.PetCombat.SlimeToPet.HitTemplateName)
	local root = resolveTargetPart(petModel, Config.PetRootPartName)
	if not template then
		warnOnce(
			"SlimeHitPet",
			"[Pawlands CombatEffects] Missing Studio-authored PetCombat/SlimeToPet/HitSplat template."
		)
		return
	end
	spawnTemplateAtPart(template, root, playSound)
end

function CombatEffects.PlayPetKO(petModel)
	local petCombat = petCombatAssets()
	local folder = petCombat and petCombat:FindFirstChild(Config.PetCombat.PetKO.FolderName)
	local template = folder and folder:FindFirstChild(Config.PetCombat.PetKO.TemplateName)
	local root = resolveTargetPart(petModel, Config.PetRootPartName)
	if not template then
		warnOnce(
			"PetKO",
			"[Pawlands CombatEffects] Missing Studio-authored PetCombat/PetKO/KnockedOut template."
		)
		return
	end
	spawnTemplateAtPart(template, root)
end

function CombatEffects.PlaySlimeHitPlayer(character)
	local combat = combatAssets()
	local slimeToPlayer = combat and combat:FindFirstChild(Config.SlimeToPlayer.FolderName)
	local template = slimeToPlayer and slimeToPlayer:FindFirstChild(Config.SlimeToPlayer.HitTemplateName)
	local root = resolveTargetPart(character, Config.PlayerRootPartName)
	if not template then
		warnOnce(
			"SlimeHitPlayer",
			"[Pawlands CombatEffects] Missing Studio-authored SlimeToPlayer/Hit template."
		)
		return
	end
	spawnTemplateAtPart(template, root)
end

function CombatEffects.PlaySlimeDefeat(slimeModel)
	local combat = combatAssets()
	local folder = combat and combat:FindFirstChild(Config.SlimeDefeat.FolderName)
	local template = folder and folder:FindFirstChild(Config.SlimeDefeat.TemplateName)
	local root = resolveTargetPart(slimeModel, Config.RootPartName)
	if not template then
		warnOnce(
			"SlimeDefeat",
			"[Pawlands CombatEffects] Missing Studio-authored KnockedOut/KnockedOut template."
		)
		return
	end
	spawnTemplateAtPart(template, root)
end

return CombatEffects
