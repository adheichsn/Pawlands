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
- `DialogueFrame > ViewportFrame` remains Studio-owned and is not rebuilt by runtime.

NPCs remain Studio-owned. The first registered tutorial NPC is:

- `Workspace > StarterStoneIsland > NPC > Alex`
- `Alex > HumanoidRootPart > ProximityPrompt`

Future NPCs can set a Model attribute named `DialogueId` and register the matching definition in `shared/Dialogue/DialogueDefinitions.lua`. `Alex` currently has a name fallback to `TutorialAlex`, so no Studio attribute is required for this first QA pass.

## Runtime ownership

- Server validates prompt, NPC, player character, and interaction distance.
- Server owns active dialogue session and branching node.
- Client only presents the authored GUI, typewriter, buttons, and open/close motion.
- Walking out of interaction range closes the server session.
- Character replacement closes stale dialogue state.
- No tutorial mission state, quest tracking, Slime spawning, or rewards are added in 3A.1.
