local visibleStates = {
	Combat = true,
	KO = true,
}

table.freeze(visibleStates)

return table.freeze({
	GuiName = "PetHealthbar",
	TemplateFolderName = "Misc",
	TemplateName = "SlimeHealthbar",
	RootPartName = "Body",
	ProgressName = "Progress",
	FillName = "Health",
	ShadowName = "HealthShadow",
	IconName = "Icon",
	TextName = "ProgressText",

	FillTweenSeconds = 0.10,
	ShadowTweenSeconds = 0.30,
	ShakeSeconds = 0.24,
	ShakeStuds = 0.12,
	VisibleStates = visibleStates,
})
