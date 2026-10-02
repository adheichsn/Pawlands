# Pawlands Dialogue Foundation — 3A.1

This stage binds the Studio-owned `StarterGui > DialogueGui` and authored NPC `ProximityPrompt` to a centralized Rojo dialogue runtime.

## Studio contract

Required GUI anchors:

- `StarterGui > DialogueGui`
- `DialogueGui > DialogueFrame`
- `DialogueFrame > Username`
- `DialogueFrame > DialogueText`
- `DialogueFrame > Option1`
- `DialogueFrame > Option2`

Optional authored anchors used when present:

- `DialogueFrame > TypeSound`
- `DialogueGui > WarningText`

`ViewportFrame` is intentionally not part of the Pawlands dialogue contract. The dialogue runtime does not create, clone, or bind a 3D NPC portrait.

NPCs remain Studio-owned. The first registered tutorial NPC is:

- `Workspace > SeabreezeIsland > NPC > Alex`
- `Alex > HumanoidRootPart > ProximityPrompt`

Future NPCs can set a Model attribute named `DialogueId` and register the matching definition in `shared/Dialogue/DialogueDefinitions.lua`. `Alex` currently has a name fallback to `TutorialAlex`, so no Studio attribute is required for this first QA pass.

## Runtime ownership

- Server validates prompt, NPC, player character, and interaction distance.
- Server owns active dialogue session and branching node.
- Client only presents the authored GUI, typewriter, buttons, and open/close motion.
- Walking out of interaction range closes the server session as a teleport/streaming fail-safe.
- Character replacement closes stale dialogue state.
- While dialogue is active, movement/run/jump and Player M1 are interaction-locked.
- The active prompt is hidden locally until the closing presentation finishes.
- The Player smoothly faces the NPC and local idle Pets settle into a wider side formation.
- Server combat also rejects Player attacks while the dialogue session attribute is active.
- No tutorial mission state, quest tracking, Slime spawning, or rewards are added in 3A.1.1.
