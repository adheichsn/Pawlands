# Pawlands — Stage 2B.1C Pet Health & KO Foundation

This stage adds server-authoritative pet vitals without changing pet combat damage, slime targeting, or GUI presentation.

## Runtime state

Each owned pet instance gets session vitals on demand:

- `Health`
- `MaxHealth`
- `CombatState`: `Idle`, `Combat`, or `KO`
- `KO`
- `RecoverAt` using Roblox server time

The current foundation baseline is `100 MaxHealth` for every species and `6 seconds` KO recovery. These are tuning defaults, not final progression balance.

Equipped-party vitals are replicated atomically through the Player attribute `PawlandsPetVitals`. No pet healthbar is rendered in this stage. The supplied per-species icon IDs are cataloged in `PetCatalog` for the later Studio-authored healthbar binding stage.

## KO behavior

At zero Health the pet enters `KO`, becomes ineligible for pet combat assignment, and receives a recovery deadline. After the recovery timer expires it returns at full Health in `Idle`, making it eligible for combat assignment again.

Stage 2B.1C does not make slimes attack pets yet. Studio-only commands are included so KO/recovery can be tested before Stage 2B.1D connects slime attacks to this service.

## Studio QA commands

- `!petvitals` or `!petvitals p1`
- `!pethurt p1 25`
- `!petko p1`
- `!petheal p1`

Expected KO test: `!petko p1` should remove that equipped pet from combat assignment on the next allocator update; after about 6 seconds it should recover to full Health and become eligible again.
