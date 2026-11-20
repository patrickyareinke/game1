extends Node2D
## Main character: WASD movement (Shift = run), animations, stick swing,
## spell casting, HP. Stats live in the Game autoload.
## Sprite sheet: assets/sprites/player_sheet.png (made by
## tools/import_player_sheet.py), 10 x 6 frames of 34x34, feet bottom centre.
##   rows: idle, walk, run, attack, hurt, sleep
##   cols: 0-3 facing down, 4-6 facing right (mirrored for left), 7-9 facing up

enum Dir { DOWN, UP, LEFT, RIGHT }

const SPEED := 70.0                  # pixels per second at fitness 1
const RUN_MULT := 1.6                # holding Shift
enum Anim { IDLE, WALK, RUN, ATTACK, HURT, SLEEP }
const DIR_COLS := {0: [0, 1, 2, 3], 1: [7, 8, 9], 2: [4, 5, 6], 3: [4, 5, 6]}   # Dir -> columns
const HURT_TIME := 0.4
const FAINT_TIME := 2.6
const WALK_FPS := 8.0
const HAND := Vector2(0, -14)        # stick pivot, relative to the feet
# Swing feel per tool: total time, arc, wind-up share, reach, impact shake
const SWINGS := {
	"stick": {"time": 0.28, "arc": 150.0, "wind": 0.26, "reach": 16.0, "shake": 1.0},
	"axe": {"time": 0.44, "arc": 175.0, "wind": 0.36, "reach": 17.0, "shake": 2.6},
	"pickaxe": {"time": 0.40, "arc": 165.0, "wind": 0.34, "reach": 16.0, "shake": 2.0},
}
const WIND_BACK := deg_to_rad(35.0)  # how far the tool is raised before striking
const STRIKE_END := 0.72             # share of the swing where the strike ends
const REACH := 16.0
const INVULN_TIME := 1.0
const BODY_LENGTH := 32.0             # sprite height in world pixels
const ZOOM := 2.0                    # character shown at double size
const CAVE_ZOOM := 1.2               # a bit wider in the boss cave

var world: Node2D
var dir := Dir.DOWN
var walk_time := 0.0
var swing_t := -1.0                  # < 0 means not swinging
var swing_angle := 0.0
var swing := {}                      # current tool's SWINGS entry
var swing_sign := 1.0                # sweep direction
var swing_hit_done := false
var smear_from := 0.0                # arc of the motion smear (angles)
var smear_to := 0.0
var smear_alpha := 0.0
var smear: Node2D
var shake := 0.0                     # camera shake strength (pixels)
var cam_base := Vector2.ZERO         # camera offset without shake
var knock := Vector2.ZERO
var invuln := 0.0
var cooldowns := {}                  # spell id -> seconds left
var last_cell := Vector2i(-1, -1)
var spawn_point := Vector2.ZERO
var running := false
var anim_t := 0.0
var hurt_t := 0.0
var faint_t := -1.0                  # >= 0 while lying on the ground

var sprite: Sprite2D
var stick: Sprite2D
var blush: Sprite2D               # rosy cheeks + smile (front idle frame only)
var cam: Camera2D


func _ready() -> void:
	spawn_point = position
	last_cell = world.screen_to_grid(position)

	sprite = Sprite2D.new()
	sprite.texture = preload("res://assets/sprites/player_sheet.png")
	sprite.hframes = 10
	sprite.vframes = 6
	sprite.centered = false
	sprite.scale = Vector2(0.5, 0.5)   # 2x detail texture
	sprite.offset = Vector2(-34, -66)  # feet at this node's position (texture px)
	add_child(sprite)

	blush = Sprite2D.new()
	blush.texture = preload("res://assets/sprites/player_blush.png")
	blush.centered = false
	blush.offset = sprite.offset
	blush.scale = sprite.scale
	blush.visible = false
	add_child(blush)

	stick = Sprite2D.new()
	stick.texture = preload("res://assets/sprites/stick.png")
	stick.centered = false
	stick.offset = Vector2(-1, -2)   # rotate around the handle end
	stick.position = HAND
	stick.visible = false
	add_child(stick)

	smear = Node2D.new()
	smear.position = HAND
	smear.draw.connect(_draw_smear)
	add_child(smear)

	cam = Camera2D.new()
	cam.zoom = Vector2(ZOOM, ZOOM)
	# small dead zone: you can move a few pixels before the camera follows,
	# then it catches up smoothly
	cam.drag_horizontal_enabled = true
	cam.drag_vertical_enabled = true
	cam.drag_left_margin = 0.06
	cam.drag_right_margin = 0.06
	cam.drag_top_margin = 0.08
	cam.drag_bottom_margin = 0.08
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	cam.ignore_rotation = false          # the boss intro tilts the camera
	add_child(cam)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.3))


