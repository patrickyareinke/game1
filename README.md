# Iso Survival

Isometric 2D building & survival game in SNES-style pixel art, made with **Godot 4**.

## Run it

1. Install Godot 4 (standard version) from <https://godotengine.org/download>
2. Godot Project Manager → **Import** → select `project.godot` in this folder
3. Press **F5**

Controls:
- **WASD**: walk (hold **Shift** to run)
- **Left click**: swing stick toward the mouse (hits slimes, cuts bushes, shakes trees)
- **Right click**: cast the active spell toward the mouse
- **Q**: spell ring (pick Fireball, Mudball or Magic Fiststamp; or press 1/2/3)
- **E**: inventory (5x8) with coins and stats; click the spellbook to read your spells
- **F**: pick up what lies at your feet (hidden stash, monster remains), otherwise scoop water at a pond
- **Mouse wheel**: switch tool (stick / axe / pickaxe), or click a tool in the inventory
- **B**: toggle build mode (left click places a crate, right click removes it)

## World, village & tools

Every game generates a new random 160x160 world. Somewhere on it is a village (fireplace + 3-5 huts) where you start.

| Tool | Harvests | Melee damage |
|---|---|---|
| Stick | bushes only | 1.0x |
| Axe | trees -> 2-4 Wood (3 hits; the tree falls, logs land on the ground, pick up with F) | 1.3x |
| Pickaxe | rocks -> 2-3 Stone (3 hits, pick up with F) | 1.1x |

## The mountain & the Hive Mantis

At the very top of the map is a mountain: a handful of snowy peaks behind one very big front mountain with the cave mouth at its base. A gravel road leads from the village to the cave on every map (through rivers as a ford). Walk in to enter the boss cave (walk onto the glowing exit to leave).

The **Hive Mantis** guards its heart with a claw cage:
1. **Burst the cage**: only *Magic Fiststamp* hurts it - 3 fist hits break it open (fireballs and the stick just bounce off).
2. **Burn the heart**: only *fireballs* damage the exposed heart (30 HP). After 12 s the claws close again.

Entering the cave plays a short intro (fade to black, reveal, roar). Six slimes crawl around the boss room, half of them spit slime. The boss spits acid at you and slams its claws where a red circle appears. If you faint, you wake up at the village fire and the boss heals. Reward: 100 coins. Behind the boss hangs a silk cocoon: once the Mantis is dead, burst it with a fireball or Magic Fiststamp (2 hits) to free the girl inside.

## Stats & spells

All stats start at 1 and are shown as whole numbers.

| Stat | Grows by | Effect |
|---|---|---|
| Fighter | +0.005 per stick hit on an enemy | stick damage |
| Alchemy | +0.005 per spell cast | spell damage |
| Building | +0.005 per placed crate | (none yet) |
| Fitness | +0.001 per tile walked | walking speed |
| Wisdom | (not decided yet) | (none yet) |

Every cast also makes that spell +0.01 stronger.

| Spell | Ingredients | Effect |
|---|---|---|
| Fireball | 1 Oil + 1 Ash | 3 damage, burns bushes into 2 Ash |
| Mudball | 1 Water | 1 damage, slows for 3 s |
| Magic Fiststamp | none (2 s cooldown) | 2 area damage anywhere at the cursor + knockback |

### Upgrades

After a spell hits enemies 10 times, the game pauses and you pick one of three upgrades (once per spell). Spell effects never hurt the player.

| Spell | Option A | Option B | Option C |
|---|---|---|---|
| Fireball | **Big Fireball**: +60% damage | **Triple Fireball**: 3 in a fan, 70% each | **Lavaball**: leaves a lava blob that burns enemies |
| Mudball | **Sticky Puddle**: slowing mud puddle | **Ricochet Mud**: bounces to 2 more enemies | **Quicksand**: enemies stuck for 2 s |
| Magic Fiststamp | **Slap Hand**: bigger push-back area, 60% damage | **Double Fist**: two fists scattered around the cursor | **Fast Fist**: +25% damage, quake slows enemies |

