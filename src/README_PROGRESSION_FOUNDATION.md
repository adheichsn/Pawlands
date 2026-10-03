# 4A.1 — Progression Foundation

This stage adds the server-authoritative data/math foundation for Pet Level and Handler Level without adding combat rewards, currency, UI, Mastery, Ascension, AFK Training, or leaderboard behavior. Persistence is supplied by the follow-up `4A.1.1` profile foundation.

## Pet progression

- Every owned Pet starts at `Lv1` with `0` cumulative Pet EXP.
- V1 Pet level cap is `Lv50` for every rarity.
- All rarities share the same EXP curve; rarity/species continues to define authored base potential through `PetCatalog`.
- EXP is stored as cumulative total experience. `Level`, EXP-into-level, and EXP-to-next are derived deterministically from the shared curve.
- Required EXP from level `L` to `L+1` is `round(50 + 10*(L-1) + 1.5*(L-1)^2)`.
- Total Pet EXP from `Lv1` to `Lv50` is `71,258`.
- Cumulative checkpoints: Lv10 `1,118`, Lv20 `5,828`, Lv30 `17,088`, Lv40 `37,898`, Lv50 `71,258`.
- Intended active-combat pacing remains the design target of roughly 7–10 hours from Lv1 to Lv50 once reward tables are implemented. This patch does not grant EXP itself.

Pet growth data is additive against the authored base stat:

- Damage multiplier: `1 + 0.032 * (Level - 1)`.
- Max HP multiplier: `1 + 0.024 * (Level - 1)`.
- Lv1 therefore preserves the current Pet combat baseline exactly.
- The shared math and trusted server APIs are available now; applying level growth to live combat/presentation remains part of the later Pet Level runtime stage.

## Handler progression

- Handler starts at `Lv1` with `0` cumulative Handler EXP.
- V1 Handler cap is `Lv50`.
- Required EXP from level `L` to `L+1` is `round(150 + 30*(L-1) + 5*(L-1)^2)`.
- Total Handler EXP from `Lv1` to `Lv50` is `232,750`.
- Cumulative checkpoints: Lv10 `3,450`, Lv20 `18,525`, Lv30 `55,100`, Lv40 `123,175`, Lv50 `232,750`.
- Intended pacing remains roughly 25–40 hours of meaningful active play once reward sources exist. AFK Training is not a Handler EXP source.

Handler growth data is intentionally light:

- Player damage multiplier data: `1 + 0.005 * (Level - 1)`.
- Player max HP multiplier data: `1 + 0.0075 * (Level - 1)`.
- This patch does not yet apply those multipliers to Player combat/health; that belongs to the Handler runtime stage.

Handler progression is published through Player attributes:

- `PawlandsHandlerLevel`
- `PawlandsHandlerExperience`
- `PawlandsHandlerExperienceIntoLevel`
- `PawlandsHandlerExperienceToNextLevel`

## Server APIs

`PetProgressionService` provides trusted `GetSnapshot`, `SetExperience`, `AddExperience`, and growth-multiplier accessors per exact Pet UID.

`HandlerProgressionService` provides trusted `GetSnapshot`, `SetExperience`, `AddExperience`, and growth-multiplier accessors per Player.

The follow-up `4A.1.1 — Player Profile & Persistence Foundation` now persists cumulative Pet/Handler EXP and reconciled levels. The progression math/API contract in this document remains unchanged.

## Explicitly not included

- No Coins or Diamonds.
- No Slime rewards or contribution resolver.
- No Pet EXP/Handler EXP reward source yet.
- No live level-up presentation.
- No Inventory redesign or runtime GUI creation.
- No Party Power or Tab leaderboard.
- No Mastery, Ascension, AFK Training, Elite, Rare Slime, Boss, or Challenge changes.
- No Tutorial behavior changes.
