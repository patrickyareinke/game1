extends Node2D
## Main character: WASD movement, 4-direction walk animation, stick swing.
## Sprite sheet: assets/sprites/player.png, 4x4 frames of 18x26
## (rows: down, up, left, right; columns: walk frames).

enum Dir { DOWN, UP, LEFT, RIGHT }

const SPEED := 70.0                  # pixels per second
const WALK_FPS := 8.0
const HAND := Vector2(0, -12)        # stick pivot, relative to the feet
const SWING_TIME := 0.22
const SWING_ARC := deg_to_rad(150.0)
const REACH := 16.0

var world: Node2D
var dir := Dir.DOWN
var walk_time := 0.0
var swing_t := -1.0                  # < 0 means not swinging
var swing_angle := 0.0

var sprite: Sprite2D
var stick: Sprite2D


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = preload("res://assets/sprites/player.png")
	sprite.hframes = 4
	sprite.vframes = 4
	sprite.centered = false
	sprite.offset = Vector2(-9, -25)  # feet at this node's position
	add_child(sprite)

	stick = Sprite2D.new()
	stick.texture = preload("res://assets/sprites/stick.png")
	stick.centered = false
	stick.offset = Vector2(-1, -2)   # rotate around the handle end
	stick.position = HAND
	stick.visible = false
	add_child(stick)

	var cam := Camera2D.new()
	add_child(cam)


func _draw() -> void:
	# soft round shadow under the feet (drawn below the sprite)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.3))


func _physics_process(delta: float) -> void:
	var input := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var moving := input != Vector2.ZERO

	if moving:
		var step := input.normalized() * SPEED * delta
		if swing_t >= 0.0:
			step *= 0.5
		# move per axis so you slide along obstacles instead of sticking
		if world.is_walkable_at(position + Vector2(step.x, 0)):
			position.x += step.x
		if world.is_walkable_at(position + Vector2(0, step.y)):
			position.y += step.y
		if swing_t < 0.0:
			dir = _dir_from(input)
		walk_time += delta
	else:
		walk_time = 0.0

	var f := int(walk_time * WALK_FPS) % 4 if moving else 0
	sprite.frame = dir * 4 + f
	_update_swing(delta)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT \
			and not world.build_mode and swing_t < 0.0:
		_start_swing()


func _start_swing() -> void:
	var aim := get_global_mouse_position() - (global_position + HAND)
	swing_angle = aim.angle()
	dir = _dir_from(aim)
	swing_t = 0.0
	stick.visible = true
	# stick goes behind the body when swinging away from the camera
	move_child(stick, 0 if dir == Dir.UP else sprite.get_index() + 1)
	_update_swing(0.0)
	world.hit_at(global_position + HAND + Vector2.from_angle(swing_angle) * REACH)


func _update_swing(delta: float) -> void:
	if swing_t < 0.0:
		return
	swing_t += delta
	var k := swing_t / SWING_TIME
	if k >= 1.0:
		swing_t = -1.0
		stick.visible = false
		return
	var eased := 1.0 - pow(1.0 - k, 3.0)
	stick.rotation = swing_angle - SWING_ARC / 2.0 + SWING_ARC * eased


func _dir_from(v: Vector2) -> Dir:
	if absf(v.x) > absf(v.y):
		return Dir.LEFT if v.x < 0 else Dir.RIGHT
	return Dir.UP if v.y < 0 else Dir.DOWN
