# Power Battles (Roblox)

A team arena fighter (1v1 to 5v5, best of 3) on fully destructible maps, built around swords, anime-style abilities, parry and dash i-frames, ragdolls, Play of the Game, and Clash Royale-style card levelling from end-of-match chests.

- **Design doc:** [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md)
- **Tuning:** everything lives in [`src/shared/Config`](src/shared/Config)

> This folder is self-contained and is not related to the GSC scripts elsewhere in this repository.

## Setup (Rojo)

1. Install [Rojo](https://rojo.space) (7.4+) and the Rojo Studio plugin.
2. Create a new Baseplate place in Studio. **Delete the default `Baseplate` and `SpawnLocation`.**
3. From this folder run `rojo serve`, then click **Connect** in the Studio plugin.
4. Game Settings:
   - **Avatar → Avatar type: R15.** Ragdolls and the sword grip expect R15.
   - **Security → Enable Studio Access to API Services** if you want saving in Studio. Without it, data falls back to memory and a warning prints.
5. Press **Play**. You land in the main menu. To test a 1v1, use **Test → Clients and Servers → 2 players** and both pick PLAY → 1v1.

`default.project.json` already sets `Players.CharacterAutoLoads = false` and turns off the built-in shift-lock toggle (the game forces its own shift lock in matches).

## Project layout

```
src/
  shared/                 → ReplicatedStorage.Shared
    Config/               all tunable data
      Swords.luau         25 swords (archetypes, rarity, passives, procedural visuals)
      Abilities.luau      25 abilities (kind, stats, theme colours)
      Rarities / Progression / Chests / GameModes / Combat / Keybinds / Shop / Animations
    Lib/
      CardLevels.luau     card + level rules (pure, shared by server & UI)
      ChestRoller.luau    chest rolls, odds, pity (pure)
      SwordBuilder.luau   procedural or artist sword models + hand weld
      VFX.luau            procedural anime VFX (slashes, explosions, beams, auras...)
      Anim.luau, Catalog.luau, Signal.luau
    Net.luau              every RemoteEvent / RemoteFunction
  server/                 → ServerScriptService.Server
    Services/
      DataService         DataStore + session lock + autosave
      MatchService        queues, map vote, custom lobbies, round loop, arena slots
      CombatService       swords, parry, dash i-frames, damage, status, passives
      AbilityService      8 ability kinds, server-simulated projectiles
      DestructionService  voxel splitting + structural collapse
      RagdollService      R15 ball-socket ragdolls
      POTGService         recording + highlight scoring
      ChestService, ShopService, LoadoutService
    Modules/MapBuilder    loads ServerStorage.Maps.<Id> or generates a destructible arena
  client/                 → StarterPlayerScripts.Client
    Controllers/          Menu, Hud, Movement, ShiftLock, Combat, Fx, POTG, Chest
    UI/Kit.luau, UI/Screens/{Play,Loadout,Shop,Settings,Info}Screen.luau
```

## Adding your own content

| What | Where |
|---|---|
| Sword model | `ReplicatedStorage.Assets.Swords.<SwordId>`: a Model with a `Handle` part at the grip and the blade along the Handle's +Y. Used instead of the procedural sword. |
| Ability VFX | `ReplicatedStorage.Assets.VFX.<AbilityId>.Projectile` (a part) and/or `.Impact` (a part or model; set an `EmitCount` attribute on emitters). |
| Animations | Paste the asset IDs into `src/shared/Config/Animations.luau`. Empty IDs are skipped. |
| Maps | `ServerStorage.Maps.<MapId>` (IDs from `GameModes.Maps`). It needs a part named `Baseplate` and a `Spawns/Team1` + `Spawns/Team2` folder of spawn parts. Build destructible things from anchored **Block** parts; wedges and meshes break off whole. Use the attribute `Indestructible = true` for anything else that must survive. Without a template map, a procedural one is generated. |
| Shop items | Set real Developer Product / Game Pass IDs in `Config/Shop.luau`. |
| Sounds | Parent music to `SoundService.Music` and effects to `SoundService.SFX` (SoundGroups created at runtime) so the volume sliders work. |
| New ability | Add an entry to `Abilities.List` using one of the 8 kinds. No code needed. |

## Status

All 47 Luau files parse as valid Luau (checked with StyLua's Luau parser) and are formatted with the included `stylua.toml`. The game has **not yet been run inside Roblox Studio** (it was written outside Studio), so expect a first round of in-engine fixes and tuning: grip offsets, animation timing, VFX scale and balance.
