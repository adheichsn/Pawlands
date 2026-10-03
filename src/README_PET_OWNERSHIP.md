# Pawlands — Pet Ownership & Party Foundation

This patch extends the existing pet-follow foundation without changing its client movement, authored-pivot correction, yaw calibration, 2×2 formation, or 1.5×1.5 ground Blockcast.

## Scope

- Pet inventory uses one unique persistent `Uid` per pet instance (`p1`, `p2`, ...).
- Duplicate species are allowed in inventory so future hatch/variant systems can own multiple copies.
- Equipped party remains capped at **4**.
- Equipped party allows only **one pet per `SpeciesId`**.
- Equip/unequip and full party changes validate ownership on the server.
- Client follow still receives the existing visual pet ids, so follow code does not need to change.
- The original ownership patch did not add persistence; `4A.1.1` now persists exact UID ownership and active party state without changing the ownership rules.

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

The automatic Studio preview remains testing only. Live ownership now hydrates from the player profile; a genuinely new profile starts empty until the existing tutorial starter flow grants its first Pet.
