-- Player locomotion animation ids are intentionally config-owned through Rojo.
-- The current responsive Humanoid movement crossfades directly from run to idle;
-- no RunStop clip is loaded or played at runtime.
local function asset(id)
	return "rbxassetid://" .. tostring(id)
end

return table.freeze({
	Idle = table.freeze({
		Base = asset(78253591937674),
		Alt1 = asset(92253713888881),
		Alt2 = asset(107554884330710),
	}),
	Walk = table.freeze({
		Forward1 = asset(91328020830324),
		Forward2 = asset(136621257656296),
		Back = asset(76625972716020),
		Right = asset(90372138161272),
		Left = asset(87448838209695),
		FrontRight = asset(92236111203756),
		FrontLeft = asset(99741221934159),
		BackRight = asset(107809348663468),
		BackLeft = asset(118699550130591),
	}),
	Run = table.freeze({
		-- Run2 is the normal Pawtopia-style sprint presentation. Run1 stays reserved
		-- for a future faster movement tier instead of being randomly alternated.
		Fast = asset(116422451361262),
		Normal = asset(75530602135713),
	}),
	Air = table.freeze({
		Jump = asset(115499882416700),
		Falling = asset(139897607637600),
		LandingLight = asset(133154043474421),
		LandingMedium = asset(101484851480780),
		LandingHeavy = asset(100740595897766),
	}),
})
