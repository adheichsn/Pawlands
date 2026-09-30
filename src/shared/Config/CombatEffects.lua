return table.freeze({
	AssetsRootName = "Assets",
	CombatFolderName = "Combat",

	PlayerToSlime = table.freeze({
		FolderName = "PlayerToSlime",
		SwingFolderName = "SwingSFX",
		HitSoundFolderName = "HitSFX",
		HitEffectName = "HitEffect",
		SwingPrefix = "Swing",
		HitPrefix = "Hit",
	}),

	SlimeToPlayer = table.freeze({
		FolderName = "SlimeToPlayer",
		HitTemplateName = "Hit",
	}),

	SlimeDefeat = table.freeze({
		FolderName = "KnockedOut",
		TemplateName = "KnockedOut",
	}),

	RootPartName = "RootPart",
	PlayerRootPartName = "HumanoidRootPart",
	DefaultEmitCount = 1,
	EffectCleanupSeconds = 4.0,
	SoundCleanupSeconds = 4.0,
})
