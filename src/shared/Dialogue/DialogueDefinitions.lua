local TutorialConfig = require(script.Parent.Parent.Config.Tutorial)

local Definitions = {}

local function tutorialStartNode(player)
	local stage = player and player:GetAttribute(TutorialConfig.StageAttributeName)
	if stage == TutorialConfig.Stages.LearnMove then
		return "MovementReminder"
	elseif stage == TutorialConfig.Stages.LearnSprint then
		return "SprintReminder"
	elseif stage == TutorialConfig.Stages.MeetAlex then
		return "Welcome"
	elseif stage == TutorialConfig.Stages.GoToZone then
		return "GoToZoneReminder"
	elseif stage == TutorialConfig.Stages.LearnAttack or stage == TutorialConfig.Stages.InCombat then
		return "CombatReminder"
	elseif stage == TutorialConfig.Stages.ReturnToAlex then
		return "ReturnComplete"
	elseif stage == TutorialConfig.Stages.SoloComplete then
		return "StarterIntro"
	elseif stage == TutorialConfig.Stages.ChooseStarterPet then
		return "StarterChoiceActive"
	elseif stage == TutorialConfig.Stages.EquipStarterPet then
		return "EquipStarterPetReminder"
	elseif stage == TutorialConfig.Stages.PetCombatReady then
		return "PetCombatReadyReminder"
	elseif stage == TutorialConfig.Stages.LearnPetCombat or stage == TutorialConfig.Stages.PetInCombat then
		return "PetCombatReminder"
	elseif stage == TutorialConfig.Stages.Completed then
		return "Completed"
	end
	return "MovementReminder"
end

local byId = {
	TutorialAlex = {
		Speaker = "Alex",
		StartNode = "Welcome",
		ResolveStartNode = tutorialStartNode,
		Nodes = {
			MovementReminder = {
				Text = "Get comfortable moving around first. Come back when you're ready.",
			},
			SprintReminder = {
				Text = "Try picking up the pace first. You'll need to move quickly out there.",
			},
			Welcome = {
				Text = "Hey there! Welcome to Seabreeze Island.",
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
						Next = "StarterIntro",
					},
				},
			},
			StarterIntro = {
				Text = "You've proven you can handle yourself. Now choose a companion to fight by your side.",
				Choices = {
					{
						Id = "ChooseStarterPet",
						Text = "Choose a Pet",
						Action = TutorialConfig.BeginStarterPetChoiceAction,
						Close = true,
					},
				},
			},
			StarterChoiceActive = {
				Text = "Choose the companion you want to begin your journey with.",
			},
			EquipStarterPetReminder = {
				Text = "Your new companion is waiting in your Inventory. Equip your Pet when you're ready.",
			},
			PetCombatReadyReminder = {
				Text = "Great. Head back to the training area and let your Pet fight beside you.",
			},
			PetCombatReminder = {
				Text = "Your Pet attacks nearby Slimes automatically. Finish the training together.",
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