func _physics_process(delta: float) -> void:
	anim_t += delta
	if faint_t >= 0.0:
		_update_faint(delta)
		return
	if Game.cutscene:
		_set_frame(Anim.IDLE, 0.0)
		cam_base = cam.offset            # cutscenes drive the camera directly
		return
	var input := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var moving := input != Vector2.ZERO

	var step := Vector2.ZERO
	if moving:
		var speed: float = SPEED * (1.0 + (Game.stats["fitness"] - 1.0) * 0.05)
		running = Input.is_physical_key_pressed(KEY_SHIFT)
		if running:
			speed *= RUN_MULT
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

	hurt_t = maxf(hurt_t - delta, 0.0)
	if swing_t >= 0.0:
		_set_frame(Anim.ATTACK, clampf(swing_t / swing["time"], 0.0, 0.999), true)
	elif hurt_t > 0.0:
		_set_frame(Anim.HURT, 1.0 - hurt_t / HURT_TIME, true)
	elif moving:
		_set_frame(Anim.RUN if running else Anim.WALK, walk_time * (11.0 if running else WALK_FPS))
	else:
		_set_frame(Anim.IDLE, anim_t * 3.0)
	_update_swing(delta)

	# in the boss cave the camera leans towards the boss so both are on screen
	# character sits one body length below the screen centre
	var cam_target := Vector2(0, -BODY_LENGTH)
	if world.in_cave and world.boss and not world.boss.dead:
		cam_target = ((world.boss.position + Vector2(0, -40)) - position) * 0.5
		cam_target = cam_target.limit_length(110.0)
		cam_target.y = maxf(cam_target.y, -BODY_LENGTH * 2.5)   # never down into the HUD
	cam_base = cam_base.lerp(cam_target, minf(1.0, delta * 5.0))
	shake = move_toward(shake, 0.0, delta * 18.0)
	cam.offset = cam_base + Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	var z := CAVE_ZOOM if world.in_cave else ZOOM
	cam.zoom = cam.zoom.lerp(Vector2(z, z), minf(1.0, delta * 4.0))
	cam.rotation = lerpf(cam.rotation, 0.0, minf(1.0, delta * 4.0))

	for id in cooldowns:
		cooldowns[id] = maxf(cooldowns[id] - delta, 0.0)
	if invuln > 0.0:
		invuln -= delta
		sprite.visible = int(invuln * 15.0) % 2 == 0 or invuln <= 0.0 or hurt_t > 0.0


func _unhandled_input(event: InputEvent) -> void:
	if Game.cutscene:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F:
		_interact()
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
	swing = SWINGS.get(Game.equipped, SWINGS["stick"])
	# sweep downward in front of the body: clockwise when aiming right
	swing_sign = 1.0 if cos(swing_angle) >= 0.0 else -1.0
	swing_t = 0.0
	swing_hit_done = false
	smear_alpha = 0.0
	var tool: Dictionary = Game.TOOLS[Game.equipped]
	stick.texture = load(tool["held"])
	stick.offset = tool["pivot"]
	stick.visible = true
	stick.modulate.a = 1.0
	var side := 3.0 * swing_sign if dir == Dir.LEFT or dir == Dir.RIGHT else 0.0
	stick.position = HAND + Vector2(side, 1.0 if side != 0.0 else 0.0)
	smear.position = stick.position
	# tool goes behind the body when swinging away from the camera
	move_child(stick, 0 if dir == Dir.UP else sprite.get_index() + 1)
	move_child(smear, stick.get_index() + 1)
	_update_swing(0.0)


func _swing_angle(k: float) -> float:
	## Wind-up (raise the tool back), fast strike, overshoot and settle.
	var arc := deg_to_rad(swing["arc"])
	var start := swing_angle - swing_sign * arc / 2.0
	var back := start - swing_sign * WIND_BACK
	var stop := swing_angle + swing_sign * arc / 2.0
	var wind: float = swing["wind"]
	if k < wind:
		var u := k / wind
		return lerpf(start, back, 1.0 - pow(1.0 - u, 2.0))         # ease out: lift
	if k < STRIKE_END:
		var u := (k - wind) / (STRIKE_END - wind)
		return lerpf(back, stop + swing_sign * 0.15, u * u * (3.0 - 2.0 * u) * 0.35 + u * u * 0.65)
	var u := (k - STRIKE_END) / (1.0 - STRIKE_END)
	return lerpf(stop + swing_sign * 0.15, stop, 1.0 - pow(1.0 - u, 3.0))   # settle