You start with 20 of each ingredient. More come from:
- **Slimes** (200 on the 160x160 map, 3 kinds), each dropping 1-2 of its ingredient plus 1-3 coins:
  - Oil Slime (amber): normal speed, 3 HP
  - Ash Slime (grey, embers): fast, 2 HP
  - Water Slime (blue): slow, 4.5 HP
- Burning bushes with a fireball (2 Ash), pressing F at a pond (1 Water)

400 hidden stashes lie next to trees (oil), rocks and bushes (ash) and ponds (water), each marked only by a very faint tile-shaped ring. Stand on it and press F.

Killed slimes leave remains (a goo splat with their ingredient and some coins) on their tile; press F there to collect, and the remains disappear.

## Folder layout

```
project.godot              settings: 480x270 pixel view scaled 3x, sharp pixels
scenes/main.tscn           main scene (Main node with world.gd)
scripts/world.gd           map generation, props, building, collision
scripts/ground.gd          draws the terrain (no grid lines)
scripts/player.gd          character: movement, animations, stick, spells, HP
scripts/girl.gd            the girl in the victory scene
scripts/game_state.gd      autoload "Game": inventory, coins, stats, spells
scripts/ui.gd              HUD, inventory, spell ring, spellbook
scripts/enemy.gd           slime enemy
scripts/projectile.gd      fireball / mudball
scripts/fx.gd              impact ring effect
scripts/pickup.gd          ground pickups: hidden stashes, monster remains, logs/stone
scripts/cocoon.gd          the cocoon behind the boss
tools/make_pixel_font.py   hand-drawn SNES-style pixel font (assets/fonts/pixel.fnt)
scripts/zone.gd            lava / mud puddle / quake ground effects
scripts/boss.gd            Hive Mantis end boss
scripts/boss_spit.gd       boss acid spit
scripts/warning.gd         red warning circle (boss claw slam)
assets/icons/*.png         16x16 item and spell icons
assets/tiles/terrain.png   terrain atlas, 10 cells of 40x20
assets/sprites/*.png       player, slimes, tree, bush, rock, crate, stick
tools/make_placeholder_art.py  regenerates all placeholder art
```

## Replacing the placeholder art

Draw your own PNGs with the same size and layout and overwrite the files:

| File | Size | Layout |
|---|---|---|
| `tools/player_source.png`, `tools/girl_source.png` | any | character sheets (rows idle, walk, run, attack, hurt, sleep; 10 frames: 0-3 down, 4-6 right, 7-9 up). Run `python tools/import_player_sheet.py` to turn them into `assets/sprites/player_sheet.png` / `girl_sheet.png` (68x68 textures = 34x34 game pixels at 2x detail), the HUD face and the blush overlay |
| `assets/tiles/terrain.png` | 640x20 | 16 cells of 40x20, iso diamond 32x16 at offset (4,2). 0-3 grass, 4-5 grass+flowers, 6-7 dirt, 8-9 water, 10-11 mountain rock, 12-13 cave floor, 14-15 cave wall |
| `assets/sprites/tree.png` | 34x46 | trunk base at (17, 42) |
| `assets/sprites/bush.png`, `rock.png`, `crate.png`, `stick.png` | see `FOOT` in world.gd | |

## Roadmap

- [x] Isometric grid, place/remove blocks
- [x] Player with WASD movement and stick swing
- [x] Generated level: grass, paths, ponds, trees, rocks, bushes
- [x] Inventory, stats, spells, slime enemies
- [x] Random world with village, axe/pickaxe harvesting
- [x] Mountain cave with the Hive Mantis end boss
- [ ] Building types with resource costs (wood, stone)
- [ ] Resource tick (wood, stone, food)
- [ ] Day/night + threats
- [ ] Save/load
