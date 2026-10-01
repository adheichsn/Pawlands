local Definitions = {}

local byId = {
	TutorialAlex = {
		Speaker = "Alex",
		StartNode = "Welcome",
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
				Text = "Great. Come back to me when you're ready to begin the training mission.",
			},
			LaterResponse = {
				Text = "No problem. Talk to me again whenever you're ready.",
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
