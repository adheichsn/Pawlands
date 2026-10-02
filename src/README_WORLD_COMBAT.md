# 4A.0 — Stonewood World Combat Foundation

## Scope

Stonewood now has a live, continuous Slime grinding runtime that is separate from the frozen tutorial encounter.

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

The current place still uses the equivalent legacy wrapper:

```text
StonewoodIsland > Combat > Zones > Zones > Region01/02/03
```

`WorldSlimeDirector` accepts either hierarchy so no additional Studio edit is required for this patch.

## Runtime contract

- Tutorial combat stays trigger-driven under `SlimeMovementService`.
- Stonewood combat runs under the separate `WorldSlimeService`.
- Both runtimes reuse the same Slime combat modules, models, health, targeting, navigation, attack runtime, Player M1, Pet combat, VFX, SFX, and healthbars.
- Both publish managed Slimes into the existing `Workspace/PawlandsSlimes` folder so existing Player/Pet combat validation continues to work.
- Stonewood Slimes use unique slots starting above the tutorial range.
- World Slimes are tagged with:
  - `WorldCombat = true`
  - `WorldRegionId = Region01/02/03`
  - `TutorialEncounter = false`
- The initial QA population is 8 total Slimes distributed across the three authored regions.
- A defeated Stonewood Slime uses the existing defeat presentation and respawns continuously after the existing lifecycle delay.
- Respawn chooses a safe inset position from the same authored region rather than a fixed death location.
- Stonewood aggro is finite and profile-driven instead of tutorial-wide aggro. Goopy keeps the `24` / `36` baseline while Fin, Sunset, and Derpy override it through 4A.0.1 world profiles.
- There are no Coins, Diamonds, Player EXP, Pet EXP, loot, boss, challenge, or chest rewards in this patch.

## Tutorial freeze

No TutorialService, tutorial stage, tutorial spawn flow, dialogue flow, cue, arrow, or tutorial completion presentation is changed by 4A.0.


## QA

1. Join and verify Stonewood creates 8 managed Slimes total.
2. Verify Slimes are distributed across Region01/02/03 rather than stacked at one Point.
3. Walk near a Stonewood Slime; it should use the existing notice/chase/engage/attack foundation with its Stonewood species profile applied.
4. Equip Pets; Pet targeting, Pet damage, Slime-to-Pet targeting, KO/recovery, and Player assist should behave like the existing combat baseline.
5. Kill a Stonewood Slime; after the normal defeat hold + respawn delay, it should reappear at a safe position in the same region.
6. Move away beyond disengage range; the Slime should return toward its home area instead of following across the island indefinitely.
7. Complete the existing Seabreeze tutorial in the same server and verify its scripted 1 → +2 encounter still behaves unchanged while Stonewood Slimes remain alive.
8. Verify Tutorial completion does not remove Stonewood Slimes.
9. Verify there are no normal rewards yet.
