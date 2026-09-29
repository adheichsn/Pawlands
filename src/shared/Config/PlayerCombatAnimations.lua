local function asset(id)
	return "rbxassetid://" .. tostring(id)
end

-- Player combat animation ids are config-owned through Rojo, matching the
-- existing Pawlands player locomotion setup. Stage 2A.1 only plays the M1
-- combo tracks; the remaining authored ids are recorded now for later combat
-- stages without enabling their mechanics early.
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
		Light = asset(109853540223703),
		Heavy = asset(130045849776111),
		KnockbackHeavy = asset(105715760605141),
	}),
})
