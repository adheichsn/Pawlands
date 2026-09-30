local States = table.freeze({
	Idle = "Idle",
	Combat = "Combat",
	KO = "KO",
})

return table.freeze({
	AttributeName = "PawlandsPetVitals",
	DefaultMaxHealth = 100,
	RecoverSeconds = 6,
	UpdateRate = 4,
	States = States,
})
