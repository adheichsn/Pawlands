# Pawlands Pet Inventory Runtime Foundation

The Studio-authored `StarterGui > Inventory` hierarchy remains the visual source of truth.
Runtime code does not create GUI hierarchy; it only clones the authored Pet `Tile` template.

Current behavior:
- HUD `InventoryButton > KeyButton` opens the Inventory.
- `Close` closes it and releases the interaction lock.
- Pet tiles are populated from server-owned session inventory.
- Clicking a Pet tile equips/unequips it when Favorite mode is OFF.
- `Favorite: ON` changes Pet-tile clicks into server-authoritative favorite toggles.
- Search filters the current Pet tiles locally.
- Pet icon, base damage, variant, equipped state, and favorite state are bound to the authored tile.
- Party count uses the shared max party size (4).
- `AutoOptions`, `SellAll`, and `Configuration` are hidden for the current minimal Inventory pass.
- Items are not implemented yet; the authored Items tab resolves to the empty state.
- Inventory/favorite state is session-only until persistence is introduced.

Tutorial handoff:
- Equipping the exact starter Pet UID completes `EquipStarterPet` server-side.
- Progress moves to `PetCombatReady`, reserved for the next guided Pet-combat stage.
