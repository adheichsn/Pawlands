local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Pawlands"):WaitForChild("Shared")
local CombatConfig = require(Shared.Config.PlayerCombat)
local CombatAnimations = require(Shared.Config.PlayerCombatAnimations)
local CombatEffects = require(script.Parent.CombatEffects)

local PlayerHitReactionController = {}
local stopCurrent

local function loadTrack(animator, name, animationId)
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not track then
		warn("[Pawlands Combat] Failed to load hit reaction " .. name .. ": " .. tostring(track))
		return nil
	end
	track.Name = name
	track.Priority = CombatConfig.HitReaction.AnimationPriority
	track.Looped = false
	return track
end

function PlayerHitReactionController.Start()
	if stopCurrent then
		return
	end

	local player = Players.LocalPlayer
	local characterCleanup
	local randomObject = Random.new()

	local function cleanupCharacter()
		if characterCleanup then
			characterCleanup()
			characterCleanup = nil
		end
	end

	local function bindCharacter(character)
		cleanupCharacter()
		local humanoid = character:WaitForChild("Humanoid")
		local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator")
		local tracks = {}
		for index, animationId in ipairs(CombatAnimations.HitReact.Light) do
			local track = loadTrack(animator, "Pawlands_HitReact_" .. tostring(index), animationId)
			if track then
				table.insert(tracks, track)
			end
		end

		local lastHealth = humanoid.Health
		local lastReactionAt = -math.huge
		local lastIndex = 0
		local generation = 0
		local currentTrack = nil

		local function playLightReaction()
			local now = os.clock()
			if now - lastReactionAt < CombatConfig.HitReaction.RetriggerCooldownSeconds then
				return
			end
			lastReactionAt = now

			local available = #tracks
			if available <= 0 then
				return
			end
			local index = available == 1 and 1 or randomObject:NextInteger(1, available)
			if available > 1 and index == lastIndex then
				index = (index % available) + 1
			end
			lastIndex = index
			local track = tracks[index]
			if not track then
				return
			end

			generation += 1
			local myGeneration = generation
			if currentTrack and currentTrack ~= track and currentTrack.IsPlaying then
				currentTrack:Stop(CombatConfig.HitReaction.FadeSeconds)
			elseif currentTrack == track and track.IsPlaying then
				track:Stop(0)
			end
			currentTrack = track
			track:Play(
				CombatConfig.HitReaction.FadeSeconds,
				1,
				CombatConfig.HitReaction.PlaybackSpeed
			)

			task.delay(CombatConfig.HitReaction.MaxVisibleSeconds, function()
				if generation ~= myGeneration or currentTrack ~= track then
					return
				end
				if track.IsPlaying then
					track:Stop(CombatConfig.HitReaction.FadeSeconds)
				end
				if currentTrack == track then
					currentTrack = nil
				end
			end)
		end

		local healthConnection = humanoid.HealthChanged:Connect(function(health)
			local tookDamage = health < lastHealth - 0.01
			lastHealth = health
			if tookDamage and health > 0 then
				playLightReaction()
			end
		end)

		local lastSlimeHitSerial = tonumber(character:GetAttribute("SlimeHitSerial")) or 0
		local slimeHitConnection = character:GetAttributeChangedSignal("SlimeHitSerial"):Connect(function()
			local serial = tonumber(character:GetAttribute("SlimeHitSerial")) or 0
			if serial <= lastSlimeHitSerial then
				lastSlimeHitSerial = serial
				return
			end
			lastSlimeHitSerial = serial
			CombatEffects.PlaySlimeHitPlayer(character)
		end)

		characterCleanup = function()
			generation += 1
			healthConnection:Disconnect()
			slimeHitConnection:Disconnect()
			if currentTrack and currentTrack.IsPlaying then
				currentTrack:Stop(0)
			end
			for _, track in pairs(tracks) do
				if track then
					track:Destroy()
				end
			end
		end
	end

	local addedConnection = player.CharacterAdded:Connect(bindCharacter)
	local removingConnection = player.CharacterRemoving:Connect(cleanupCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end

	stopCurrent = function()
		addedConnection:Disconnect()
		removingConnection:Disconnect()
		cleanupCharacter()
	end
end

function PlayerHitReactionController.Stop()
	if stopCurrent then
		local stop = stopCurrent
		stopCurrent = nil
		stop()
	end
end

return PlayerHitReactionController
