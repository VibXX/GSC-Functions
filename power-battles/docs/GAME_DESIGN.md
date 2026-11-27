# Power Battles: Game Design Document

> Team arena fighter for Roblox. 1v1 to 5v5, best of 3 rounds, on maps where everything except the floor can be destroyed. You fight with a main sword and one anime-style ability. Swords and abilities come from end-of-match chests and level up Clash Royale style by collecting duplicate cards.

Every number in this doc lives in `src/shared/Config/*`. Change it there and the whole game follows.

---

## 1. Core loop

```
Main menu ──PLAY──► pick mode / custom game ──► map vote ──► MATCH (best of 3)
    ▲                                                         │
    │                                       after every round │ Play of the Game (skippable)
    │                                                         ▼
    └──── back to menu ◄── open chest (Victory / Defeat) ◄── results + scoreboard
                │
                └─► LOADOUT: equip / level up swords + abilities with cards & coins
```

## 2. Modes

| Mode | Players | Notes |
|---|---|---|
| 1v1 to 5v5 | 2 to 10 | Matchmade queue. When a queue fills, those players vote on 1 of 3 random maps (12 s). |
| Custom Game | 2 to 10 | The host creates a lobby and sets team size, rounds to win (1 to 5), round time (60/90/150/240 s) and the map (fixed or vote). Toggles: **Abilities**, **Map Destruction**, **Card Level Buffs** (off = everyone at base stats), **Play of the Game**. |

**Match rules** (`GameModes.Rules`):
- Best of 3: first team to 2 round wins takes the match.
- 3 s frozen countdown before each round.
- A round lasts 150 s. On time-out, the team with more total health % wins. A tie counts as a draw and nobody scores.
- No respawns inside a round. Dead players spectate a living teammate.
- The map is rebuilt fresh every round, so all destruction resets.
- If a whole team leaves, it forfeits.
- Up to 4 matches run at once per server, each in its own arena slot.

## 3. Combat

### Health and movement
| | Value |
|---|---|
| Max health | 150 (no regeneration) |
| Walk / sprint speed | 16 / 26 (hold Shift); the sword archetype scales it ×0.93 to ×1.06 |
| Jump / double jump | 50 / 58. One air jump. The double-jump VFX uses the **colours of your equipped ability**. |
| Dash | 24 studs over 0.18 s. **0.28 s of i-frames** (cannot be hit). 1.4 s cooldown. Directional animations. |
| Shift lock | Forced on in matches. The camera sits over the right shoulder, the character faces the camera, and the crosshair is screen centre. |

### Sword (primary weapon)
- Hold or click to swing. Swings chain into a combo, and the **last hit is a finisher** (×1.5 to ×1.8 damage plus a launch).
- The server checks a box hitbox in front of the attacker after a short wind-up (`HitDelay`), so the hit lines up with the animation.
- There are four **archetypes**. Rarity then scales damage (Common ×1.00 up to Mythic ×1.20):

| Archetype | Damage | Swing CD | Reach | Combo | Finisher | Move |
|---|---|---|---|---|---|---|
| Light | 7.5 | 0.30 s | 6.5 | 5 | ×1.5 | ×1.06 |
| Balanced | 10 | 0.42 s | 7.5 | 4 | ×1.6 | ×1.00 |
| Heavy | 15 | 0.68 s | 9 | 3 | ×1.8 | ×0.93 |
| Rapier | 9 | 0.38 s | 10 | 4 | ×1.7 | ×1.02 |

### Parry
- 0.25 s active window, plus 0.1 s of server-side latency grace. 1 s cooldown.
- You must roughly **face** the attack.
- Parrying a **sword hit** blocks it fully, **stuns the attacker for 1 s** and refunds your parry cooldown. Parrying a **projectile** deflects it.
- Beams, cones, novas and meteors cannot be parried. Dash through those instead.
- Starting a swing cancels your own parry, so you can't parry-spam while attacking.

