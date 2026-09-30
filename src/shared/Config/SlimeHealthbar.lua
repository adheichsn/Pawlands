local visibleStates = {
	Notice = true,
	Chase = true,
	Engage = true,
	Attack = true,
}

table.freeze(visibleStates)

return table.freeze({
	GuiName = "SlimeHealthbar",
	RootPartName = "RootPart",
	ProgressName = "Progress",
	FillName = "Health",
	TextName = "ProgressText",

	TemplateFolderName = "Misc",
	TweenSeconds = 0.14,
	ReplicationGraceSeconds = 3.0,
	VisibleStates = visibleStates,
})
