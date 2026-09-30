return table.freeze({
	-- Pawtopia-derived first-pass locomotion speeds. Ctrl remains a toggle so long
	-- open-world traversal does not require holding a modifier.
	WalkSpeed = 10,
	RunSpeed = 16,
	RunToggleKeys = table.freeze({ Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl }),
	SpeedTransitionSeconds = 0.16,

	MoveDeadzone = 0.05,
	IdleSpeed = 0.75,

	-- Ground movement crossfades are intentionally softer than the previous pass.
	AnimationFade = 0.14,
	SprintStopFade = 0.20,
	OneShotFade = 0.08,

	-- Runtime playback follows actual horizontal speed so feet do not race or drag.
	WalkReferenceSpeed = 10,
	RunReferenceSpeed = 16,
	MinimumPlaybackSpeed = 0.75,
	MaximumPlaybackSpeed = 1.35,

	-- Free third-person movement always presents the authored forward walk because
	-- Humanoid AutoRotate already turns the character toward travel. 8-way clips
	-- are reserved for Shift Lock / facing-locked movement.
	DirectionHysteresisDegrees = 10,

	IdleVariantMinSeconds = 7,
	IdleVariantMaxSeconds = 13,

	-- Peak downward speed while airborne selects the authored landing weight.
	MinLandingSpeed = 12,
	MediumLandingSpeed = 55,
	HeavyLandingSpeed = 85,
	MinimumLandingPresentationLock = 0.08,
})
