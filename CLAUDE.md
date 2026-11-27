# Repository notes for Claude

This repo holds two unrelated things:

1. **GSC scripts** (`gamescripts/`, `universalscripts/`, `utilities/`, ...): Call of Duty modding scripts and game dumps. Leave these alone unless asked.
2. **Power Battles** (`power-battles/`): a Roblox team arena fighter written in Luau, synced into Studio with Rojo. Most work happens here.

## Power Battles

- Read `power-battles/docs/GAME_DESIGN.md` first. It has every design decision and number.
- `power-battles/README.md` covers Rojo setup and the project layout.
- **All tuning is data** in `power-battles/src/shared/Config/`: swords, abilities, rarities, chest odds, card levels, combat timings, modes, keybinds, shop, animation IDs. Change numbers there, not in services, and keep `GAME_DESIGN.md` in sync when you do.
- **New abilities are data:** add an entry to `Config/Abilities.luau` using an existing `Kind` (Projectile, Beam, Nova, Cone, Meteor, Line, Blink, Vortex). Only add a new Kind in `AbilityService` + `FxController` if none fit.
- **Server-authoritative:** damage, cooldowns, parry/i-frames, projectiles, destruction, chests and data live on the server (`src/server/Services`). Clients only predict visuals (`src/client/Controllers`).
- **Remotes** are all declared in `src/shared/Net.luau`. Add new ones there.
- **Artist assets** drop in without code changes: `ReplicatedStorage.Assets.Swords.<Id>` and `ReplicatedStorage.Assets.VFX.<AbilityId>.Projectile` / `.Impact`.
- **Style:** Luau, tabs, formatted with `power-battles/stylua.toml` (`stylua --syntax Luau power-battles/src`).
- **Status:** the code parses and formats cleanly but has **not been run in Roblox Studio yet**. Expect in-engine fixes, such as the sword grip angle, animation timing, VFX scale and balance. Don't claim something works in-game unless it was tested there.