func _update_swing(delta: float) -> void:
	if swing_t < 0.0:
		return
	swing_t += delta
	var k: float = swing_t / swing["time"]
	if k >= 1.0:
		swing_t = -1.0
		stick.visible = false
		smear_alpha = 0.0
		smear.queue_redraw()
		return
	var a := _swing_angle(k)
	stick.rotation = a
	# motion smear trails the tool during the strike, then fades
	var wind: float = swing["wind"]
	if k >= wind and k < STRIKE_END:
		smear_from = _swing_angle(maxf(wind, k - 0.16))
		smear_to = a
		smear_alpha = 0.55
	else:
		smear_alpha = maxf(0.0, smear_alpha - delta * 6.0)
	smear.queue_redraw()
	if k > 0.85:
		stick.modulate.a = 1.0 - (k - 0.85) / 0.15
	# the hit lands when the tool passes the aim direction
	var strike_mid := wind + (STRIKE_END - wind) * 0.55
	if not swing_hit_done and k >= strike_mid:
		swing_hit_done = true
		world.hit_at(position + Vector2.from_angle(swing_angle) * swing["reach"], Game.equipped)
		if world.last_hit:
			shake = swing["shake"]


func _draw_smear() -> void:
	if smear_alpha <= 0.0:
		return
	var a0 := minf(smear_from, smear_to)
	var a1 := maxf(smear_from, smear_to)
	if a1 - a0 < 0.05:
		return
	var r := 13.0
	smear.draw_arc(Vector2.ZERO, r, a0, a1, 14, Color(1, 1, 0.92, smear_alpha), 3.0)
	smear.draw_arc(Vector2.ZERO, r - 3.0, a0 + (a1 - a0) * 0.3, a1, 10, Color(1, 1, 1, smear_alpha * 0.5), 1.5)


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

func _interact() -> void:
	## F: pick up stash / remains if one is close, otherwise scoop water.
	if not world.try_collect(position):
		_gather_water()


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
	if invuln > 0.0 or faint_t >= 0.0:
		return
	invuln = INVULN_TIME
	hurt_t = HURT_TIME
	knock = (position - from).normalized() * 160.0
	Game.set_hp(Game.hp - amount)
	world.popup(position + Vector2(0, -40), "-%d" % amount, Color(1, 0.3, 0.3))
	if Game.hp <= 0:
		world.popup(position + Vector2(0, -50), "You fainted!", Color(1, 0.3, 0.3))
		faint_t = 0.0
		swing_t = -1.0
		stick.visible = false
		sprite.visible = true
		Game.set_cutscene(true)          # everything waits while you go down


func _update_faint(delta: float) -> void:
	## Sleep row: sway, sink to the ground, lie there; then wake at the village.
	faint_t += delta
	_set_frame(Anim.SLEEP, minf(faint_t / (FAINT_TIME * 0.6), 0.999) * 8.0, false, true)
	if faint_t >= FAINT_TIME:
		faint_t = -1.0
		invuln = INVULN_TIME
		Game.set_hp(Game.MAX_HP)
		world.respawn_player()
		Game.set_cutscene(false)


func _set_frame(anim: int, t: float, once := false, raw := false) -> void:
	## t: frame counter (looping), or progress 0..1 when once is true.
	## raw: t is a direct column index (sleep row ignores direction).
	if raw:
		sprite.flip_h = false
		sprite.frame = anim * 10 + clampi(int(t), 0, 7)
		return
	var cols: Array = DIR_COLS[dir]
	var i := int(t * cols.size()) if once else int(t) % cols.size()
	sprite.flip_h = dir == Dir.LEFT
	sprite.frame = anim * 10 + cols[clampi(i, 0, cols.size() - 1)]
	blush.self_modulate.a = 1.0 if sprite.frame == 0 else 0.0   # drawn for this frame


func _dir_from(v: Vector2) -> Dir:
	if absf(v.x) > absf(v.y):
		return Dir.LEFT if v.x < 0 else Dir.RIGHT
	return Dir.UP if v.y < 0 else Dir.DOWN
