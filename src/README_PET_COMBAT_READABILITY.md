# Pawlands — Stage 2B.4 Pet Strike Authority & Combat Readability

This baseline keeps Pawlands' Pet-primary combat identity while adapting two mature Pawtopia ideas: server-side strike commitment/contact validation and clean out-of-combat health recovery.

## Pet strike authority

The client still owns Pet visual presentation and reports only the authored impact beat. The server owns whether damage is accepted.

For each assigned Pet, `PetStrikeAuthority` advances a lightweight server virtual proxy toward the same shared combat goal. A reported impact is accepted only when:

- the Pet is still assigned to the same live Slime;
- the Pet is healthy and combat-eligible;
- the owner remains inside the hard leash;
- server cadence timing is valid;
- the server proxy has reached attack-ready range; and
- current proxy contact or the server-committed target-drift window is valid.

This is Pawtopia-inspired contact authority without moving Pawlands' rendered Pet models to the server.

## Healthbar lifecycle

- Slime healthbars show only during `Notice`, `Chase`, `Engage`, or `Attack` and hide again in non-combat states even if that Slime still has missing HP.
- Pet healthbars show during `Combat`, `Recovering`, and `KO`.
- A healthy damaged Pet leaving combat refills smoothly to MaxHealth on the server, then returns to `Idle` and hides its healthbar.
- Runtime continues to clone only the complete Studio-authored healthbar template.

## Movement polish

- Pet combat approach, retarget, and return transitions keep their existing speed caps but now also use acceleration caps. This removes the abrupt `0 -> max transition speed` jump after a recovery hold.
- Player Ctrl run toggle now eases `WalkSpeed` between walk/run over a short `0.16s` transition. Existing actual-velocity animation playback remains authoritative for foot speed.
- Slime movement/facing was already using a fixed simulation step, acceleration, and bounded turn rate, so it is intentionally unchanged in this patch.

## Intentionally unchanged

- Pet and Slime damage values.
- Pet attack cadence and lunge timing.
- 4v4 / 4v3 / 4v2 / 4v1 adaptive allocation.
- PrimaryOpponent / Player takeover rules.
- Combat leash distances.
- Pet KO duration.
- Slime strike trajectory and dodge validation.
- Authored Pet pivot / `YawOffset = -90` / Dragon planar facing.

## Studio QA

1. 1 Pet + 1 Slime: confirm every visible Pet impact that deals damage occurs only after the Pet has reached its combat slot.
2. Move rapidly into combat and confirm the first visual approach does not grant early remote damage from far away.
3. Finish combat with a damaged healthy Pet: bar remains visible during refill, reaches full HP, then hides.
4. Confirm an Idle/Wander Slime has no healthbar, including a damaged Slime after disengage.
5. Re-enter combat while a Pet is recovering: recovery stops at the current HP and combat resumes without a free full heal.
6. Repeat 4 Pets + 4/3/2/1 Slimes and confirm allocation, aggro, KO, and target handoff remain unchanged.
7. Toggle Ctrl while walking/running and confirm speed handoff feels smooth without animation foot racing.
8. Confirm Pet retarget/return starts and stops smoothly with no new teleport or WUUUSHH regression.
9. Confirm no console errors or infinite yields.
