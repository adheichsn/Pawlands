# Pawlands First-Time Onboarding, Solo Combat & Starter Pet — 3A.5.3

This stage extends the Studio-owned tutorial flow with contextual movement guidance, a longer Alex introduction, and a first combat lesson that intentionally happens before the Player receives a starter Pet.

## Studio-owned UI

No GUI hierarchy is created at runtime.

- `StarterGui > TextNotifications > Frame > TextTile` is treated as the authored generic text-notification template. Runtime clones the complete `TextTile` template for tutorial guidance.
- `StarterGui > QuestTracker` continues to own persistent tutorial objectives.
- `StarterGui > DialogueGui` continues to own Alex dialogue presentation.
- `StarterGui > StarterPetSelection` owns the Bunny / Cat / Dog starter choice. Runtime only binds the authored `DogCard`, `CatCard`, and `BunnyCard`; it does not create GUI hierarchy.

Authored notification preview tiles are hidden at runtime; only a cloned `TextTile` is used by this stage.

## Flow

1. First spawn begins at `LearnMove`.
2. `TextTile` teaches movement. The server advances after the character travels enough horizontal distance.
3. Keyboard Players learn `Ctrl` sprint; gamepad Players learn `L3` sprint. The server validates actual horizontal sprint speed before advancing.
4. Touch Players currently skip the sprint lesson after movement because Pawlands does not yet have a Studio-owned mobile Sprint button; this patch intentionally does not create one in code.
5. `QuestTracker` changes to `Meet Alex`.
6. Alex gives a longer Stone Island / Slime introduction and offers the first training mission.
7. `QuestTracker` changes to `Go to Training Area`.
8. Entering the authored CombatZone starts a three-Slime player-only training wave.
9. Studio automatic Pet preview is disabled so QA matches the live zero-Pet onboarding baseline. Pet dev commands remain available for explicit testing.
10. Clearing the wave changes the objective to `Return to Alex`.
11. Alex closes the solo lesson at `SoloComplete`, then introduces the first companion choice.
12. The tutorial advances to `ChooseStarterPet` and opens the Studio-owned starter selection after dialogue closes.
13. Bunny, Cat, and Dog are the only valid starter choices. The server grants exactly one starter Pet for the session and never auto-equips it.
14. The chosen card uses its authored outer `UIStroke` as the selection feedback; no selection overlay is created by code.
15. A successful grant advances to `EquipStarterPet`, shows `You got: <Pet>!`, and changes the QuestTracker objective to `Equip your first Pet`.
16. The exact starter UID must be equipped before the server advances to `PetCombatReady`; contextual Inventory cues teach that handoff without completing from a mere click.
17. `PetCombatReady` changes the QuestTracker back to `Go to Training Area`. Entering the CombatZone starts one Slime and shows `Pets attack nearby enemies automatically.`
18. The Pet lesson does not advance from acquisition, assignment, animation, or a client cue. `TutorialService` observes the authoritative Slime hit metadata and requires `LastHitSourceType = Pet`, the correct Player user ID, and `LastHitSourceUid = PawlandsStarterPetUid`.
19. The first confirmed starter-Pet hit expands the same tutorial encounter by two more Slimes and reveals the `0 / 3` clear progress. Clearing the encounter advances the tutorial to `Completed`.

## Scope boundaries

- Pet rarity/base stats are consumed from the existing 3B.1 catalog; this stage does not change those values.
- Starter ownership is session-only because persistent Inventory/Profile storage is not part of the current Pawlands foundation.
- No auto-equip, Coins, EXP, loot, or general combat rewards are added.
- The Pet combat lesson reuses the existing tutorial encounter and frozen Pet combat systems; it does not create a second combat/wave runtime.
- Existing Player combat damage, Slime combat tuning, Pet combat logic, KO, and reward systems are unchanged.
- Current Player basic attack input is still mouse-first. Studio-owned mobile/gamepad combat controls should be added in a later input stage before those platforms receive the same attack lesson.
## Starter Pet Inventory handoff

After starter grant, the player enters `EquipStarterPet`. The Pet Inventory runtime is server-backed and the exact starter UID must be equipped before tutorial progression advances to `PetCombatReady`. The existing contextual Inventory-button / exact Pet-tile cue presentation remains presentation-only; the server-confirmed party state owns completion.

## Guided Pet combat handoff

`PetCombatReady` is the travel stage for the second CombatZone lesson. The first Slime is deliberately spawned alone. A valid server-confirmed hit from the exact starter UID advances the Player to `PetInCombat`, expands the encounter to three Slimes, and enables kill progress. No Click/Tap attack cue is shown because this lesson teaches automatic Pet combat. If the first Slime is defeated before the required starter-Pet hit, the lesson resets instead of leaving the Player with no valid target.
## Starter tutorial recovery safety

3A.5.3 treats active combat stages as runtime checkpoints rather than durable wave ownership. If a character dies, leaves the CombatZone, or the tutorial encounter runtime becomes inconsistent, the Player returns to the matching travel stage and the encounter is rebuilt cleanly. A Player who already produced the required exact starter-Pet hit keeps that gate checkpoint, so a Pet-combat retry returns directly to the three-Slime clear instead of teaching the automatic-hit gate twice.

Tutorial Slimes are tagged internally by encounter generation inside `TutorialService`; stale hit/defeat signals from a cancelled wave cannot advance or increment a newer wave. Orphaned tutorial encounter runtime is cancelled before a fresh wave is allowed to start. Studio-authored Inventory, starter-selection, and cue presentation also release stale interaction locks and rebind if their `ScreenGui` instances are replaced. Starter Pet grants remain server-gated by the existing single-grant attribute plus the request-in-flight guard.

