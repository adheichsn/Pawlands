# 4A.0 — Stonewood World Combat Foundation

## Scope

Stonewood has a live, continuous Slime grinding runtime that is separate from the frozen tutorial encounter.

Studio authoring remains the source of placement truth:

```text
Workspace
└─ StonewoodIsland
   └─ Combat
      └─ Regions
         ├─ Region01
         │  └─ Points x8
         ├─ Region02
         │  └─ Points x8
         └─ Region03
            └─ Points x8
```

The runtime also accepts the equivalent legacy wrapper:

```text
StonewoodIsland > Combat > Zones > Zones > Region01/02/03
```

## Runtime contract

- Tutorial combat stays trigger-driven under `SlimeMovementService`.
- Stonewood combat runs under the separate `WorldSlimeService`.
- Both runtimes reuse the same Slime combat modules, models, health, targeting, navigation, attack runtime, Player M1, Pet combat, VFX, SFX, and healthbars.
- Both publish managed Slimes into the existing `Workspace/PawlandsSlimes` folder so existing Player/Pet combat validation continues to work.
- World Slimes are tagged with:
  - `WorldCombat = true`
  - `WorldRegionId = Region01/02/03`
  - `WorldPopulationIndex = 1..16`
  - `TutorialEncounter = false`
- Stonewood aggro and combat identity remain profile-driven through `WorldSlimeProfiles`.
- There are still no Coins, Diamonds, Player EXP, Pet EXP, loot, boss, challenge, or chest rewards in this stage.

## 4A.0.3 population scaling

Population uses only living Players whose HumanoidRootPart is inside one of the authored Stonewood combat regions. Seabreeze Players do not increase the target.

| Active Stonewood Players | Target Slimes |
| ---: | ---: |
| 0-1 | 8 |
| 2-3 | 10 |
| 4-6 | 12 |
| 7-10 | 14 |
| 11-16+ | 16 |

The target is capped by available authored region capacity. Population increases are filled gradually rather than bursting all missing Slimes in one frame. When the target decreases, living excess Slimes are not deleted in front of Players; their slots naturally stop respawning after they are defeated until population returns to target.

## Species composition

World population slots use deterministic smooth weighted distribution:

- Goopy: 45%
- Fin: 25%
- Sunset: 20%
- Derpy: 10%

The species is tied to the population slot, so a defeated slot respawns as the same species instead of rerolling every death.

At the current targets this produces approximately:

| Target | Goopy | Fin | Sunset | Derpy |
| ---: | ---: | ---: | ---: | ---: |
| 8 | 4 | 2 | 1 | 1 |
| 10 | 5 | 2 | 2 | 1 |
| 12 | 6 | 3 | 2 | 1 |
| 14 | 6 | 4 | 3 | 1 |
| 16 | 7 | 4 | 3 | 2 |

## Spawn and respawn safety

- Region allocation is stable and round-robin across Region01/02/03.
- Studio `Points` remain boundary/sampling authoring, not fixed exact spawn slots.
- New population searches grounded inset candidates before creating a model.
- A candidate must be at least 24 studs from a living Player.
- A candidate must be at least 8 studs from another live Slime.
- A candidate must be at least 18 studs from a Slime currently in Notice/Chase/Engage/Attack, preventing new population from appearing directly inside an active fight.
- Defeated world Slimes respawn after a randomized 4-7 second delay, after the existing defeat presentation.
- Respawns also avoid the previous death position by at least 6 studs.
- If no safe candidate exists, the slot waits and retries instead of forcing an unsafe spawn.

## Tutorial freeze

`TutorialService`, tutorial stages, tutorial 1 -> +2 spawn flow, dialogue, cue, arrow, completion presentation, and tutorial lifecycle configuration are unchanged by 4A.0.3.

## QA

1. With 1 Player in Stonewood, verify the target remains 8 Slimes.
2. Add enough Players inside Stonewood regions to cross 2-3 / 4-6 / 7-10 / 11-16 tiers and verify the target moves 10 / 12 / 14 / 16 gradually.
3. Keep Players in Seabreeze and verify they do not increase Stonewood population.
4. Verify population remains distributed across Region01/02/03 rather than stacking in one region.
5. Verify the 8-Slime baseline is approximately Goopy x4, Fin x2, Sunset x1, Derpy x1.
6. Kill world Slimes repeatedly and verify each slot preserves its species/profile on respawn.
7. Verify respawn delay varies between roughly 4 and 7 seconds after the defeat hold.
8. Fight near one authored sample area and verify a new/respawned Slime waits if there is no safe candidate away from Players and the active fight.
9. Reduce the active Stonewood player count after scaling up. Existing excess Slimes should not suddenly disappear; defeated excess slots should stop refilling until the target is met.
10. Complete the Seabreeze tutorial and verify its scripted encounter remains unchanged.
