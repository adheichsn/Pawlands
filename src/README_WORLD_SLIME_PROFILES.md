# 4A.0.1 — World Slime Profiles & Combat Personality

## Scope

Stonewood Slimes now keep the shared combat foundation while receiving world-only species profiles. The Seabreeze tutorial continues using the frozen `SlimeCombat` and `SlimeMovement` baselines.

Initial QA profiles:

| Slime | Role | HP | Damage | Aggro / Disengage | Identity |
| --- | --- | ---: | ---: | ---: | --- |
| Goopy | Balanced | 350 | 10 | 24 / 36 | Stonewood baseline |
| Fin | Swift | 280 | 8 | 26 / 42 | Faster chase, faster readable strikes |
| Sunset | Aggressive | 425 | 13 | 32 / 44 | Earlier notice plus low-health Frenzy |
| Derpy | Heavy | 600 | 18 | 20 / 30 | Slower pursuit, longer wind-up, heavier hit |

These are QA tuning values, not final progression balance.

## Runtime contract

- World profiles are resolved from the existing `SlimeId`; Studio model names and asset paths are unchanged.
- `WorldSlimeProfileRuntime` overlays movement/combat values only for Stonewood agents.
- `SlimeFactory`, `SlimeHealth`, Player M1, Pet damage, targeting, scheduler, navigation, lifecycle, VFX/SFX, and healthbar foundations remain shared.
- World profile health is published through the existing `MaxHealth` / `Health` attributes.
- Useful Studio metadata is published on each Stonewood model: `CombatRole`, `AttackDamage`, `AttackIntervalSeconds`, `AggroRange`, `DisengageRange`, `ChaseSpeed`, `PassiveId`, and `PassiveActive`.
- Respawned Stonewood Slimes re-apply their species profile before returning to the active world-agent list.

## Sunset Frenzy

Sunset activates `Frenzy` at or below 35% health while still alive. Frenzy increases chase speed by 15% and shortens its attack interval / pressure cooldown by 15%. Damage does not increase, keeping the low-health pressure readable instead of producing a hidden damage spike.

## Tutorial freeze

No TutorialService, tutorial state, tutorial spawn flow, tutorial movement config, tutorial combat config, dialogue, cue, arrow, or completion presentation is changed by 4A.0.1.

## QA

1. Verify Stonewood spawns still use the existing 8-Slime 4A.0 population and all four species appear.
2. Inspect runtime attributes: Goopy `350`, Fin `280`, Sunset `425`, Derpy `600` MaxHealth.
3. Confirm hit damage is Goopy `10`, Fin `8`, Sunset `13`, Derpy `18` against valid Player/Pet targets.
4. Compare movement: Fin should be clearly faster, Sunset should notice from farther away, and Derpy should feel slower/territorial.
5. Damage Sunset below 35% without defeating it; `PassiveActive` should become true and its chase/attack pacing should increase without increasing damage.
6. Defeat and respawn each species; profile HP, role, damage, and passive metadata should be restored correctly.
7. Run the Seabreeze tutorial and confirm its Slimes remain on the frozen 100-HP tutorial baseline.
8. Verify no Coins, EXP, loot, population scaling, Pet recall changes, elite behavior, or boss behavior were introduced here.
