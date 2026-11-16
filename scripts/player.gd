extends Node2D
## Main character: WASD movement, 4-direction walk animation, stick swing,
## spell casting, HP. Stats live in the Game autoload.
## Sprite sheet: assets/sprites/player.png, 4x4 frames of 18x26
## (rows: down, up, left, right; columns: walk frames).

enum Dir { DOWN, UP, LEFT, RIGHT }

const SPEED := 70.0                  # pixels per second at fitness 1
const WALK_FPS := 8.0
const HAND := Vector2(0, -12)        # stick pivot, relative to the feet
const SWING_TIME := 0.22
const SWING_ARC := deg_to_rad(150.0)
const REACH := 16.0
const INVULN_TIME := 1.0

var world: Node2D
var dir := Dir.DOWN
var walk_time := 0.0
var swing_t := -1.0                  # < 0 means not swinging
var swing_angle := 0.0
var knock := Vector2.ZERO
var invuln := 0.0
var cooldowns := {}                  # spell id -> seconds left
var last_cell := Vector2i(-1, -1)
var spawn_point := Vector2.ZERO

var sprite: Sprite2D
var stick: Sprite2D
var cam: Camera2D


func _ready() -> void:
	spawn_point = position
	last_cell = world.screen_to_grid(position)

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

	cam = Camera2D.new()
	add_child(cam)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.3))


func _physics_process(delta: float) -> void:
	var input := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var moving := input != Vector2.ZERO

	var step := Vector2.ZERO
	if moving:
		var speed: float = SPEED * (1.0 + (Game.stats["fitness"] - 1.0) * 0.05)
		step = input.normalized() * speed * delta
		if swing_t >= 0.0:
			step *= 0.5
		if swing_t < 0.0:
			dir = _dir_from(input)
		walk_time += delta
	else:
		walk_time = 0.0
	step += knock * delta
	knock = knock.move_toward(Vector2.ZERO, 600.0 * delta)
	# move per axis so you slide along obstacles instead of sticking
	if world.is_walkable_at(position + Vector2(step.x, 0)):
		position.x += step.x
	if world.is_walkable_at(position + Vector2(0, step.y)):
		position.y += step.y

	# fitness: +0.001 for every new tile you walk onto
	var cell: Vector2i = world.screen_to_grid(position)
	if cell != last_cell:
		last_cell = cell
		Game.add_stat("fitness", Game.FITNESS_PER_TILE)
		world.on_player_cell(cell)

	var f := int(walk_time * WALK_FPS) % 4 if moving else 0
	sprite.frame = dir * 4 + f
	_update_swing(delta)

	# in the boss cave the camera leans towards the boss so both are on screen
	var cam_target := Vector2.ZERO
	if world.in_cave and world.boss and not world.boss.dead:
		cam_target = ((world.boss.position + Vector2(0, -40)) - position) * 0.5
		cam_target = cam_target.limit_length(110.0)
	cam.offset = cam.offset.lerp(cam_target, minf(1.0, delta * 5.0))

	for id in cooldowns:
		cooldowns[id] = maxf(cooldowns[id] - delta, 0.0)
	if invuln > 0.0:
		invuln -= delta
		sprite.visible = int(invuln * 15.0) % 2 == 0 or invuln <= 0.0


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F:
		_gather_water()
		return

	var mb := event as InputEventMouseButton
	if not (mb and mb.pressed) or Game.ui_open or Game.build_mode:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		Game.cycle_tool(1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and swing_t < 0.0:
		_start_swing()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_cast(Game.active_spell)


# --- stick -----------------------------------------------------------------

func _start_swing() -> void:
	var aim := get_global_mouse_position() - (global_position + HAND)
	swing_angle = aim.angle()
	dir = _dir_from(aim)
	swing_t = 0.0
	var tool: Dictionary = Game.TOOLS[Game.equipped]
	stick.texture = load(tool["held"])
	stick.offset = tool["pivot"]
	stick.visible = true
	# stick goes behind the body when swinging away from the camera
	move_child(stick, 0 if dir == Dir.UP else sprite.get_index() + 1)
	_update_swing(0.0)
	world.hit_at(position + Vector2.from_angle(swing_angle) * REACH, Game.equipped)


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


# --- spells ----------------------------------------------------------------

func _cast(id: String) -> void:
	if cooldowns.get(id, 0.0) > 0.0:
		return
	if not Game.can_cast(id):
		world.popup(position + Vector2(0, -34), Game.missing_text(id), Color(1, 0.55, 0.55))
		return
	var target := get_global_mouse_position()
	dir = _dir_from(target - position)
	var dmg: float = Game.spell_damage(id)
	var up: String = Game.spell_upgrade[id]
	match id:
		"fireball":
			if up == "triple":
				for a in [-0.26, 0.0, 0.26]:
					world.spawn_projectile(id, position, position + (target - position).rotated(a), dmg * 0.7)
			elif up == "big":
				world.spawn_projectile(id, position, target, dmg * 1.6, up)
			else:
				world.spawn_projectile(id, position, target, dmg, up)
		"mudball":
			world.spawn_projectile(id, position, target, dmg, up)
		"fiststamp":
			world.spawn_fiststamp(target, dmg, up)   # no range limit
	cooldowns[id] = Game.SPELLS[id]["cooldown"]
	Game.cast(id)


# --- misc ------------------------------------------------------------------

func _gather_water() -> void:
	var cell: Vector2i = world.screen_to_grid(position)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := cell + Vector2i(dx, dy)
			if world.in_bounds(c) and world.terrain_at(c) == world.T.WATER:
				Game.add_item("water")
				world.popup(position + Vector2(0, -34), "+1 Water", Color(0.6, 0.85, 1))
				return
	world.popup(position + Vector2(0, -34), "No water nearby", Color(1, 1, 1, 0.8))


func hurt(amount: int, from: Vector2) -> void:
	if invuln > 0.0:
		return
	invuln = INVULN_TIME
	knock = (position - from).normalized() * 160.0
	Game.set_hp(Game.hp - amount)
	world.popup(position + Vector2(0, -34), "-%d" % amount, Color(1, 0.3, 0.3))
	if Game.hp <= 0:
		world.popup(position + Vector2(0, -44), "You fainted!", Color(1, 0.3, 0.3))
		Game.set_hp(Game.MAX_HP)
		world.respawn_player()


func _dir_from(v: Vector2) -> Dir:
	if absf(v.x) > absf(v.y):
		return Dir.LEFT if v.x < 0 else Dir.RIGHT
	return Dir.UP if v.y < 0 else Dir.DOWN
