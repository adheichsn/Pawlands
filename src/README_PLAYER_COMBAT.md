# Player Combat Foundation — Stage 2A.1

Stage 2A.1 adds server-authoritative M1 damage against runtime Pawlands slimes while preserving the existing player locomotion and slime crowd/navigation systems.

## Runtime behavior

- Left mouse button attacks the slime currently under the cursor.
- M1 cycles through four authored R6 combo animations and resets after a short pause.
- The server independently validates player state, slime ownership by the runtime slime folder, range, cooldown, line of sight, and slime health before applying damage.
- Runtime slimes expose `MaxHealth`, `Health`, `Defeated`, and `LastHitUserId` attributes for Studio QA.
- A slime that reaches zero health enters a non-moving `Defeated` state. Defeat presentation, despawn, and respawn are intentionally deferred to Stage 2A.2.

## Deferred

Critical attacks, running attacks, block/parry, hit reactions, slime attacks, pet attacks, rewards, health-bar UI, defeat VFX/SFX, and respawning are not enabled by this patch.
