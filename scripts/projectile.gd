extends Node2D
## Fireball / mudball. The node sits on the ground (for y-sorting and
## collision), the sprite floats HEIGHT pixels above it.
## Upgrades: fireball "big" / "lava", mudball "puddle" / "bounce" / "quicksand".
## ("triple" fireball is three normal projectiles, spawned by the player.)

const SPEED := 170.0
const RANGE := 150.0
const HEIGHT := 12.0
const HIT_RANGE := 10.0
const MAX_BOUNCES := 2

var world: Node2D
var kind := "fireball"
var upgrade := ""
var velocity := Vector2.ZERO
var damage := 1.0
var travelled := 0.0
var size := 1.0
var bounces := 0
var already_hit: Array = []


func setup(w: Node2D, spell: String, from: Vector2, to: Vector2, dmg: float, up := "") -> void:
	world = w
	kind = spell
	upgrade = up
	damage = dmg
	position = from
	size = 1.8 if upgrade == "big" else 1.0
	velocity = (to - from).normalized() * SPEED
	if velocity == Vector2.ZERO:
		velocity = Vector2.RIGHT * SPEED


func _ready() -> void:
	var s := Sprite2D.new()
	s.texture = load("res://assets/sprites/%s_proj.png" % kind)
	s.offset = Vector2(0, -HEIGHT / size)
	s.scale = Vector2(size, size)
	if upgrade == "lava":
		s.modulate = Color(1.0, 0.55, 0.35)
	add_child(s)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 3.0 * size, Color(0, 0, 0, 0.25))


func _physics_process(delta: float) -> void:
	var step := velocity * delta
	position += step
	travelled += step.length()

	for e in get_tree().get_nodes_in_group("enemies"):
		if e in already_hit or e.dead:
			continue
		if e.position.distance_to(position) < HIT_RANGE * size + e.hit_radius:
			_hit_enemy(e)
			return

	var cell: Vector2i = world.screen_to_grid(position)
	if not world.in_bounds(cell) or travelled > RANGE or world.terrain_at(cell) == world.T.ROCK:
		_end()
		return
	if world.props.has(cell):
		if kind == "fireball" and world.props[cell]["type"] == "bush":
			world.burn_bush(cell)
		_end()


func _hit_enemy(e: Node2D) -> void:
	e.take_damage(damage, position - velocity, 130.0 * size, kind)
	if kind == "mudball":
		e.slow(3.0)
		if upgrade == "quicksand":
			e.root(2.0)
		if upgrade == "bounce" and bounces < MAX_BOUNCES:
			already_hit.append(e)
			var next := _nearest_enemy(90.0)
			if next:
				bounces += 1
				travelled = 0.0
				velocity = (next.position - position).normalized() * SPEED
				world.ring_fx(position, 8.0, Color(0.55, 0.4, 0.25))
				return
	_end()


func _nearest_enemy(max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for e in get_tree().get_nodes_in_group("enemies"):
		if e in already_hit or e.dead:
			continue
		var d: float = e.position.distance_to(position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _end() -> void:
	var color := Color(1, 0.6, 0.2) if kind == "fireball" else Color(0.55, 0.4, 0.25)
	world.ring_fx(position, 10.0 * size, color)
	if world.in_bounds(world.screen_to_grid(position)):
		if upgrade == "lava":
			world.spawn_zone("lava", position, 16.0, 6.0, damage * 0.6)
		elif upgrade == "puddle":
			world.spawn_zone("mud", position, 22.0, 5.0, 0.0)
	queue_free()
