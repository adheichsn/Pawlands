# Pawlands — Stage 2A.2.1 Slime Healthbar Presentation

This stage binds the existing server-authoritative slime `Health` / `MaxHealth` attributes to a Studio-authored BillboardGui. Runtime code does not construct or clone GUI instances.

## Studio-owned GUI

Canonical authored asset:

`ReplicatedStorage > Assets > Misc > SlimeHealthbar`

The current Studio asset hierarchy is:

- `SlimeHealthbar` (`BillboardGui`)
  - `Progress` (`Frame`)
    - `Health` (`Frame`) — runtime width only
    - `HealthShadow` (`Frame`) — untouched
    - `Icon` (`ImageLabel`) — untouched
    - `ProgressText` (`TextLabel`) — runtime text only

Before Play, copy the authored `SlimeHealthbar` in Studio into each slime template's `RootPart`:

- `ReplicatedStorage > Assets > Slimes > StoneIsland > goopy > RootPart > SlimeHealthbar`
- `ReplicatedStorage > Assets > Slimes > StoneIsland > derpy > RootPart > SlimeHealthbar`
- `ReplicatedStorage > Assets > Slimes > StoneIsland > sunset > RootPart > SlimeHealthbar`
- `ReplicatedStorage > Assets > Slimes > StoneIsland > fin > RootPart > SlimeHealthbar`

Keep `ReplicatedStorage > Assets > Misc > SlimeHealthbar` as the canonical design/template. The four copies are Studio-authored content; `SlimeFactory` already clones each whole slime model for gameplay, so the authored BillboardGui naturally travels with that model clone.

## Runtime presentation

The client controller only binds and updates the authored BillboardGui already present inside each runtime slime:

- `Health / MaxHealth` updates `Progress > Health.Size` with a short smooth tween.
- `ProgressText` displays `current / max` health.
- A full-health idle/wandering slime keeps the healthbar hidden.
- Notice / Chase / Engage / Attack makes the healthbar visible even at full health.
- Once damaged, the healthbar remains visible until defeat.
- At `0 HP`, the bar reaches zero during the existing Stage 2A.2 defeat hold; destroying the slime model removes the authored healthbar with it.
- A respawned slime receives a fresh authored healthbar because the fresh slime clone comes from the Studio model template.

## GUI ownership rule

`SlimeHealthbarController` does **not** call `Instance.new()` for GUI, does **not** call `SlimeHealthbar:Clone()`, and does not build layout/style in code. Studio owns the BillboardGui, frames, icon, text style, gradients, strokes, corners, size, offset, and visual design.
