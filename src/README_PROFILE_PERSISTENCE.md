# 4A.1.1 — Player Profile & Persistence Foundation

This stage adds the first canonical Pawlands player profile and safe DataStore lifecycle before combat rewards become live.

## Persisted v1 profile

- Handler cumulative EXP and reconciled Handler Level.
- Every owned Pet as an exact unique UID (`p1`, `p2`, ...), including duplicate species as separate records.
- Per-Pet `PetId`, `SpeciesId`, variant, favorite state, cumulative EXP, and reconciled Pet Level.
- Monotonic `NextSequence`, so future hatch/grant acquisition cannot reuse an existing historical UID.
- Active party as exact Pet UIDs. Duplicate species remain valid in inventory but invalid in the equipped party.
- Tutorial stage, starter-granted flag, exact starter Pet UID/species, and the starter-Pet-hit checkpoint.

Derived/runtime values such as Party Power, EXP-into-level, current HP, combat assignments, temporary buffs, and world Slime state are intentionally not stored.

## Lifecycle and safety

- `PlayerProfileService` loads before inventory/progression/tutorial services.
- Dependent player initialization waits for profile readiness instead of assuming `PlayerAdded` callback ordering.
- Live servers use `DataStoreService` with `UpdateAsync`, schema versioning, retry/backoff, and a server-session lock with a short handoff retry window.
- If a live profile cannot be loaded safely, Pawlands does not create a writable default session over the unknown data; the player is asked to rejoin.
- Loaded profiles autosave every 60 seconds (also refreshing the session-lock heartbeat) and release-save on `PlayerRemoving` / server shutdown.
- Profile writes are server-authoritative. Clients never submit profile blobs.
- Schema v1 includes a migration bridge for pre-versioned internal/test records and normalizes malformed/stale fields before runtime use.

## Studio behavior

`Shared.Config.Profile.UseDataStoreInStudio` defaults to `false`. Studio therefore uses an isolated in-memory profile by default, which avoids API-service errors during normal local QA but does not persist across Studio restarts.

For explicit persistence QA, enable Studio API Services and opt in through that config. Live servers always use the configured DataStore.

## Exact Pet UID example

Two Dragons are two independent Pet records:

```text
p17 = Dragon, Lv32, Favorite=true
p18 = Dragon, Lv1,  Favorite=false
```

Both survive save/load independently. They may coexist in inventory, but the existing one-species-per-party validation still prevents equipping both Dragons at once.


## Studio development commands

`4A.1.1.1 — Dev Profile Reset & Inspect Commands` adds Studio-only profile QA commands behind `server/Config/Development.lua > EnableProfileCommands`. They never create runtime GUI and they only act on the Player issuing the command.

- `!profileinspect` prints Handler progression, Pet UID records, active party, `NextSequence`, and Tutorial/starter state from the current canonical server profile. Pet output is capped at 50 records to avoid runaway console spam.
- `!profilereset` is intentionally non-destructive by itself and prints the confirmation syntax.
- `!profilereset CONFIRM` atomically resets the issuing Player to the current default schema, releases the profile session lock, and kicks the Player so every dependent service reloads from a fresh profile on rejoin.
- In default Studio memory mode the reset only clears the in-memory QA record. With Studio DataStore access explicitly enabled through `UseDataStoreInStudio = true`, the same command resets the persistent QA record owned by the current server session.
- A reset refuses to overwrite a profile whose session lock belongs to another server.

## Explicitly not included

- No Coins, Diamonds, Slime Core, or item persistence yet.
- No Slime reward/contribution integration.
- No Party Power or Tab leaderboard.
- No Mastery, Ascension, Elite/Rare, Boss, Challenge, or AFK Training changes.
- No runtime GUI creation or GUI redesign.
