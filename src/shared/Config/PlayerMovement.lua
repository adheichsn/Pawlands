return table.freeze({
	-- Initial feel pass. These values are intentionally easy to tune after Studio QA.
	WalkSpeed = 12,
	RunSpeed = 20,
	RunToggleKeys = table.freeze({ Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl }),

	MoveDeadzone = 0.08,
	AnimationFade = 0.12,
	OneShotFade = 0.08,

	-- IdleBase remains the default; alternate idles are occasional one-shots.
	IdleVariantMinSeconds = 8,
	IdleVariantMaxSeconds = 14,

	-- Maximum downward velocity observed during the airborne phase selects landing weight.
	MinLandingSpeed = 14,
	MediumLandingSpeed = 38,
	HeavyLandingSpeed = 62,
})
