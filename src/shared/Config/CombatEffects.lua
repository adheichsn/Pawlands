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

	PetCombat = table.freeze({
		FolderName = "PetCombat",
		PetToSlime = table.freeze({
			FolderName = "PetToSlime",
			HitTemplateName = "HitSplat",
		}),
		SlimeToPet = table.freeze({
			FolderName = "SlimeToPet",
			HitTemplateName = "HitSplat",
		}),
		PetKO = table.freeze({
			FolderName = "PetKO",
			TemplateName = "KnockedOut",
		}),
	}),

	RootPartName = "RootPart",
	PlayerRootPartName = "HumanoidRootPart",
	PetRootPartName = "Body",
	DefaultEmitCount = 1,
	EffectCleanupSeconds = 4.0,
	SoundCleanupSeconds = 4.0,
})
