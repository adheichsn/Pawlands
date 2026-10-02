# 4A.0.2 — World Pet Combat AI & Natural Recall

## Scope

Stonewood Pets now treat the handler as the encounter anchor instead of following a world Slime indefinitely. The frozen Seabreeze tutorial continues to use the existing PetCombat/PetFollow baseline.

## World-only behavior

- New Stonewood targets are acquired within `28` studs of the owner.
- Existing Stonewood targets may remain sticky until `36` studs, creating leash hysteresis instead of rapid target flicker.
- A living world target that leaves the encounter starts a short server-authoritative regroup lock for that Pet slot.
- Returning Pets cannot acquire another target until that regroup lock expires; the server estimates the lock from separation and the handler's current horizontal speed.
- Ground Pets physically run back; flying Pets physically fly back and may cross a temporary ground gap while preserving hover height.
- Return speed scales with separation and can overtake a running handler.
- Normal world return no longer uses the generic `80`-stud visual snap. Emergency distance recall is pushed to `115` studs.
- If a ground return crosses an invalid gap, the Pet first holds its last valid grounded pose and retries. Only a sustained `2.0s` failure may use emergency recall.
- Owner teleport/character displacement still uses the existing explicit recall failsafe.

## Player assist bias

A confirmed Player hit on a Stonewood Slime marks that Slime as preferred for *new* Pet assignments for `1.75s`.

This is a bias, not a hard command:

- existing sticky Pet targets are preserved;
- adaptive attacker capacity still spreads Pets across multiple available Slimes;
- only otherwise comparable new assignments prefer the Player-hit target.

## Preserved systems

- Existing sticky-target behavior remains intact inside the world disengage leash.
- Existing adaptive `4v4 / 4v3 / 4v2 / 4v1` allocation remains intact.
- Pet damage, server strike authority, Pet HP/KO/recovery, Slime targeting, and combat presentation remain authoritative through the existing systems.
- No Pet stats, progression, rewards, Slime profiles, population scaling, or Tutorial stage behavior are changed by this patch.

## QA

1. Fight a Stonewood Slime, then walk/run away until the Slime leaves the Pet world leash. The Pet should stop combat and physically return instead of immediately snapping to the owner.
2. Keep running while the Pet returns. The Pet should visibly catch up rather than falling farther behind until generic recall triggers.
3. Pass another Stonewood Slime while the Pet is in its regroup window. It should continue returning instead of instantly turning back to fight.
4. Move extremely far/teleport the character. Emergency recall should still recover the Pet.
5. Force a return across a bad terrain edge/gap. The Pet should attempt physical recovery first; a sustained failure may recall after the stuck timeout.
6. With multiple Slimes active, verify sticky targets and adaptive allocation still distribute Pets as before.
7. Hit one Stonewood Slime with Player M1 while an unassigned Pet is choosing among comparable targets. The new assignment should prefer the recently Player-hit Slime without pulling already-sticky Pets off their targets.
8. Re-run Seabreeze Tutorial Pet combat and verify its assignment/leash/return behavior is unchanged from the frozen baseline.
