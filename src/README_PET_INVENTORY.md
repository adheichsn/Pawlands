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
- Pet icon, base damage, special variant, equipped state, and favorite state are bound to the authored tile.
- The default `Normal` variant is presentation-hidden; only non-default variants render their authored Variant row.
- Equipped Pets render in the authored top party strip and are removed from the lower unequipped inventory grid.
- The top party strip clones the complete authored `Top > AddFrame > AddTile` slot template four times; equipped slots replace only the inner `AddTile` presentation with a cloned authored Pet `Tile`.
- Search only filters the lower unequipped inventory grid; it never hides equipped Pets.
- Party count uses the shared max party size (4).
- Inventory and starter-choice modal ScreenGuis ignore the Roblox inset so their authored dimmer reaches the top viewport edge.
- `AutoOptions`, `SellAll`, and `Configuration` are hidden for the current minimal Inventory pass.
- Items are not implemented yet; the authored Items tab resolves to the empty state.
- Inventory/favorite state is session-only until persistence is introduced.

Combat roster lock:
- Inventory remains a per-player modal and never pauses or changes the server simulation for other players.
- Search, Favorite mode, and Inventory viewing remain available while that player is in combat.
- Equip, unequip, and other party mutations are rejected server-side while a live Slime is in `Notice`, `Chase`, `Engage`, or `Attack` against that player or one of that player's Pets.
- The roster remains locked for a short 1.75-second grace after the last live engagement clears, preventing rapid combat/free/combat flicker during target transitions.
- Rejected roster changes show the existing TextNotification message: `Pet party can't be changed during combat.`
- The guard mirrors its current state to the Player attribute `PawlandsPetPartyLocked` for future UI/readability work; this patch does not redesign or disable Pet tiles.

Tutorial handoff:
- Equipping the exact starter Pet UID completes `EquipStarterPet` server-side.
- Progress moves to `PetCombatReady`, reserved for the next guided Pet-combat stage.
