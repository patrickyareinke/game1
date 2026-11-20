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
	if kind == "drop":                # logs / stone lying on the ground
		sprite = Sprite2D.new()
		sprite.texture = Game.icons[item]
		sprite.offset = Vector2(0, -3)
		sprite.scale = Vector2(0.75, 0.75)
		add_child(sprite)
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
		var p := Vector2(-4, -16 if kind == "stash" else -20)
		draw_rect(Rect2(p, Vector2(9, 11)), Color(0.07, 0.1, 0.35, 0.9))
		draw_rect(Rect2(p, Vector2(9, 11)), Color(0.92, 0.92, 0.96), false, 1.0)
		draw_string(preload("res://assets/fonts/pixel.fnt"), p + Vector2(2, 9), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(1, 1, 1))


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
