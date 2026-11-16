# Iso Survival

Isometric 2D building & survival game in SNES-style pixel art, made with **Godot 4**.

## Run it

1. Install Godot 4 (standard version) from <https://godotengine.org/download>
2. Godot Project Manager → **Import** → select `project.godot` in this folder
3. Press **F5**

Controls:
- **WASD**: walk
- **Left click**: swing stick toward the mouse (cuts bushes, shakes trees)
- **B**: toggle build mode (left click places a crate, right click removes it)

## Folder layout

```
project.godot              settings: 480x270 pixel view scaled 3x, sharp pixels
scenes/main.tscn           main scene (Main node with world.gd)
scripts/world.gd           map generation, props, building, collision
scripts/ground.gd          draws the terrain (no grid lines)
scripts/player.gd          character: movement, walk animation, stick swing
assets/tiles/terrain.png   terrain atlas, 10 cells of 40x20
assets/sprites/*.png       player, tree, bush, rock, crate, stick
tools/make_placeholder_art.py  regenerates all placeholder art
```

## Replacing the placeholder art

Draw your own PNGs with the same size and layout and overwrite the files:

| File | Size | Layout |
|---|---|---|
| `assets/sprites/player.png` | 72x104 | 4x4 frames of 18x26. Rows: down, up, left, right. Columns: walk cycle. Feet at (9, 24) in each frame |
| `assets/tiles/terrain.png` | 400x20 | 10 cells of 40x20, iso diamond 32x16 at offset (4,2). 0-3 grass, 4-5 grass+flowers, 6-7 dirt, 8-9 water |
| `assets/sprites/tree.png` | 34x46 | trunk base at (17, 42) |
| `assets/sprites/bush.png`, `rock.png`, `crate.png`, `stick.png` | see `FOOT` in world.gd | |

## Roadmap

- [x] Isometric grid, place/remove blocks
- [x] Player with WASD movement and stick swing
- [x] Generated level: grass, paths, ponds, trees, rocks, bushes
- [ ] Building types with resource costs
- [ ] Resource tick (wood, stone, food)
- [ ] Day/night + threats
- [ ] Save/load
