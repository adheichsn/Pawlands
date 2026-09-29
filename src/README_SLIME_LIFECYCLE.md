# Pawlands — Stage 2A.2 Slime Defeat, Despawn & Respawn

This stage completes the first Tutorial slime lifecycle after server-authoritative health reaches zero.

## Runtime flow

`Alive -> Defeated -> Presentation Hold -> Despawned -> Respawned -> Idle`

- Health reaching `0` immediately marks the slime `Defeated` and removes it from targeting, attack turns, formation, crowd steering, and navigation.
- The defeated runtime clone remains visible for `0.50s` so the final hit is readable.
- The old runtime model is then destroyed completely; it is not kept invisible in Workspace.
- After a `5.00s` respawn delay, the same slime slot and species are recreated as a fresh clone.
- Fresh clones restart with full health and return to the normal Idle/Wander/Notice/Chase/Engage combat flow.

## Respawn placement

Respawns do not use the death position. The lifecycle evaluates the existing eight authored `CombatZone > Points` inset positions and prefers a candidate that is:

- at least `8` studs from a live Player inside CombatZone;
- at least `6` studs from another live slime;
- at least `4` studs from the defeated slime's death position.

If every authored candidate is occupied, respawn waits and retries instead of spawning on top of a Player or another slime.

## Not included

- Coins / EXP / item rewards;
- loot drops;
- defeat VFX/SFX;
- authored slime defeat animation;
- healthbar UI;
- Pet combat.

Those remain separate stages so the Tutorial lifecycle can be validated first.
