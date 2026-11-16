# Iso Survival

Isometric 2D building & survival game in SNES-style pixel art, made with **Godot 4**.

## Run it

1. Install Godot 4 (standard version) from <https://godotengine.org/download>
2. Godot Project Manager → **Import** → select `project.godot` in this folder
3. Press **F5**

Controls: **left click** = place block, **right click** = remove block.

## Folder layout

```
project.godot        Godot project settings (480x270 pixel viewport, scaled 3x)
scenes/main.tscn     Main scene
scripts/iso_world.gd Isometric grid: drawing, mouse picking, building
assets/sprites/      Character / building sprites (later)
assets/tiles/        Ground tiles (later)
```

## Roadmap

- [x] Isometric grid, place/remove blocks
- [ ] Camera pan & zoom
- [ ] Building types with resource costs
- [ ] Resource tick (wood, stone, food)
- [ ] Day/night + threats
- [ ] Save/load
