# Pawlands Tutorial Combat Flow — 3A.2

This stage connects the Studio-owned Alex dialogue, QuestTracker, authored CombatZone, and the existing Slime combat loop into the first tutorial mission.

## Flow

1. Talk to `Workspace > StarterStoneIsland > NPC > Alex`.
2. Choose `I'm ready.`.
3. The Studio-owned `StarterGui > QuestTracker` shows `Go to Training Area` after dialogue closes.
4. Enter `Workspace > StarterStoneIsland > Tutorial > Zones > CombatZone`.
5. The server spawns one four-Slime tutorial wave.
6. The tracker changes to `Defeat Training Slimes` and updates shared wave progress.
7. Tutorial Slimes do not respawn during this wave.
8. After the wave is cleared, the tracker changes to `Return to Alex`.
9. Talk to Alex and continue once to complete this tutorial combat step.

## Multiplayer behavior

The authored CombatZone hosts one cooperative tutorial wave at a time. Players who have accepted the mission can join the active wave by entering the zone. Every active tutorial participant sees the same wave progress. Players who have not accepted the mission are not valid targets for tutorial Slimes.

## Current scope

- The tutorial state is server-authoritative for the current server session.
- Persistence across leave/rejoin is intentionally not added yet; a future profile/save stage should hydrate the existing tutorial attributes before `TutorialService` starts.
- No Coins, Player EXP, Pet EXP, or general combat reward is granted yet.
- No runtime GUI hierarchy is created. `QuestTracker` is bound and updated in place.
- No world-space objective marker is created because no Studio-authored marker asset exists in the current RBXL. The QuestTracker is the current guidance layer.
