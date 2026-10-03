# 4A.4 — Currency & Combat Materials Foundation

This stage adds persistent, server-authoritative economy storage before Stonewood starts paying combat rewards.

## Canonical resources

- `Coins` — general gameplay currency.
- `Diamonds` — scarce premium-style gameplay currency; normal Stonewood Slimes do not award it yet.
- `SlimeCore` — the first combat progression material for future Ascension costs.

The persistent profile keeps currencies and materials separate:

```text
Economy
├─ Currencies
│  ├─ Coins
│  └─ Diamonds
└─ Materials
   └─ SlimeCore
```

Old schema-v1 profiles migrate to schema v2 with zero balances. No existing Pet, party, Handler, or Tutorial data is reset.

## Server authority

`EconomyService` is the only intended mutation layer for gameplay systems. It exposes trusted server APIs:

- `GetBalance(player, resourceId)`
- `GetSnapshot(player)`
- `Add(player, resourceId, amount, audit)`
- `Spend(player, resourceId, amount, audit)`
- `SetBalance(player, resourceId, amount, audit)`
- `GetLedgerSnapshot(player)`

Successful mutations require non-empty `Reason` and `Source` audit strings. Amounts are integer-only, negative balances are rejected, insufficient spends fail atomically, and overflow beyond the exact integer-safe range is rejected.

## Runtime audit ledger

Every successful balance change records a bounded server-memory ledger entry with:

- resource id;
- operation (`Add`, `Spend`, or `Set`);
- signed delta;
- before/after balance;
- reason;
- source;
- timestamp and per-session sequence.

Only canonical balances are persisted. The bounded transaction ledger is intentionally session-only so profile records do not grow without limit; it is a foundation for future analytics/economy telemetry.

## Client/UI binding

Balances are published as read-only server-authored Player attributes:

- `PawlandsCoins`
- `PawlandsDiamonds`
- `PawlandsSlimeCore`
- `PawlandsEconomyRevision`

No runtime GUI is created. Studio-authored HUD/UI can bind to these attributes later.

## Explicitly not included

- No Slime reward payout yet.
- No Pet EXP or Handler EXP payout changes.
- No Diamonds from normal Stonewood farming.
- No Ascension spending logic yet.
- No shop/hatch spending integration.
- No Mastery, Elite/Rare, Boss, Challenge, or AFK changes.
- No runtime GUI creation.

`4A.5 — Stonewood Combat Rewards` will connect finalized combat contribution snapshots to eligible Player/Pet progression and economy payouts.
