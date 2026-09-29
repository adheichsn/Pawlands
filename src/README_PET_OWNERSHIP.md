# Pawlands — Session Pet Ownership & Party Patch

This patch extends the existing pet-follow foundation without changing its client movement, authored-pivot correction, yaw calibration, 2×2 formation, or 1.5×1.5 ground Blockcast.

## Scope

- Session-only pet inventory with one unique `Uid` per pet instance (`p1`, `p2`, ...).
- Duplicate species are allowed in inventory so future hatch/variant systems can own multiple copies.
- Equipped party remains capped at **4**.
- Equipped party allows only **one pet per `SpeciesId`**.
- Equip/unequip and full party changes validate ownership on the server.
- Client follow still receives the existing visual pet ids, so follow code does not need to change.
- No GUI, remotes, persistence, hatch, combat, tutorial, or starter-pet acquisition is added here.

## Studio commands

The existing `!pets` commands remain available as Studio convenience commands. When a requested preview species is not owned yet, the Studio helper grants a temporary session copy first and then uses the normal ownership-validated `SetParty` path.

```text
!pets Bunny Cat Dog Dragon
!pets Cow Rat Turtle
!pets Dragon Dragon
!pets Drago Dragon
!pets Bunny Cat Dog Dragon Cow
!pets clear
!pets list

!petgrant Bunny
!petinventory
!petequip p1
!petunequip p1
!party
!petreset
```

`!petgrant Bunny` may be run repeatedly. Each copy gets a different Uid, but two Bunny instances still cannot be equipped together because they share the same `SpeciesId`.

## Important runtime boundary

The automatic Studio preview is testing only. Live servers still start with an empty session inventory and empty party. How the first real pet is obtained remains intentionally undecided for now.
