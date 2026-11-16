extends Node2D
## Fireball / mudball. The node sits on the ground (for y-sorting and
## collision), the sprite floats HEIGHT pixels above it.

const SPEED := 170.0
const RANGE := 150.0
const HEIGHT := 12.0
const HIT_RANGE := 10.0

var world: Node2D
var kind := "fireball"
var velocity := Vector2.ZERO
var damage := 1.0
var travelled := 0.0


func setup(w: Node2D, spell: String, from: Vector2, to: Vector2, dmg: float) -> void:
	world = w
	kind = spell
	damage = dmg
	position = from
	velocity = (to - from).normalized() * SPEED
	if velocity == Vector2.ZERO:
		velocity = Vector2.RIGHT * SPEED


func _ready() -> void:
	var s := Sprite2D.new()
	s.texture = load("res://assets/sprites/%s_proj.png" % kind)
	s.offset = Vector2(0, -HEIGHT)
	add_child(s)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.25))


func _physics_process(delta: float) -> void:
	var step := velocity * delta
	position += step
	travelled += step.length()

	for e in get_tree().get_nodes_in_group("enemies"):
		if e.position.distance_to(position) < HIT_RANGE:
			e.take_damage(damage, position - velocity)
			if kind == "mudball":
				e.slow(3.0)
			_end()
			return

	var cell: Vector2i = world.screen_to_grid(position)
	if not world.in_bounds(cell) or travelled > RANGE:
		_end()
		return
	if world.props.has(cell):
		if kind == "fireball" and world.props[cell]["type"] == "bush":
			world.burn_bush(cell)
		_end()


func _end() -> void:
	var color := Color(1, 0.6, 0.2) if kind == "fireball" else Color(0.55, 0.4, 0.25)
	world.ring_fx(position, 10.0, color)
	queue_free()
