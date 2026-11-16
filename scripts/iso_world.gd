extends Node2D
## Minimal isometric building prototype for Godot 4.
## Left click = place block, right click = remove block.

const TILE_W := 32          # diamond width in pixels
const TILE_H := 16          # diamond height in pixels (2:1 = classic isometric)
const BLOCK_H := 16         # height of a placed block
const GRID_SIZE := 14       # map is GRID_SIZE x GRID_SIZE

# The world is plain data: grid cell -> building. Rendering just reads this.
var buildings := {}         # Dictionary[Vector2i, bool]
var hover := Vector2i(-1, -1)

# SNES-ish palette
const GRASS_A := Color("5a9e3a")
const GRASS_B := Color("4f8c33")
const GRID_LINE := Color("3d6e28")
const HOVER := Color(1, 1, 1, 0.35)
const BLOCK_TOP := Color("c8a064")
const BLOCK_LEFT := Color("9c7444")
const BLOCK_RIGHT := Color("7a5634")
const OUTLINE := Color("2b1d10")


func _ready() -> void:
	# Center the map horizontally, small margin at the top.
	position = Vector2(get_viewport_rect().size.x / 2.0, 30)


# --- coordinate conversion -------------------------------------------------

func grid_to_screen(cell: Vector2i) -> Vector2:
	# Returns the TOP corner of the cell's diamond.
	return Vector2((cell.x - cell.y) * TILE_W / 2.0, (cell.x + cell.y) * TILE_H / 2.0)


func screen_to_grid(p: Vector2) -> Vector2i:
	var a := p.x / (TILE_W / 2.0)
	var b := p.y / (TILE_H / 2.0)
	return Vector2i(floori((a + b) / 2.0), floori((b - a) / 2.0))


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_SIZE and cell.y < GRID_SIZE


func diamond(cell: Vector2i, lift: float = 0.0) -> PackedVector2Array:
	var t := grid_to_screen(cell) - Vector2(0, lift)
	return PackedVector2Array([
		t,                                       # top
		t + Vector2(TILE_W / 2.0, TILE_H / 2.0), # right
		t + Vector2(0, TILE_H),                  # bottom
		t + Vector2(-TILE_W / 2.0, TILE_H / 2.0) # left
	])


# --- input -----------------------------------------------------------------

func _process(_delta: float) -> void:
	var cell := screen_to_grid(get_local_mouse_position())
	if cell != hover:
		hover = cell
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and in_bounds(hover):
		if mb.button_index == MOUSE_BUTTON_LEFT:
			buildings[hover] = true
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			buildings.erase(hover)
		queue_redraw()


# --- drawing ---------------------------------------------------------------

func _draw() -> void:
	# 1) Ground
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var cell := Vector2i(x, y)
			var d := diamond(cell)
			draw_colored_polygon(d, GRASS_A if (x + y) % 2 == 0 else GRASS_B)
			_outline(d, GRID_LINE)

	# 2) Hover highlight
	if in_bounds(hover) and not buildings.has(hover):
		draw_colored_polygon(diamond(hover), HOVER)

	# 3) Buildings, back to front (smaller x+y is further away)
	var cells := buildings.keys()
	cells.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
	for cell in cells:
		_draw_block(cell, cell == hover)


func _draw_block(cell: Vector2i, highlighted: bool) -> void:
	var g := diamond(cell)               # ground footprint
	var t := diamond(cell, BLOCK_H)      # raised top face
	# g/t indices: 0 top, 1 right, 2 bottom, 3 left
	var left_face := PackedVector2Array([t[3], t[2], g[2], g[3]])
	var right_face := PackedVector2Array([t[2], t[1], g[1], g[2]])

	draw_colored_polygon(left_face, BLOCK_LEFT)
	draw_colored_polygon(right_face, BLOCK_RIGHT)
	draw_colored_polygon(t, BLOCK_TOP.lightened(0.25) if highlighted else BLOCK_TOP)
	_outline(left_face, OUTLINE)
	_outline(right_face, OUTLINE)
	_outline(t, OUTLINE)


func _outline(pts: PackedVector2Array, color: Color) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, color, 1.0)
