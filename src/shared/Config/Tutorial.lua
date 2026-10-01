return table.freeze({
	StageAttributeName = "PawlandsTutorialStage",
	ProgressAttributeName = "PawlandsTutorialProgress",
	GoalAttributeName = "PawlandsTutorialGoal",
	CombatEligibleAttributeName = "PawlandsTutorialCombatEligible",
	InputModeAttributeName = "PawlandsTutorialInputMode",

	Stages = table.freeze({
		NotStarted = "NotStarted",
		LearnMove = "LearnMove",
		LearnSprint = "LearnSprint",
		MeetAlex = "MeetAlex",
		GoToZone = "GoToZone",
		InCombat = "InCombat",
		ReturnToAlex = "ReturnToAlex",
		SoloComplete = "SoloComplete",
		Completed = "Completed",
	}),

	AcceptCombatAction = "AcceptTutorialCombat",
	CompleteSoloCombatAction = "CompleteSoloTutorialCombat",
	-- Kept as a compatibility alias for the previous 3A.2 action name.
	CompleteCombatAction = "CompleteTutorialCombat",

	RemoteFolderName = "Remotes",
	InputModeRemoteName = "TutorialInputMode",
	InputModes = table.freeze({
		Keyboard = "Keyboard",
		Gamepad = "Gamepad",
		Touch = "Touch",
	}),

	ZoneCheckSeconds = 0.15,
	MoveLessonDistanceStuds = 7,
	SprintLessonMinSpeedStuds = 12.0,
	SprintLessonRequiredSeconds = 0.35,
	SoloCombatSlimeCount = 3,

	QuestGuiName = "QuestTracker",
	QuestTitle = "A New Adventure",
	MeetAlexPrefix = "Meet",
	MeetAlexItem = "Alex",
	GoToZonePrefix = "Go to",
	GoToZoneItem = "Training Area",
	CombatPrefix = "Defeat",
	CombatItem = "Training Slimes",
	ReturnPrefix = "Return to",
	ReturnItem = "Alex",

	NotificationKey = "TutorialGuidance",
	MoveHintKeyboard = "MOVE: Use WASD to move",
	MoveHintGamepad = "MOVE: Use the Left Stick to move",
	MoveHintTouch = "MOVE: Use the joystick to move",
	SprintHintKeyboard = "SPRINT: Press Ctrl to toggle Sprint",
	SprintHintGamepad = "SPRINT: Press L3 to toggle Sprint",
	CombatHintKeyboard = "ATTACK: Click to attack the Slimes",
})
