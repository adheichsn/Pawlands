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

## Explicitly not included

- No Coins, Diamonds, Slime Core, or item persistence yet.
- No Slime reward/contribution integration.
- No Party Power or Tab leaderboard.
- No Mastery, Ascension, Elite/Rare, Boss, Challenge, or AFK Training changes.
- No runtime GUI creation or GUI redesign.
