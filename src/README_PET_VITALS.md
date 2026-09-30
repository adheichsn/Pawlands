# Pawlands — Pet Health / KO / Out-of-Combat Recovery

Pet vitals remain server-authoritative. Each owned Pet instance gets session state on demand:

- `Health`
- `MaxHealth`
- `CombatState`: `Idle`, `Combat`, `Recovering`, or `KO`
- `KO`
- `RecoverAt` using Roblox server time

The current baseline remains `100 MaxHealth` for every species and `6 seconds` KO recovery. These are tuning defaults, not final progression balance.

## Out-of-combat recovery

When a healthy damaged Pet loses its combat assignment, it enters `Recovering` instead of keeping stale missing HP forever. After a short `0.35s` handoff delay, the server refills that Pet from its current Health to MaxHealth over `3.0s`.

Recovery is cancelled immediately when the Pet receives a new combat assignment. Its current recovered Health is preserved; re-entering combat never grants a free full heal.

The Pet healthbar stays visible during `Combat`, `Recovering`, and `KO`. Once recovery reaches full Health the Pet returns to `Idle`, and the healthbar hides again.

KO recovery is intentionally separate: a KO Pet remains ineligible for combat for the existing six-second timer, then returns at full Health.

## Studio QA commands

- `!petvitals` or `!petvitals p1`
- `!pethurt p1 25`
- `!petko p1`
- `!petheal p1`

Expected normal recovery test: damage a healthy Pet, finish/leave combat, observe `Recovering`, smooth HP refill, then `Idle` at full Health with the bar hidden.

Expected KO test: `!petko p1` removes that equipped Pet from combat assignment; after about six seconds it returns at full Health and becomes eligible again.
