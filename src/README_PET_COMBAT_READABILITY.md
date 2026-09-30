# Pawlands — Stage 2B.2.2 Pet Hit Readability

This patch adapts the proven Pawtopia Pet damage presentation to Pawlands without replacing Pawlands combat authority, target ownership, allocation, leash, or facing systems.

## Runtime behavior

- Replicated Pet Health decrease is treated as the canonical visible hit signal, matching Pawtopia's combat presentation model.
- The existing server-confirmed `PetCombatFeedback` event remains an immediate timing/direction fallback.
- A non-lethal Pet hit keeps the Pet's pre-impact yaw briefly, suppresses ambient bob/hop, and applies the existing short recoil instead of visually turning toward an incoming attacker.
- KO still freezes the Pet's last facing, applies the existing down tilt/push, waits the Pawlands six-second KO duration, then uses the existing recovery bounce.
- Pet health bars clone the complete Studio-authored `ReplicatedStorage > Assets > Misc > SlimeHealthbar` template. Runtime code does not construct GUI hierarchy.
- Pet health bars use the Pet icon from `PetCatalog`, show while the Pet is in combat/damaged/KO, tween the foreground fill, trail the authored `HealthShadow`, and shake briefly when Health decreases.

## Intentionally unchanged

- Pet and Slime damage values.
- Attack cadence and attack timing.
- 4v4 / 4v3 / 4v2 / 4v1 adaptive allocation.
- PrimaryOpponent / Player takeover rules.
- Slime target selection and Pet-first reclaim.
- Pet KO duration and server-authoritative vitals.
- Pet attack lunge, combat leash, and normal combat facing.

## Studio QA

1. Equip one Pet and enter combat without using Player M1.
2. When the Slime lands a confirmed hit, the Pet health bar must drop from `100 / 100` to `90 / 100` with a short shake and trailing shadow.
3. The Pet must recoil briefly without snapping to face a different incoming Slime.
4. Verify `SlimeToPet > HitSplat` still plays on each confirmed hit.
5. Let the Pet reach 0 HP. Confirm KO VFX/SFX, frozen last facing, down pose, and no attack impacts while KO.
6. After about six seconds, confirm full HP recovery, recovery bounce, and normal retarget/return behavior.
7. Repeat with 4 Pets + 4/3/2/1 Slimes and confirm allocation/aggro/facing remain unchanged.
8. Confirm no console errors or infinite yields.
