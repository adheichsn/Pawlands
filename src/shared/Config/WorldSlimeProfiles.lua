-- Stonewood-only combat identities. Tutorial Slimes continue using the frozen
-- SlimeCombat / SlimeMovement baselines without these profile overrides.
local profiles = {
	goopy = {
		Role = "Balanced",
		MaxHealth = 350,
		Movement = {
			AggroRange = 24,
			DisengageRange = 36,
			WanderSpeed = 2.8,
			ChaseSpeed = 9.8,
			ChaseCatchupMaxSpeed = 11.5,
			ReturnSpeed = 8.8,
		},
		Combat = {
			AttackDamage = 10,
			NoticeSeconds = 0.26,
			AttackIntervalSeconds = 1.55,
			PlayerPressureCooldownSeconds = 1.55,
			PetPressureCooldownSeconds = 1.55,
		},
	},

	fin = {
		Role = "Swift",
		MaxHealth = 280,
		Movement = {
			AggroRange = 26,
			DisengageRange = 42,
			WanderSpeed = 3.2,
			ChaseSpeed = 12.5,
			ChaseCatchupMaxSpeed = 14.5,
			ChaseCatchupStartDistance = 9,
			ChaseCatchupFullDistance = 22,
			ReturnSpeed = 11.0,
		},
		Combat = {
			AttackDamage = 8,
			NoticeSeconds = 0.20,
			AttackIntervalSeconds = 1.15,
			PlayerPressureCooldownSeconds = 1.15,
			PetPressureCooldownSeconds = 1.15,
			AttackWindupSeconds = 0.62,
			AttackImpactSeconds = 0.16,
			AttackStrikeSeconds = 0.31,
		},
	},

	sunset = {
		Role = "Aggressive",
		MaxHealth = 425,
		Movement = {
			AggroRange = 32,
			DisengageRange = 44,
			WanderSpeed = 3.0,
			ChaseSpeed = 10.8,
			ChaseCatchupMaxSpeed = 12.8,
			ReturnSpeed = 9.4,
		},
		Combat = {
			AttackDamage = 13,
			NoticeSeconds = 0.16,
			AttackIntervalSeconds = 1.35,
			PlayerPressureCooldownSeconds = 1.35,
			PetPressureCooldownSeconds = 1.35,
			AttackWindupSeconds = 0.68,
		},
		Passive = {
			Id = "Frenzy",
			HealthRatio = 0.35,
			ChaseSpeedMultiplier = 1.15,
			AttackIntervalMultiplier = 0.85,
		},
	},

	derpy = {
		Role = "Heavy",
		MaxHealth = 600,
		Movement = {
			AggroRange = 20,
			DisengageRange = 30,
			WanderSpeed = 2.2,
			ChaseSpeed = 7.4,
			ChaseCatchupMaxSpeed = 8.8,
			ReturnSpeed = 7.8,
			Acceleration = 9.0,
		},
		Combat = {
			AttackDamage = 18,
			NoticeSeconds = 0.35,
			AttackIntervalSeconds = 2.10,
			PlayerPressureCooldownSeconds = 2.10,
			PetPressureCooldownSeconds = 2.10,
			AttackWindupSeconds = 1.00,
			AttackImpactSeconds = 0.24,
			AttackStrikeSeconds = 0.44,
			AttackLungeDistance = 3.40,
			AttackHopHeight = 0.75,
		},
	},
}

for _, profile in pairs(profiles) do
	profile.Movement = table.freeze(profile.Movement)
	profile.Combat = table.freeze(profile.Combat)
	if profile.Passive then
		profile.Passive = table.freeze(profile.Passive)
	end
	table.freeze(profile)
end

return table.freeze(profiles)
