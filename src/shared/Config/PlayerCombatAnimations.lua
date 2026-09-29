local function asset(id)
	return "rbxassetid://" .. tostring(id)
end

-- Player combat animation ids are config-owned through Rojo, matching the
-- existing Pawlands player locomotion setup. M1 and the four light hit reactions
-- are active; heavier/downed/death reactions remain recorded for later stages.
return table.freeze({
	M1 = table.freeze({
		asset(140339096811792),
		asset(102005494639875),
		asset(73153009073720),
		asset(139153284469838),
	}),
	Critical = asset(127661678150014),
	RunningAttack = asset(111267696343286),
	Defense = table.freeze({
		Block = asset(107520695929641),
		Parry = asset(102954165251049),
		ParryLanded1 = asset(86871878587282),
		ParryLanded2 = asset(134317187298546),
	}),
	HitReact = table.freeze({
		Light = table.freeze({
			asset(116548055206847),
			asset(104433339910626),
			asset(114542854566053),
			asset(113094119830949),
		}),
		Middle = asset(138000361507127),
		GettingHitDowned = asset(74258197039998),
		Died = asset(70862108895485),
		Downed = asset(140411658400790),
		GettingUp = asset(89333160354969),
		Stunned = asset(140545505487737),

		-- Earlier authored reactions stay recorded for future heavy/knockback work.
		Legacy = table.freeze({
			Light = asset(109853540223703),
			Heavy = asset(130045849776111),
			KnockbackHeavy = asset(105715760605141),
		}),
	}),
})
