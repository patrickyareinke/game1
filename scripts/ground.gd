extends Node2D
## Draws the terrain from world data. No grid lines: tiles are textured and
## dirt/water overlap their neighbours with ragged edges.

const ATLAS := preload("res://assets/tiles/terrain.png")
const CELL := Vector2(40, 20)          # atlas cell size
const DRAW_OFFSET := Vector2(-20, -2)  # atlas cell vs. diamond top corner
const HIGHLIGHT := Color(1, 1, 1, 0.3)

var world: Node2D
var hover := Vector2i(-1, -1)
var highlight := Node2D.new()   # build-mode cursor, redrawn alone (map is big)


func _ready() -> void:
	highlight.draw.connect(_draw_highlight)
	add_child(highlight)


func _process(_delta: float) -> void:
	var cell: Vector2i = world.screen_to_grid(get_global_mouse_position())
	if cell != hover or not Game.build_mode:
		hover = cell
		highlight.queue_redraw()


func _draw_highlight() -> void:
	if Game.build_mode and world.in_bounds(hover):
		var t: Vector2 = world.grid_to_screen(hover)
		highlight.draw_colored_polygon(PackedVector2Array([
			t, t + Vector2(16, 8), t + Vector2(0, 16), t + Vector2(-16, 8)
		]), HIGHLIGHT)


func _tile(cell: Vector2i, index: int) -> void:
	var dest := Rect2(world.grid_to_screen(cell) + DRAW_OFFSET, CELL)
	draw_texture_rect_region(ATLAS, dest, Rect2(Vector2(index * CELL.x, 0), CELL))


func _draw() -> void:
	var n: int = world.MAP_SIZE
	# 1) grass everywhere (also under dirt/water so ragged edges show grass)
	for y in n:
		for x in n:
			var c := Vector2i(x, y)
			var v: int = world.variant_at(c)
			_tile(c, 4 + v % 2 if v < 8 else v % 4)
	# 2) dirt paths, 3) water
	for kind in [world.T.DIRT, world.T.WATER]:
		var base := 6 if kind == world.T.DIRT else 8
		for y in n:
			for x in n:
				var c := Vector2i(x, y)
				if world.terrain_at(c) == kind:
					_tile(c, base + world.variant_at(c) % 2)
