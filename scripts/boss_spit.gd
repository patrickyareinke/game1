extends Node2D
## Acid spit from the boss. Hurts the player only.

const SPEED := 110.0
const RANGE := 280.0
const HEIGHT := 14.0

var world: Node2D
var velocity := Vector2.ZERO
var travelled := 0.0
var color := Color(0.6, 0.95, 0.2)
var speed := SPEED


func _ready() -> void:
	add_to_group("enemy_shots")


func setup(w: Node2D, from: Vector2, to: Vector2, col := Color(0.6, 0.95, 0.2), spd := SPEED) -> void:
	world = w
	position = from
	color = col
	speed = spd
	velocity = (to - from).normalized() * speed
	if velocity == Vector2.ZERO:
		velocity = Vector2.DOWN * speed


func _physics_process(delta: float) -> void:
	if Game.cutscene:
		return
	position += velocity * delta
	travelled += speed * delta
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
	draw_circle(Vector2(0, -HEIGHT), 4.0, color.darkened(0.4))
	draw_circle(Vector2(0, -HEIGHT), 3.0, color)
	draw_circle(Vector2(-1, -HEIGHT - 1), 1.2, color.lightened(0.6))


func _end() -> void:
	world.ring_fx(position, 8.0, color)
	queue_free()
