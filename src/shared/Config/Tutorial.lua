return table.freeze({
	StageAttributeName = "PawlandsTutorialStage",
	ProgressAttributeName = "PawlandsTutorialProgress",
	GoalAttributeName = "PawlandsTutorialGoal",
	CombatEligibleAttributeName = "PawlandsTutorialCombatEligible",

	Stages = table.freeze({
		NotStarted = "NotStarted",
		GoToZone = "GoToZone",
		InCombat = "InCombat",
		ReturnToAlex = "ReturnToAlex",
		Completed = "Completed",
	}),

	AcceptCombatAction = "AcceptTutorialCombat",
	CompleteCombatAction = "CompleteTutorialCombat",
	ZoneCheckSeconds = 0.15,

	QuestGuiName = "QuestTracker",
	QuestTitle = "A New Adventure",
	GoToZonePrefix = "Go to",
	GoToZoneItem = "Training Area",
	CombatPrefix = "Defeat",
	CombatItem = "Training Slimes",
	ReturnPrefix = "Return to",
	ReturnItem = "Alex",
})
