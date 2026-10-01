# Pawlands First-Time Onboarding & Solo Combat — 3A.3

This stage extends the Studio-owned tutorial flow with contextual movement guidance, a longer Alex introduction, and a first combat lesson that intentionally happens before the Player receives a starter Pet.

## Studio-owned UI

No GUI hierarchy is created at runtime.

- `StarterGui > TextNotifications > Frame > TextTile` is treated as the authored generic text-notification template. Runtime clones the complete `TextTile` template for tutorial guidance.
- `StarterGui > QuestTracker` continues to own persistent tutorial objectives.
- `StarterGui > DialogueGui` continues to own Alex dialogue presentation.

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
11. Alex closes the solo lesson and the tutorial stops at `SoloComplete`, leaving starter-Pet grant / Pet combat training for the next stage.

## Scope boundaries

- No Pet rarity, Pet base stats, starter-Pet grant, persistence, Coins, EXP, loot, or general combat rewards are added.
- Existing Player combat damage, Slime combat tuning, Pet combat logic, KO, and reward systems are unchanged.
- Current Player basic attack input is still mouse-first. Studio-owned mobile/gamepad combat controls should be added in a later input stage before those platforms receive the same attack lesson.
