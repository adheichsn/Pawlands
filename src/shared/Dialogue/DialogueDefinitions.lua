local TutorialConfig = require(script.Parent.Parent.Config.Tutorial)

local Definitions = {}

local function tutorialStartNode(player)
	local stage = player and player:GetAttribute(TutorialConfig.StageAttributeName)
	if stage == TutorialConfig.Stages.GoToZone then
		return "GoToZoneReminder"
	elseif stage == TutorialConfig.Stages.InCombat then
		return "CombatReminder"
	elseif stage == TutorialConfig.Stages.ReturnToAlex then
		return "ReturnComplete"
	elseif stage == TutorialConfig.Stages.Completed then
		return "Completed"
	end
	return "Welcome"
end

local byId = {
	TutorialAlex = {
		Speaker = "Alex",
		StartNode = "Welcome",
		ResolveStartNode = tutorialStartNode,
		Nodes = {
			Welcome = {
				Text = "Hey there! Welcome to Stone Island.",
				Next = "CombatIntro",
			},
			CombatIntro = {
				Text = "When you're ready, I can show you how combat works.",
				Choices = {
					{
						Id = "Ready",
						Text = "I'm ready.",
						Action = TutorialConfig.AcceptCombatAction,
						Next = "ReadyResponse",
					},
					{
						Id = "Later",
						Text = "Maybe later.",
						Next = "LaterResponse",
					},
				},
			},
			ReadyResponse = {
				Text = "Head to the training area. Show me what you can do.",
			},
			LaterResponse = {
				Text = "No problem. Talk to me again whenever you're ready.",
			},
			GoToZoneReminder = {
				Text = "The training area is just ahead. Head there when you're ready.",
			},
			CombatReminder = {
				Text = "Stay focused. Finish the training Slimes, then come back to me.",
			},
			ReturnComplete = {
				Text = "Nice work! You handled those Slimes well.",
				Choices = {
					{
						Id = "FinishTraining",
						Text = "Continue",
						Action = TutorialConfig.CompleteCombatAction,
						Close = true,
					},
				},
			},
			Completed = {
				Text = "Good work. You're ready for the next step of your adventure.",
			},
		},
	},
}

local idByNpcName = {
	Alex = "TutorialAlex",
}

function Definitions.ResolveIdFromNpcName(npcName)
	return idByNpcName[npcName]
end

function Definitions.Get(dialogueId)
	return byId[dialogueId]
end

return table.freeze(Definitions)
