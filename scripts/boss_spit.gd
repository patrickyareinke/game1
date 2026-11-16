extends Node2D
## Acid spit from the boss. Hurts the player only.

const SPEED := 110.0
const RANGE := 280.0
const HEIGHT := 14.0

var world: Node2D
var velocity := Vector2.ZERO
var travelled := 0.0


func setup(w: Node2D, from: Vector2, to: Vector2) -> void:
	world = w
	position = from
	velocity = (to - from).normalized() * SPEED
	if velocity == Vector2.ZERO:
		velocity = Vector2.DOWN * SPEED


func _physics_process(delta: float) -> void:
	position += velocity * delta
	travelled += SPEED * delta
	if world.player.position.distance_to(position) < 8.0:
		world.player.hurt(1, position)
		_end()
		return
	var cell: Vector2i = world.screen_to_grid(position)
	if travelled > RANGE or not world.in_bounds(cell) or world.terrain_at(cell) in [world.T.ROCK, world.T.VOID]:
		_end()
		return
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO)
	draw_circle(Vector2(0, -HEIGHT), 4.0, Color(0.35, 0.6, 0.1))
	draw_circle(Vector2(0, -HEIGHT), 3.0, Color(0.6, 0.95, 0.2))
	draw_circle(Vector2(-1, -HEIGHT - 1), 1.2, Color(0.9, 1, 0.6))


func _end() -> void:
	world.ring_fx(position, 8.0, Color(0.6, 0.95, 0.2))
	queue_free()
