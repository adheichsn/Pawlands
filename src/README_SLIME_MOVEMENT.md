# Pawlands — Stage 1.6A Slime Crowd Movement Foundation

This patch adds server-owned slime locomotion before combat damage is introduced.

## Studio assets used

- Arena: `Workspace > StarterStoneIsland > Tutorial > Zones > CombatZone`
- Spawn/wander anchors: the eight `Attachment` children named `Points` under `CombatZone`
- Slime models: `ReplicatedStorage > Assets > Slimes > StoneIsland`
  - `goopy`
  - `derpy`
  - `sunset`
  - `fin`

The patch clones four runtime slimes. Studio remains the owner of the map and slime models.

## Movement states

`Idle -> Wander -> Chase -> Idle/Wander`

There is no damage, health, defeat, reward, or combat hit logic in this patch.

- Idle: stays near its current position but still yields if another slime gets too close.
- Wander: selects a different unreserved CombatZone point and moves toward it.
- Chase: selects the nearest valid player inside CombatZone and approaches a stable ring slot around that player.
- Disengage: if the target leaves CombatZone or exceeds the disengage radius, the slime returns to non-combat movement.

## Anti-stacking / crowd behavior

Physical collision is disabled on runtime slime parts so slimes never shove or physics-jitter each other. Visual separation is handled independently by crowd steering:

1. Spawn uses farthest-point sampling from the Studio attachments instead of adjacent/random stacking.
2. Wander points are reserved so multiple slimes do not intentionally select the same destination.
3. Separation steering predicts short-term neighbor movement and pushes nearby slimes apart.
4. A stronger hard-separation force resolves accidental near-overlap.
5. Chase uses a ring of stable approach slots around the target rather than sending every slime to the player's exact position.

The same chase-ring slot is intended to become the future attack position, so attack logic can keep spacing instead of collapsing all slimes into one point.

## Animation

The provided Slime RNG reference contains a looping `SlimeIdle` animation with asset id `83416013845556`, and the Pawlands slime rigs already contain `AnimationController > Animator`. The runtime attempts to play that animation on each clone. If Roblox rejects the asset because of experience/creator permissions, the movement system keeps running and emits a warning; replace the id in `src/shared/Config/SlimeAnimations.lua` with an animation owned/permitted by Pawlands.

## Not included yet

- Damage / attack cooldowns / player HP
- Slime hit or death states
- Pathfinding around walls or large obstacles
- Combat GUI / health bars
- Rewards or respawn
- Pet combat

Obstacle navigation should be added separately if the CombatZone layout requires it; crowd separation solves slime-to-slime spacing, not pathfinding around geometry.

## Studio QA

1. On Play, four slimes should spawn in separated positions using four of the eight `Points` attachments.
2. Leave the player outside aggro range: slimes should alternate idle and wandering without overlapping.
3. Enter CombatZone and approach the group: slimes should chase but settle around the player rather than pile into the same position.
4. Walk/run in circles through the zone: slimes should avoid one another while following their assigned approach slots.
5. Leave CombatZone: slimes should disengage and resume idle/wander movement.
6. Verify pet follow still behaves exactly as before; this patch does not edit any pet module.
