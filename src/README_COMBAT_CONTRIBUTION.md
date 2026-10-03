# Combat Contribution Foundation (4A.3)

Stonewood world combat now keeps an authoritative per-encounter damage ledger before rewards exist.

## What is tracked

- Player M1/running-attack damage is attributed to the owning Player.
- Pet damage is attributed to the owning Player and the exact Pet UID that landed the hit.
- Player damage and Pet damage are stored separately and combined into total contribution.
- Participating Pet UIDs remain in the finalized snapshot even if that Pet is KO later.
- Effective HP removed is recorded, so overkill damage cannot inflate contribution.
- Final snapshots are sorted by damage and expose share, hit counts, defeating source, and eligible users.

## Eligibility

Normal Stonewood Slimes currently require any positive meaningful authoritative damage (`>= 1`) and have no minimum share. These thresholds are config-driven and may be overridden per encounter later for Elite/Boss content.

Eligibility is contribution-based, never last-hit-only. The final hit is recorded only as metadata.

## Reward boundary

This patch does **not** grant Pet EXP, Handler EXP, Coins, Diamonds, Slime Core, Mastery, or loot.

Future reward code should subscribe to `CombatContributionService.SubscribeFinalized(...)`. Finalization happens once per Slime model, providing a single server-authoritative handoff point that avoids duplicate reward resolution.

## Tutorial safety

Contribution tracking is gated to models with `WorldCombat = true`. Seabreeze Tutorial Slimes are therefore not entered into the world reward ledger and Tutorial behavior is unchanged.
