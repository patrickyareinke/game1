extends Node2D
## Slime enemy: wanders, chases the player when close, hurts on contact.

const MAX_HP := 3.0
const SPEED := 30.0
const CHASE_RANGE := 90.0
const TOUCH_RANGE := 9.0

var world: Node2D
var hp := MAX_HP
var slow_t := 0.0
var hurt_t := 0.0
var knock := Vector2.ZERO
var wander_dir := Vector2.ZERO
var wander_t := 0.0
var anim := 0.0
var sprite: Sprite2D


func _ready() -> void:
	add_to_group("enemies")
	anim = randf() * 2.0
	sprite = Sprite2D.new()
	sprite.texture = preload("res://assets/sprites/slime.png")
	sprite.hframes = 2
	sprite.centered = false
	sprite.offset = Vector2(-9, -15)
	add_child(sprite)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.3))


func _physics_process(delta: float) -> void:
	anim += delta
	sprite.frame = int(anim * 4.0) % 2
	slow_t = maxf(slow_t - delta, 0.0)
	hurt_t = maxf(hurt_t - delta, 0.0)

	var player: Node2D = world.player
	var to_player := player.position - position
	var dir := Vector2.ZERO
	if to_player.length() < CHASE_RANGE:
		dir = to_player.normalized()
	else:
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(1.0, 3.0)
			wander_dir = Vector2.from_angle(randf() * TAU) * 0.5 if randf() < 0.7 else Vector2.ZERO
		dir = wander_dir

	var speed := SPEED * (0.35 if slow_t > 0.0 else 1.0)
	var step := dir * speed * delta + knock * delta
	knock = knock.move_toward(Vector2.ZERO, 500.0 * delta)
	if world.is_walkable_at(position + Vector2(step.x, 0)):
		position.x += step.x
	if world.is_walkable_at(position + Vector2(0, step.y)):
		position.y += step.y

	if to_player.length() < TOUCH_RANGE:
		player.hurt(1, position)

	if hurt_t > 0.0:
		sprite.modulate = Color(1, 0.4, 0.4)
	elif slow_t > 0.0:
		sprite.modulate = Color(0.75, 0.6, 0.45)
	else:
		sprite.modulate = Color.WHITE


func take_damage(amount: float, from: Vector2, knockback := 130.0) -> void:
	hp -= amount
	hurt_t = 0.15
	knock = (position - from).normalized() * knockback
	world.popup(position + Vector2(0, -20), "%.1f" % amount, Color(1, 0.9, 0.4))
	if hp <= 0.0:
		world.on_enemy_killed(self)
		queue_free()


func slow(seconds: float) -> void:
	slow_t = seconds
