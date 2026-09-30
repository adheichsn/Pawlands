return table.freeze({
	BodyMotorName = "SlimeBodyMotor6D",
	RootPartName = "RootPart",
	HealthbarGuiName = "SlimeHealthbar",

	-- Normal hits are presentation-only. The body motor receives a very small
	-- additive recoil/dip while the authoritative slime root and AI keep moving.
	Hit = table.freeze({
		LightDurationSeconds = 0.12,
		FinisherDurationSeconds = 0.15,
		LightRecoilStuds = 0.28,
		FinisherRecoilStuds = 0.45,
		LightDipStuds = 0.08,
		FinisherDipStuds = 0.12,
	}),

	-- Stage 2A.2 already keeps defeated models around for 0.50s. This sequence
	-- intentionally finishes before that server-owned despawn window expires.
	Defeat = table.freeze({
		PauseSeconds = 0.06,
		SquashEndSeconds = 0.14,
		PopEndSeconds = 0.28,
		EndSeconds = 0.44,
		SquashScale = 0.90,
		PopScale = 1.04,
		EndScale = 0.10,
		HopHeightStuds = 0.55,
		HideHealthbarAtSeconds = 0.14,
	}),

	FeedbackTiers = table.freeze({
		Light = "Light",
		Finisher = "Finisher",
	}),
})
