extends Node2D
## The world: map data, terrain generation, props, building, collision.
## Rendering of the ground lives in ground.gd, the player in player.gd.

const TILE_W := 32
const TILE_H := 16
const MAP_SIZE := 40
const SEED := 1337

enum T { GRASS, DIRT, WATER }

const TEX := {
	"tree": preload("res://assets/sprites/tree.png"),
	"bush": preload("res://assets/sprites/bush.png"),
	"rock": preload("res://assets/sprites/rock.png"),
	"crate": preload("res://assets/sprites/crate.png"),
}
# Sprite offsets so that the image's "foot point" sits on the cell centre.
const FOOT := {
	"tree": Vector2(-17, -42),
	"bush": Vector2(-10, -14),
	"rock": Vector2(-9, -11),
	"crate": Vector2(-17, -25),
}

var terrain := PackedByteArray()   # T per cell, index = y * MAP_SIZE + x
var variant := PackedByteArray()   # random 0..99 per cell for tile variety
var props := {}                    # Vector2i -> { "type": String, "node": Sprite2D }
var build_mode := false

var ground: Node2D
var entities: Node2D
var player: Node2D
var hud: Label


func _ready() -> void:
	_generate()

	ground = preload("res://scripts/ground.gd").new()
	ground.world = self
	add_child(ground)

	entities = Node2D.new()
	entities.y_sort_enabled = true      # things lower on screen draw in front
	add_child(entities)

	for cell in props:
		_spawn_prop_node(cell)

	player = preload("res://scripts/player.gd").new()
	player.world = self
	player.position = cell_center(Vector2i(MAP_SIZE / 2, MAP_SIZE / 2))
	entities.add_child(player)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(4, 2)
	hud.add_theme_font_size_override("font_size", 8)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 2)
	layer.add_child(hud)
	_update_hud()


# --- coordinates -----------------------------------------------------------

func grid_to_screen(cell: Vector2i) -> Vector2:
	## Top corner of the cell's diamond.
	return Vector2((cell.x - cell.y) * TILE_W / 2.0, (cell.x + cell.y) * TILE_H / 2.0)


func cell_center(cell: Vector2i) -> Vector2:
	return grid_to_screen(cell) + Vector2(0, TILE_H / 2.0)


func screen_to_grid(p: Vector2) -> Vector2i:
	var a := p.x / (TILE_W / 2.0)
	var b := p.y / (TILE_H / 2.0)
	return Vector2i(floori((a + b) / 2.0), floori((b - a) / 2.0))


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MAP_SIZE and cell.y < MAP_SIZE


func terrain_at(cell: Vector2i) -> int:
	return terrain[cell.y * MAP_SIZE + cell.x]


func variant_at(cell: Vector2i) -> int:
	return variant[cell.y * MAP_SIZE + cell.x]


func is_walkable_cell(cell: Vector2i) -> bool:
	return in_bounds(cell) and terrain_at(cell) != T.WATER and not props.has(cell)


func is_walkable_at(p: Vector2) -> bool:
	return is_walkable_cell(screen_to_grid(p))


# --- generation ------------------------------------------------------------

func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var n_water := FastNoiseLite.new()
	n_water.seed = SEED
	n_water.frequency = 0.07
	var n_path := FastNoiseLite.new()
	n_path.seed = SEED + 1
	n_path.frequency = 0.035
	var n_forest := FastNoiseLite.new()
	n_forest.seed = SEED + 2
	n_forest.frequency = 0.09

	terrain.resize(MAP_SIZE * MAP_SIZE)
	variant.resize(MAP_SIZE * MAP_SIZE)
	var start := Vector2(MAP_SIZE / 2, MAP_SIZE / 2)

	for y in MAP_SIZE:
		for x in MAP_SIZE:
			var cell := Vector2i(x, y)
			var i := y * MAP_SIZE + x
			var near_start := Vector2(cell).distance_to(start) < 4.0
			var t := T.GRASS
			if n_water.get_noise_2d(x, y) < -0.28 and not near_start:
				t = T.WATER
			elif absf(n_path.get_noise_2d(x, y)) < 0.05:
				t = T.DIRT
			terrain[i] = t
			variant[i] = rng.randi_range(0, 99)

			if t != T.GRASS or near_start:
				continue
			var forest := n_forest.get_noise_2d(x, y)
			var r := rng.randf()
			if forest > 0.15 and r < 0.5:
				props[cell] = {"type": "tree"}
			elif r < 0.025:
				props[cell] = {"type": "rock"}
			elif r < 0.07:
				props[cell] = {"type": "bush"}


func _spawn_prop_node(cell: Vector2i) -> void:
	var type: String = props[cell]["type"]
	var s := Sprite2D.new()
	s.texture = TEX[type]
	s.centered = false
	s.offset = FOOT[type]
	s.position = cell_center(cell)
	entities.add_child(s)
	props[cell]["node"] = s


func _remove_prop(cell: Vector2i) -> void:
	props[cell]["node"].queue_free()
	props.erase(cell)


# --- interaction -----------------------------------------------------------

func hit_at(point: Vector2) -> void:
	## Called by the player's stick swing. Cuts bushes, shakes trees.
	var center := screen_to_grid(point)
	var best := Vector2i(-1, -1)
	var best_d := 14.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := center + Vector2i(dx, dy)
			if not props.has(cell):
				continue
			var d := cell_center(cell).distance_to(point)
			if d < best_d:
				best_d = d
				best = cell
	if best == Vector2i(-1, -1):
		return
	var node: Sprite2D = props[best]["node"]
	match props[best]["type"]:
		"bush":
			_remove_prop(best)
		_:
			var tw := create_tween()
			var x := node.position.x
			tw.tween_property(node, "position:x", x + 1, 0.04)
			tw.tween_property(node, "position:x", x - 1, 0.04)
			tw.tween_property(node, "position:x", x, 0.04)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_B:
		build_mode = not build_mode
		_update_hud()
		ground.queue_redraw()
		return

	var mb := event as InputEventMouseButton
	if not (build_mode and mb and mb.pressed):
		return
	var cell := screen_to_grid(get_global_mouse_position())
	if mb.button_index == MOUSE_BUTTON_LEFT:
		var player_cell := screen_to_grid(player.position)
		if is_walkable_cell(cell) and cell != player_cell:
			props[cell] = {"type": "crate"}
			_spawn_prop_node(cell)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if props.has(cell) and props[cell]["type"] == "crate":
			_remove_prop(cell)


func _update_hud() -> void:
	if build_mode:
		hud.text = "BUILD MODE   L-click: place   R-click: remove   B: exit"
	else:
		hud.text = "WASD: move   Click: swing stick   B: build mode"
