# Party Power Foundation

`4A.2 — Party Power Foundation & PlayerList Power`

## Purpose

Party Power is a descriptive, permanent-build strength summary for the exact Pets currently equipped by a player. It is never used as an input to combat damage.

The default Roblox Player List exposes the stat as `Power`; no custom GUI is created at runtime.

## Formula

For each equipped exact Pet UID:

```text
DerivedDamage = rounded authored BaseDamage after permanent Pet Level growth
DerivedMaxHP  = rounded authored BaseMaxHealth after permanent Pet Level growth
DPS           = DerivedDamage / AttackCadenceSeconds
PetPower      = round(DPS * 30 + DerivedMaxHP * 2)
PartyPower    = sum(PetPower for equipped Pets)
```

The formula intentionally reuses the same permanent level-growth configuration and the same rounded combat stats used by Pet combat/vitals.

## Included

- Authored Pet base damage and max health.
- Permanent Pet Level growth.
- Equipped exact Pet UIDs only.
- Current authored Pet attack cadence.

## Excluded

- Rarity as a direct score bonus.
- Handler Level.
- Current HP or KO state.
- Temporary food/potion/event buffs.
- Cosmetics, favorite state, or future Mastery cosmetics.

Future permanent systems such as Ascension can extend the derived permanent stats before Party Power is calculated.

## Runtime publication

The server publishes the current value in two places:

- `Player:GetAttribute("PawlandsPartyPower")`
- `Player > leaderstats > Power`

The `leaderstats.Power` IntValue is only a Roblox Player List bridge. Canonical Pet ownership/progression stays in the server-authoritative profile/inventory systems.

Party Power refreshes when the equipped party changes and when exact-Pet progression changes.
