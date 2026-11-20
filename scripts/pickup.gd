extends Node2D
## Something on the ground you pick up with F.
##   stash   - hidden ingredients: only a very faint ring shaped like the tile
##   remains - what a killed slime leaves: a goo splat with its ingredient
## Both sit exactly on their tile. Collecting removes them.

const NEAR := 26.0           # player distance for "you can pick this up"

var world: Node2D
var kind := "stash"          # "stash" or "remains"
var item := "oil"
var count := 1
var coins := 0
var t := 0.0
var near := false
var sprite: Sprite2D


func _ready() -> void:
	t = randf() * 3.0
	if kind == "remains":
		sprite = Sprite2D.new()
		sprite.texture = load("res://assets/sprites/remains_%s.png" % item)
		sprite.offset = Vector2(0, 0)   # 34x20 splat centred on the tile centre
		add_child(sprite)


func _process(delta: float) -> void:
	if world.player == null:
		return
	var d: float = world.player.position.distance_to(position)
	if d > 260.0 and not near:
		return                   # far away: nothing to animate
	t += delta
	near = d < NEAR
	queue_redraw()


func _draw() -> void:
	if kind == "stash":
		# very faint pulsing ring, the shape of the tile (iso diamond, inset)
		var a := 0.10 + 0.06 * sin(t * 2.0)
		if near:
			a = 0.45 + 0.15 * sin(t * 6.0)
		var pts := PackedVector2Array([Vector2(0, -6), Vector2(12, 0), Vector2(0, 6), Vector2(-12, 0), Vector2(0, -6)])
		draw_polyline(pts, Color(1, 0.95, 0.7, a), 1.0)
	if near:
		# small "F" key hint above it
		var p := Vector2(-4, -18 if kind == "remains" else -14)
		draw_rect(Rect2(p, Vector2(8, 8)), Color(0.1, 0.1, 0.2, 0.85))
		draw_rect(Rect2(p, Vector2(8, 8)), Color(1, 0.95, 0.7), false, 1.0)
		draw_string(ThemeDB.fallback_font, p + Vector2(1.5, 6.5), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
			Color(1, 0.95, 0.7))


func collect() -> void:
	Game.add_item(item, count)
	var text := "+%d %s" % [count, Game.ITEMS[item]["name"]]
	if coins > 0:
		Game.add_money(coins)
		text += "  +%d coins" % coins
	world.popup(position + Vector2(0, -22), text, Color(1, 0.9, 0.4))
	world.ring_fx(position, 12.0, Color(1, 0.9, 0.4), 0.4)
	world.pickups.erase(self)
	queue_free()