### Abilities (secondary)
- One equipped ability. It **fires toward the crosshair** (the server raycasts from the camera centre and clamps range).
- **Every ability ragdolls whoever it hits.** The R15 ragdoll uses ball-socket joints, launches the victim away from the blast, and grants 0.6 s of immunity after they stand up, which prevents ragdoll-locking.
- Abilities also **destroy the map** (see §5).
- There are eight generic behaviours (*kinds*), so a new ability is pure data: Projectile, Beam, Nova, Cone, Meteor, Line, Blink, Vortex.

### Status effects
Burn / Bleed / Poison (damage over time), Slow, Root, Vulnerable (+% damage taken), Stun (after being parried).

## 4. Swords and abilities

### Rarity
Common · Uncommon · Rare · Epic · Legendary · Mythic. Rarer items get bigger numbers, a passive (swords) and flashier VFX: glowing edges, lights, particles and a rarity gem in the guard.

### The 25 swords
Starter: **Initiate's Blade**, a polished steel longsword with a faint white edge glow and a clean slash trail.

| # | Sword | Rarity | Archetype | Passive |
|---|---|---|---|---|
| 1 | Initiate's Blade | Common | Balanced | — |
| 2 | Rusted Cleaver | Common | Heavy | — |
| 3 | Twin Fang | Common | Light | — |
| 4 | Militia Saber | Common | Balanced | — |
| 5 | Ashwood Katana | Common | Light | — |
| 6 | Tidecaller | Uncommon | Balanced | Slow 15% 1.2s |
| 7 | Emberedge | Uncommon | Balanced | Burn 2×3 |
| 8 | Frostbite | Uncommon | Light | Slow 20% 1.5s |
| 9 | Galebreaker | Uncommon | Rapier | Finisher launches |
| 10 | Thornroot | Uncommon | Heavy | Bleed 1.5×4 |
| 11 | Stormfang | Rare | Light | Chain 40% |
| 12 | Obsidian Reaver | Rare | Heavy | Lifesteal 12% |
| 13 | Moonlit Crescent | Rare | Balanced | Finisher +40% |
| 14 | Venomspire | Rare | Rapier | Poison 2×4 |
| 15 | Sunforged Claymore | Rare | Heavy | Burn 3×2 |
| 16 | Phantom Edge | Epic | Light | Swing 12% faster |
| 17 | Crimson Requiem | Epic | Balanced | Lifesteal 15% |
| 18 | Voidrender | Epic | Heavy | Target +10% dmg taken 3s |
| 19 | Wyrmspine | Epic | Heavy | Burn 3×3 |
| 20 | Celestial Judgement | Legendary | Balanced | Finisher +60% |
| 21 | Abyssal Maw | Legendary | Heavy | Lifesteal 18% |
| 22 | Raijin's Verdict | Legendary | Rapier | Chain 60% |
| 23 | Inferno Sovereign | Legendary | Heavy | Burn 4×3 |
| 24 | Eclipse | Mythic | Balanced | Target +15% dmg taken 3s |
| 25 | Genesis Blade | Mythic | Balanced | Chain 50% |

### The 25 abilities
Starter: **Fireball**, a glowing core inside a translucent shell with a fire trail, light and particles. It explodes with a white flash, an expanding sphere, double shockwave rings, embers, smoke, a light pulse and screen shake.

