# Pawlands — R6 Player Locomotion Foundation

This patch adds the first custom player movement/animation layer before combat work begins.

## Scope

- R6 player character.
- Default movement mode is Walk at `12` WalkSpeed.
- Left Ctrl or Right Ctrl toggles Run at `20` WalkSpeed; pressing Ctrl again returns to Walk.
- Run state resets to Walk after character respawn.
- Custom Idle, 8-direction Walk, Run, Run Stop, Jump, Falling, and Light/Medium/Heavy Landing animations.
- Landing animation weight is selected from observed downward velocity.
- Roblox's default character `Animate` LocalScript is disabled for the local character so it does not fight the Pawlands locomotion tracks.
- Existing pet ownership, party, and follow modules are not changed.

## Animation ownership decision

For player locomotion only, animation asset ids are config-owned through Rojo in `shared/Config/PlayerAnimations.lua`. Temporary `Animation` objects are created locally only to load tracks into the character Animator.

GUI, map, pet/NPC models, SFX, VFX, and other world assets remain Studio-owned.

## Direction behavior

Directional walk selection is resolved from `Humanoid.MoveDirection` relative to the character's current facing. This patch intentionally does not replace Roblox character rotation or camera behavior. If a later action-style camera-facing/strafe controller is desired, it can be added as a separate movement patch without rewriting the animation catalog.

## Studio QA

1. Join with an R6 character. Confirm custom IdleBase is visible and Roblox default idle/walk no longer blends underneath it.
2. Walk and verify WalkSpeed is 12.
3. Press Left Ctrl once, move, and verify RunSpeed is 20 plus Run animation. Press Left Ctrl again and verify Walk returns.
4. Repeat with Right Ctrl.
5. Reset Character and verify the movement mode starts at Walk again.
6. Walk forward/back/left/right/diagonals and inspect directional animation changes.
7. Jump, fall from several heights, and confirm Jump → Falling → landing transitions. Verify landing weight increases with fall speed.
8. While moving and toggling Walk/Run, verify all equipped pets still follow, keep their authored pivot/facing, and recover normally after teleport/respawn.

This patch does not add camera-facing strafing, stamina, combat, slime logic, mobile sprint UI, gamepad sprint bindings, or server movement anti-cheat.