| # | Ability | Rarity | Kind | Damage | CD | Notes |
|---|---|---|---|---|---|---|
| 1 | Fireball | Common | Projectile | 20 | 5 s | Starter. Explodes on impact. |
| 2 | Boulder Hurl | Common | Projectile | 24 | 6.5 s | Lobbed arc (gravity) |
| 3 | Wind Slash | Common | Projectile | 16 | 4 s | Flying crescent, pierces players |
| 4 | Frost Shard | Common | Projectile | 8 ×3 | 5 s | 3-shot spread, slow |
| 5 | Spark Bolt | Common | Beam | 17 | 5 s | Instant lightning |
| 6 | Water Lance | Uncommon | Projectile | 22 | 6 s | Fast spear, pierces |
| 7 | Ember Burst | Uncommon | Cone | 26 | 7 s | Burn |
| 8 | Gale Push | Uncommon | Cone | 14 | 6 s | Huge knockback |
| 9 | Vine Snare | Uncommon | Projectile | 14 | 7 s | Root 1.2 s |
| 10 | Shock Orb | Uncommon | Vortex | 12 (+4/0.5 s) | 8 s | Slow orb that zaps everything near it |
| 11 | Chain Lightning | Rare | Beam | 22 | 7 s | Arcs to 2 more enemies |
| 12 | Magma Meteor | Rare | Meteor | 34 | 9 s | 1 s telegraph ring, burn |
| 13 | Glacier Spike | Rare | Line | 26 | 8 s | 8 ice spikes along the ground, slow |
| 14 | Shadow Step | Rare | Blink | 22 | 8 s | Teleport to aim point and detonate |
| 15 | Crescent Wave | Rare | Projectile | 28 | 8 s | Giant crescent, pierces |
| 16 | Dragon's Breath | Epic | Beam | 36 | 11 s | **Carves through walls**, burn |
| 17 | Void Rift | Epic | Vortex | 30 (+3/0.25 s) | 12 s | Drifting rift that pulls enemies in |
| 18 | Thunder Spear | Epic | Projectile | 38 | 10 s | Fastest projectile in the game |
| 19 | Blood Moon Nova | Epic | Nova | 34 | 12 s | Heals you for 30% of damage dealt |
| 20 | Solar Flare Cannon | Legendary | Beam | 44 | 14 s | 0.5 s charge, then **carves** a 200-stud line through the map |
| 21 | Abyssal Hands | Legendary | Meteor | 14 ×5 | 13 s | Hands erupt around the target and root it |
| 22 | Tempest Cyclone | Legendary | Vortex | 20 (+4/0.25 s) | 14 s | Tornado that shreds buildings and pulls enemies in |
| 23 | Phoenix Dive | Legendary | Blink | 42 | 14 s | Dive bomb, burn |
| 24 | Starfall | Mythic | Meteor | 16 ×9 | 16 s | Star barrage over an area |
| 25 | Oblivion | Mythic | Vortex | 55 (+4/0.25 s) | 18 s | Collapsing star: massive pull, then erase |

### VFX pipeline
- All VFX is **procedural by default**: neon parts, curved Beams for the slash arcs, Trails, ParticleEmitters and lights, tinted by each item's theme colours. The game is fully playable and readable before any art exists.
- **Artist drop-in, no code changes:**
  - `ReplicatedStorage.Assets.Swords.<SwordId>`: a Model with a `Handle` part at the grip, blade along +Y.
  - `ReplicatedStorage.Assets.VFX.<AbilityId>.Projectile`: a part that replaces the projectile body.
  - `ReplicatedStorage.Assets.VFX.<AbilityId>.Impact`: a part or model with emitters. Each emitter fires `EmitCount` (attribute) particles.
- Animations are listed in `Config/Animations.luau` (dash ×4 directions, double jump, sprint, 5 swing slots, parry, parry-success, stunned, cast per kind or per ability, menu idle). An empty ID is skipped.

## 5. Destruction (Teardown-style)
- Every anchored part on the map is destructible **except the base plate**. Mark other indestructible parts with the attribute `Indestructible = true`.
- **Blast → voxel split:** each block part touching the blast sphere is recursively halved along its longest axis. Pieces outside the sphere stay anchored as smaller blocks, which leaves real holes in walls. Pieces inside it become physics debris and are flung outward.
- **Structural collapse:** after a blast, a budgeted flood-fill checks whether nearby chunks still connect to the ground. Anything floating falls, so blowing out a tower's base brings the tower down.
- **Carving beams** (Dragon's Breath, Solar Flare Cannon) cut a tunnel along their whole length. Vortexes chew through structures as they travel.
- **Performance guards:** at most 260 new parts per explosion, at most 500 debris pieces per match (oldest removed first), debris fades after 7 to 12 s. Debris collides with the world but not with players, so movement stays smooth in 5v5.

## 6. Play of the Game
- The server records every fighter's root CFrame at 10 Hz plus a combat log (swings, casts, impacts, damage, kills, parries, dashes, double jumps).
- At round end it scores every 8-second window per player: **kill 100**, **damage ×1.2**, **parry 45**, and multi-kill bonuses (+80 / +220 / +400 / +650). The best window is played back to everyone, titled ELIMINATION, DOUBLE ELIMINATION and so on up to TEAM WIPE.
- Clients rebuild the clip with ghost copies of the characters (run/idle animations, all VFX re-fired) and a cinematic over-the-shoulder camera with letterbox bars.
- **Skippable:** press the skip key (default X) or click SKIP. The round moves on once everyone has skipped. **Auto-skip** is available in Settings.
- *v2 idea:* also record debris and replay the destruction on a fresh copy of the map. Right now the clip plays on the already-damaged map.

## 7. Progression: chests and cards

### Chests (one per match)
| | Victory Chest | Defeat Chest |
|---|---|---|
| Card drops | 3 | 1 |
| Coins | 60 to 90 | 20 to 30 |
| Common | 50% | 62% |
| Uncommon | 28% | 25% |
| Rare | 14% | 9.5% |
| Epic | 6% | 3% |
| Legendary | 1.7% | 0.45% |
| Mythic | 0.3% | 0.05% |

- Each drop is a 50/50 sword or ability, then a random item of that rarity. When you're missing items of that rarity, a **35% bias toward unowned items** applies.
- Cards per drop: Common 4 to 8, Uncommon 3 to 5, Rare 2 to 3, Epic 1 to 2, Legendary 1, Mythic 1.
- **Pity:** a guaranteed Legendary-or-better within 40 chests, and a Mythic within 120.
- The chest-opening screen shakes the chest, bursts it open, shows coins, then reveals cards from lowest to highest rarity. Rare hits get a longer pause.

### Card levels
- The first card unlocks the item at **level 1**. Each level costs cards plus coins and gives **+2% damage** (abilities also get **−1% cooldown**). Max level is 10 (+18% damage).

| Upgrade to → | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|
| Common cards | 2 | 4 | 10 | 20 | 40 | 80 | 150 | 250 | 400 |
| Uncommon | 2 | 4 | 8 | 15 | 30 | 60 | 100 | 160 | 250 |
| Rare | 1 | 2 | 4 | 8 | 15 | 30 | 50 | 80 | 120 |
| Epic | 1 | 2 | 3 | 5 | 8 | 12 | 18 | 26 | 36 |
| Legendary | 1 | 1 | 2 | 3 | 4 | 6 | 8 | 10 | 14 |
| Mythic | 1 | 1 | 1 | 2 | 2 | 3 | 4 | 5 | 6 |
| Coins | 20 | 50 | 150 | 400 | 1k | 2k | 4k | 8k | 15k |

### Simulated economy
These figures come from a 400-player Monte Carlo of the real roll logic at a 50% win rate.

| Milestone | Median matches |
|---|---|
| First Legendary drop | ~24 |
| First Mythic drop | ~120 (almost always from pity) |
| All 50 items unlocked | ~600 |
| Starter sword after 100 matches | ~58 cards → about level 6 |

**Tuning notes:**
- Maxing one item costs about 30.8k coins, roughly 600 matches of coins. That is deliberately long-tail. Lower `CoinsToUpgrade` if it feels grindy.
- Mythic drops come almost entirely from pity. Raise the Mythic weight if you want natural drops to happen.
- Card levels are a PvP power gap, capped at +18%. Custom games can switch them off, and ranked play (if added later) should matchmake on average item level.

## 8. Main menu
The look follows your reference: a dark, foggy gothic street with the player's own character in the middle, **back to the camera**, holding the equipped sword in a resting pose. The character is wrapped in an **aura in the equipped ability's colours** (rising motes, soft flames, coloured light). A cold light at the end of the street backlights them as a silhouette.

- **Title:** "Power Battles" in a blackletter gothic font, centred over the character.
- **Menu:** PLAY · LOADOUT · SHOP · SETTINGS · INFORMATION. The selected item turns gold with a gold gradient bar behind it. Works with mouse hover, ↑/↓ or W/S plus Enter, and gamepad D-pad plus A.
- **Footer:** coins and app version bottom-right in muted gold.
- **Ambience:** slow camera sway, drifting ground fog and motes, desaturated colour grading, bloom.

| Page | Contents |
|---|---|
| PLAY | Mode cards 1v1 to 5v5 (join queue), a custom-game browser (create / join / refresh), the custom lobby (host settings, start / leave) and the map-vote overlay with live vote counts and a timer. A queue status pill with CANCEL stays visible on every page. |
| LOADOUT | Swords / Abilities tabs. A grid of all 25 items sorted by rarity, showing locked state, level and card progress; upgradeable items are highlighted gold. The detail panel shows live stats at your level, the passive, a card progress bar, EQUIP, and UPGRADE (coin cost). |
| SHOP | Coin packs, a Victory Chest Key with **odds shown**, and a VIP pass. |
| SETTINGS | Rebind every action (click, then press a key; duplicates swap). Master / music / SFX volume, mouse sensitivity, FOV, screen shake, effects quality (Low / Med / High), damage numbers, auto-skip POTG. Save / reset. |
| INFORMATION | Goal, controls (shows your current binds), sword combat, parry, dash, abilities, chests and cards, rarities, POTG. |

## 9. Monetisation (Shop)
Everything is configured in `Config/Shop.luau`. Set the real product and pass IDs; an ID of 0 shows "COMING SOON".

| Item | Type | Grants |
|---|---|---|
| Pouch / Chest / Vault of Coins | Dev product | 500 / 1,500 / 5,000 coins |
| Victory Chest Key | Dev product (paid random item) | Opens a Victory Chest |
| VIP | Game pass | +25% chest coins, gold nameplate |

**Compliance:** Roblox requires that paid random items show their odds (the shop does), and that they are hidden where `PolicyService.ArePaidRandomItemsRestricted` is true. The server enforces this and fails closed.

**Ideas that avoid pay-to-win:** cosmetic sword skins and recolours, ability VFX recolours, menu auras, kill effects, POTG intro poses, a battle pass of cosmetics.

## 10. Default controls
| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Attack | LMB (hold to chain) | R2 |
| Ability | E | R1 |
| Parry | F | L1 |
| Dash | Q | B |
| Sprint | Hold Left Shift | L3 |
| Jump / double jump | Space | A |
| Skip POTG | X | Y |

## 11. Technical architecture
- **Server-authoritative:** hit detection, damage, cooldowns, parry and i-frames, projectile simulation (spherecasts, no physical parts), destruction, chest rolls, data and purchases. Clients only predict visuals: slash arcs, dash, double jump.
- **Networking:** one `Net` module declares every remote. Ability visuals are sent once at cast (`AbilityFx`, with server timestamp for latency catch-up), then `AbilityTick` for vortex positions and `AbilityImpact` for explosions.
- **Data:** DataStore with session locking, reconcile-on-load for new fields, 120 s autosave, save on leave and on shutdown, and an idempotent purchase history. In Studio without API access it falls back to memory automatically.
- **Arena slots:** each match is a `Folder` far apart in Workspace with its own map and debris. Menu stages are private per player and far from the arenas.
- **Anti-exploit basics:** server cooldowns with tolerance, aim-distance clamp, team checks on every damage call, and input validation on every RemoteFunction.

## 12. Roadmap / next steps
1. **Art pass:** sword models, authored ability VFX (Projectile / Impact drop-ins), animations, SFX and music (put them in the `Music` / `SFX` SoundGroups so the sliders work).
2. **Hand-built maps** in `ServerStorage.Maps` (see the README for requirements). The procedural maps are placeholders.
3. **Playtesting and balance** on a live server with 10 players, especially parry window, dash i-frames, ragdoll durations and damage of the top-rarity abilities.
4. Multi-place scaling: a lobby place plus reserved-server match places via TeleportService and MemoryStore queues, when one server isn't enough.
5. Ranked mode, daily quests, a cosmetics battle pass, and POTG destruction replay.
