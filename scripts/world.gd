extends Node2D
## The world: map data, terrain generation, props, building, collision.
## Rendering of the ground lives in ground.gd, the player in player.gd.

const TILE_W := 32
const TILE_H := 16
const MAP_SIZE := 160
const VILLAGE_CLEAR := 8.0          # radius (cells) kept free of water and props
const PLAZA := 3.5                  # radius of the dirt plaza around the fire
const MOUNTAIN_R := 11              # mountain radius in cells
const CAVE_REGION := 44             # cells x,y < this: sealed rock with the boss arena
const ARENA := Vector2i(22, 22)     # arena centre (inside the sealed region)
const ARENA_R := 9.0
const CAVE_TINT := Color(0.55, 0.5, 0.65)

enum T { GRASS, DIRT, WATER, ROCK, CAVE }

const TEX := {
	"tree": preload("res://assets/sprites/tree.png"),
	"bush": preload("res://assets/sprites/bush.png"),
	"rock": preload("res://assets/sprites/rock.png"),
	"crate": preload("res://assets/sprites/crate.png"),
	"hut": preload("res://assets/sprites/hut.png"),
	"fireplace": preload("res://assets/sprites/fireplace.png"),
	"peak_big": preload("res://assets/sprites/peak_big.png"),
	"peak": preload("res://assets/sprites/peak.png"),
	"boulder": preload("res://assets/sprites/boulder.png"),
	"cave_mouth": preload("res://assets/sprites/cave_mouth.png"),
	"cave_exit": preload("res://assets/sprites/cave_exit.png"),
}
# Sprite offsets so that the image's "foot point" sits on the cell centre.
const FOOT := {
	"tree": Vector2(-17, -42),
	"bush": Vector2(-10, -14),
	"rock": Vector2(-9, -11),
	"crate": Vector2(-17, -25),
	"hut": Vector2(-34, -44),        # hut covers 2x2 cells, see _build_village
	"fireplace": Vector2(-12, -22),
	"peak_big": Vector2(-36, -64),
	"peak": Vector2(-25, -42),
	"boulder": Vector2(-16, -24),
	"cave_mouth": Vector2(-20, -30),
	"cave_exit": Vector2(-20, -30),
}
const HARVEST := {   # prop -> [tool needed, item, min, max]
	"tree": ["axe", "wood", 2, 4],
	"rock": ["pickaxe", "stone", 2, 3],
}
const HITS_TO_HARVEST := 3

var terrain := PackedByteArray()   # T per cell, index = y * MAP_SIZE + x
var variant := PackedByteArray()   # random 0..99 per cell for tile variety
var props := {}                    # Vector2i -> { "type": String, "node": Sprite2D }
var stashes := {}                  # Vector2i -> { "id": String, "count": int } (invisible)
var village := Vector2i.ZERO       # fireplace cell
var fire: Sprite2D
var anim_time := 0.0
var hint_cooldown := 0.0
var mountain := Vector2i.ZERO      # mountain centre
var cave_entrance := Vector2i.ZERO # step here (overworld) -> into the cave
var mountain_exit := Vector2i.ZERO # where you come out again
var arena_arrival := ARENA + Vector2i(8, 8)
var cave_exit := ARENA + Vector2i(11, 11)
var mountain_decor: Array = []    # [Sprite2D, keep_visible_in_cave]
var in_cave := false
var boss: Node2D
var darkness := CanvasModulate.new()

const ENEMY_COUNT := 200
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
const PROJECTILE_SCRIPT := preload("res://scripts/projectile.gd")
const FX_SCRIPT := preload("res://scripts/fx.gd")
const ZONE_SCRIPT := preload("res://scripts/zone.gd")
const HIDDEN_COUNT := 400

var rng := RandomNumberGenerator.new()
var ground: Node2D
var entities: Node2D
var player: Node2D
var ui: CanvasLayer


func _ready() -> void:
	_generate()

	ground = preload("res://scripts/ground.gd").new()
	ground.world = self
	ground.z_index = -10               # ground zones (lava, mud) draw at -5
	add_child(ground)

	entities = Node2D.new()
	entities.y_sort_enabled = true      # things lower on screen draw in front
	add_child(entities)

	for cell in props:
		_spawn_prop_node(cell)
	_build_mountain_decor()
	_hide_ingredients()
	add_child(darkness)

	player = preload("res://scripts/player.gd").new()
	player.world = self
	player.position = cell_center(village + Vector2i(1, 2))
	entities.add_child(player)

	for i in ENEMY_COUNT:
		_spawn_enemy()
	var respawn := Timer.new()
	respawn.wait_time = 2.0
	respawn.autostart = true
	respawn.timeout.connect(func():
		if get_tree().get_nodes_in_group("enemies").size() < ENEMY_COUNT:
			_spawn_enemy())
	add_child(respawn)

	ui = preload("res://scripts/ui.gd").new()
	add_child(ui)


# --- coordinates -----------------------------------------------------------

func grid_to_screen(cell: Vector2i) -> Vector2:
	## Top corner of the cell's diamond.
	return Vector2((cell.x - cell.y) * TILE_W / 2.0, (cell.x + cell.y) * TILE_H / 2.0)


func cell_center(cell: Vector2i) -> Vector2:
	return grid_to_screen(cell) + Vector2(0, TILE_H / 2.0)


func screen_to_grid(p: Vector2) -> Vector2i:
	var a := p.x / (TILE_W / 2.0)
	var b := p.y / (TILE_H / 2.0)
	return Vector2i(floori((a + b) / 2.0), floori((b - a) / 2.0))


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MAP_SIZE and cell.y < MAP_SIZE


func terrain_at(cell: Vector2i) -> int:
	return terrain[cell.y * MAP_SIZE + cell.x]


func variant_at(cell: Vector2i) -> int:
	return variant[cell.y * MAP_SIZE + cell.x]


func is_walkable_cell(cell: Vector2i) -> bool:
	if not in_bounds(cell) or props.has(cell):
		return false
	var t := terrain_at(cell)
	return t != T.WATER and t != T.ROCK


func is_walkable_at(p: Vector2) -> bool:
	return is_walkable_cell(screen_to_grid(p))


# --- generation ------------------------------------------------------------

func _generate() -> void:
	## New random world every game.
	rng.randomize()
	var n_water := FastNoiseLite.new()
	n_water.seed = rng.randi()
	n_water.frequency = 0.07
	var n_path := FastNoiseLite.new()
	n_path.seed = rng.randi()
	n_path.frequency = 0.035
	var n_forest := FastNoiseLite.new()
	n_forest.seed = rng.randi()
	n_forest.frequency = 0.09
	var n_mountain := FastNoiseLite.new()
	n_mountain.seed = rng.randi()
	n_mountain.frequency = 0.15

	terrain.resize(MAP_SIZE * MAP_SIZE)
	variant.resize(MAP_SIZE * MAP_SIZE)
	_pick_landmarks()
	var vc := Vector2(village)
	var mc := Vector2(mountain)

	for y in MAP_SIZE:
		for x in MAP_SIZE:
			var cell := Vector2i(x, y)
			var i := y * MAP_SIZE + x
			variant[i] = rng.randi_range(0, 99)
			# sealed rock region holding the boss arena
			if x < CAVE_REGION and y < CAVE_REGION:
				terrain[i] = T.CAVE if Vector2(cell).distance_to(Vector2(ARENA)) < ARENA_R else T.ROCK
				continue
			# the mountain
			if Vector2(cell).distance_to(mc) + n_mountain.get_noise_2d(x, y) * 3.0 < MOUNTAIN_R:
				terrain[i] = T.ROCK
				continue
			var d_village := Vector2(cell).distance_to(vc)
			var near_village := d_village < VILLAGE_CLEAR
			var t := T.GRASS
			if d_village < PLAZA:
				t = T.DIRT
			elif n_water.get_noise_2d(x, y) < -0.28 and not near_village:
				t = T.WATER
			elif absf(n_path.get_noise_2d(x, y)) < 0.05:
				t = T.DIRT
			terrain[i] = t

			if t != T.GRASS or near_village:
				continue
			var forest := n_forest.get_noise_2d(x, y)
			var r := rng.randf()
			if forest > 0.15 and r < 0.5:
				props[cell] = {"type": "tree"}
			elif r < 0.025:
				props[cell] = {"type": "rock"}
			elif r < 0.07:
				props[cell] = {"type": "bush"}

	_carve_tunnels()
	_build_village()


func _pick_landmarks() -> void:
	## Village and mountain at random places, apart from each other and
	## from the sealed cave region in the top corner.
	var margin := 25
	while true:
		village = Vector2i(rng.randi_range(margin, MAP_SIZE - margin), rng.randi_range(margin, MAP_SIZE - margin))
		if not (village.x < CAVE_REGION + 12 and village.y < CAVE_REGION + 12):
			break
	for attempt in 500:
		var m := Vector2i(rng.randi_range(MOUNTAIN_R + 8, MAP_SIZE - MOUNTAIN_R - 8),
			rng.randi_range(MOUNTAIN_R + 8, MAP_SIZE - MOUNTAIN_R - 8))
		var far_from_village := Vector2(m).distance_to(Vector2(village)) > MOUNTAIN_R + VILLAGE_CLEAR + 12
		var outside_region := not (m.x - MOUNTAIN_R - 4 < CAVE_REGION and m.y - MOUNTAIN_R - 4 < CAVE_REGION)
		if far_from_village and outside_region:
			mountain = m
			break


func _set_terrain(cell: Vector2i, t: int) -> void:
	if in_bounds(cell):
		terrain[cell.y * MAP_SIZE + cell.x] = t
		props.erase(cell)


func _carve_tunnels() -> void:
	## Cave mouth on the mountain's front edge (facing the camera), and the
	## exit tunnel of the boss arena.
	# walk from the mountain centre towards the camera until the rock ends
	var k := 0
	while terrain_at(mountain + Vector2i(k + 1, k + 1)) == T.ROCK:
		k += 1
	cave_entrance = mountain + Vector2i(k, k)
	_set_terrain(cave_entrance, T.CAVE)
	# clear path in front of the mouth
	for j in range(1, 5):
		for off in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var c: Vector2i = cave_entrance + Vector2i(j, j) + off
			if in_bounds(c) and terrain_at(c) != T.ROCK:
				_set_terrain(c, T.DIRT)
	mountain_exit = cave_entrance + Vector2i(2, 2)
	# arena exit tunnel, 2 cells wide
	for j in range(0, 12):
		for off in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			_set_terrain(ARENA + Vector2i(j, j) + off, T.CAVE)


func _build_village() -> void:
	## Fireplace in the middle, 3-5 huts (2x2 cells each) in a ring around it.
	props[village] = {"type": "fireplace"}
	var huts := rng.randi_range(3, 5)
	var start_angle := rng.randf() * TAU
	for i in huts:
		var a := start_angle + TAU * i / huts + rng.randf_range(-0.25, 0.25)
		var dist := rng.randf_range(5.0, 6.5)
		var anchor := village + Vector2i(roundi(cos(a) * dist) - 1, roundi(sin(a) * dist) - 1)
		var cells := [anchor, anchor + Vector2i(1, 0), anchor + Vector2i(0, 1), anchor + Vector2i(1, 1)]
		if cells.any(func(c): return props.has(c)):
			continue
		props[anchor] = {"type": "hut"}
		for c in cells.slice(1):
			props[c] = {"type": "block", "owner": anchor}   # invisible collision


func _process(delta: float) -> void:
	anim_time += delta
	hint_cooldown = maxf(hint_cooldown - delta, 0.0)
	if fire:
		fire.frame = int(anim_time * 8.0) % 3


func _spawn_prop_node(cell: Vector2i) -> void:
	var type: String = props[cell]["type"]
	if type == "block":
		return
	var s := Sprite2D.new()
	s.texture = TEX[type]
	s.centered = false
	s.offset = FOOT[type]
	s.position = cell_center(cell)
	if type == "hut":
		s.position += Vector2(0, TILE_H / 2.0)   # middle of the 2x2 footprint
	elif type == "fireplace":
		s.hframes = 3
		fire = s
	entities.add_child(s)
	props[cell]["node"] = s


func _remove_prop(cell: Vector2i) -> void:
	props[cell]["node"].queue_free()
	props.erase(cell)


# --- mountain & cave -------------------------------------------------------

func _decor(type: String, pos: Vector2, keep_in_cave := false) -> void:
	var s := Sprite2D.new()
	s.texture = TEX[type]
	s.centered = false
	s.offset = FOOT[type]
	s.position = pos
	entities.add_child(s)
	mountain_decor.append([s, keep_in_cave])


func _near_cave_floor(cell: Vector2i, dist: int) -> bool:
	for dy in range(-dist, dist + 1):
		for dx in range(-dist, dist + 1):
			var n := cell + Vector2i(dx, dy)
			if in_bounds(n) and terrain_at(n) == T.CAVE:
				return true
	return false


func _build_mountain_decor() -> void:
	## Peaks and boulders on rock cells so the rock looks like a mountain.
	## Inside the cave only the back wall stays visible.
	var arena_depth := ARENA.x + ARENA.y
	for y in range(0, MAP_SIZE, 2):
		for x in range(0, MAP_SIZE, 2):
			var cell := Vector2i(x + (y / 2) % 2, y)
			if not in_bounds(cell) or terrain_at(cell) != T.ROCK:
				continue
			var pos := cell_center(cell) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-2, 2))
			var in_region := cell.x < CAVE_REGION and cell.y < CAVE_REGION
			if _near_cave_floor(cell, 1):
				# rim around tunnels / arena: small boulders, back wall kept in the cave
				if in_region and cell.x + cell.y < arena_depth:
					_decor("boulder", pos, true)
				continue
			var d := Vector2(cell).distance_to(Vector2(mountain))
			var type := "peak"
			if in_region:
				type = "peak_big" if Vector2(cell).distance_to(Vector2(ARENA)) > ARENA_R + 8 else "peak"
			elif d < MOUNTAIN_R * 0.45:
				type = "peak_big"
			elif d > MOUNTAIN_R * 0.8:
				type = "boulder"
			_decor(type, pos, in_region and cell.x + cell.y < arena_depth - 4)
	_decor("cave_mouth", cell_center(cave_entrance) + Vector2(0, 4))
	_decor("cave_exit", cell_center(cave_exit) + Vector2(0, 4), true)


func on_player_cell(cell: Vector2i) -> void:
	## Called by the player on every new tile.
	check_hidden(cell)
	if cell == cave_entrance and not in_cave:
		enter_cave()
	elif cell == cave_exit and in_cave:
		exit_cave()


func _set_cave_view(on: bool) -> void:
	in_cave = on
	darkness.color = CAVE_TINT if on else Color.WHITE
	for d in mountain_decor:
		d[0].visible = d[1] or not on
	if boss:
		boss.visible = on
	Game.boss["visible"] = on and boss != null and not boss.dead
	Game.changed.emit()


func enter_cave() -> void:
	player.position = cell_center(arena_arrival)
	player.last_cell = arena_arrival
	if boss == null and not Game.boss_defeated:
		boss = preload("res://scripts/boss.gd").new()
		boss.world = self
		boss.position = cell_center(ARENA + Vector2i(-3, -3))
		entities.add_child(boss)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				props[ARENA + Vector2i(-3 + dx, -3 + dy)] = {"type": "block"}
	_set_cave_view(true)
	popup(player.position + Vector2(0, -40), "The Hive", Color(0.85, 0.6, 1.0))


func exit_cave() -> void:
	player.position = cell_center(mountain_exit)
	player.last_cell = mountain_exit
	_set_cave_view(false)


func respawn_player() -> void:
	## Fainted: wake up at the village fire. The boss heals up.
	if in_cave:
		_set_cave_view(false)
	player.position = cell_center(village + Vector2i(1, 2))
	player.last_cell = village + Vector2i(1, 2)
	if boss and not boss.dead:
		boss.reset()


func on_boss_killed() -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			props.erase(ARENA + Vector2i(-3 + dx, -3 + dy))
	Game.boss["visible"] = false
	Game.changed.emit()


func spawn_spit(from: Vector2, to: Vector2) -> void:
	var sp := preload("res://scripts/boss_spit.gd").new()
	sp.setup(self, from, to)
	entities.add_child(sp)


func spawn_warning(pos: Vector2, radius: float, time: float, on_done: Callable) -> void:
	var w := preload("res://scripts/warning.gd").new()
	w.position = pos
	w.radius = radius
	w.duration = time
	w.on_done = on_done
	w.z_index = -4
	add_child(w)


# --- hidden ingredients -----------------------------------------------------

func _hide_ingredients() -> void:
	## Invisible stashes in free cells next to water, trees, rocks or bushes.
	## The neighbour decides what you find.
	var found_near := {"tree": "oil", "rock": "ash", "bush": "ash"}
	var candidates := []
	for y in MAP_SIZE:
		for x in MAP_SIZE:
			var cell := Vector2i(x, y)
			if not is_walkable_cell(cell) or terrain_at(cell) == T.CAVE \
					or Vector2(cell).distance_to(Vector2(village)) < VILLAGE_CLEAR:
				continue
			var item := ""
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := cell + Vector2i(dx, dy)
					if not in_bounds(n):
						continue
					if terrain_at(n) == T.WATER:
						item = "water"
					elif props.has(n) and item == "":
						item = found_near.get(props[n]["type"], "")
			if item != "":
				candidates.append([cell, item])
	candidates.shuffle()
	for c in candidates.slice(0, HIDDEN_COUNT):
		stashes[c[0]] = {"id": c[1], "count": randi_range(1, 2)}


func check_hidden(cell: Vector2i) -> void:
	## Called by the player on every new tile.
	if not stashes.has(cell):
		return
	var h: Dictionary = stashes[cell]
	stashes.erase(cell)
	Game.add_item(h["id"], h["count"])
	var pos := cell_center(cell)
	popup(pos + Vector2(0, -36), "Found %d %s!" % [h["count"], Game.ITEMS[h["id"]]["name"]], Color(1, 0.9, 0.4))
	ring_fx(pos, 14.0, Color(1, 0.9, 0.4), 0.5)


# --- enemies ---------------------------------------------------------------

func _spawn_enemy() -> void:
	## Random free grass/dirt cell, not too close to the player.
	for attempt in 50:
		var cell := Vector2i(rng.randi_range(0, MAP_SIZE - 1), rng.randi_range(0, MAP_SIZE - 1))
		if not is_walkable_cell(cell) or terrain_at(cell) == T.CAVE \
				or Vector2(cell).distance_to(Vector2(village)) < 12.0:
			continue
		var pos := cell_center(cell)
		var from: Vector2 = player.position if player else cell_center(village)
		if pos.distance_to(from) < 150.0:
			continue
		var e := ENEMY_SCRIPT.new()
		e.world = self
		e.kind = ["oil", "ash", "water"][rng.randi_range(0, 2)]
		e.position = pos
		entities.add_child(e)
		return


func on_enemy_killed(enemy: Node2D) -> void:
	var coins := rng.randi_range(1, 3)
	Game.add_money(coins)
	var item: String = enemy.kind
	var count := rng.randi_range(1, 2)
	Game.add_item(item, count)
	var text := "+%d %s  +%d coins" % [count, Game.ITEMS[item]["name"], coins]
	popup(enemy.position + Vector2(0, -30), text, Color(1, 0.85, 0.3))
	ring_fx(enemy.position, 14.0, Color(0.5, 1, 0.4))


# --- combat & effects ------------------------------------------------------

func hit_at(point: Vector2, tool := "stick") -> void:
	## Called by the player's swing (point is on the ground).
	var hit_enemy := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.position.distance_to(point) < 14.0 + e.hit_radius:
			e.take_damage(Game.stick_damage(), player.position)
			Game.add_stat("fighter", Game.FIGHTER_PER_HIT)
			hit_enemy = true
	if hit_enemy:
		return

	var center := screen_to_grid(point)
	var best := Vector2i(-1, -1)
	var best_d := 14.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := center + Vector2i(dx, dy)
			if not props.has(cell) or props[cell]["type"] == "block":
				continue
			var d := cell_center(cell).distance_to(point)
			if d < best_d:
				best_d = d
				best = cell
	if best == Vector2i(-1, -1):
		return
	var type: String = props[best]["type"]
	if type == "bush":
		_remove_prop(best)
	elif HARVEST.has(type):
		_shake(props[best]["node"])
		var h: Array = HARVEST[type]
		if tool != h[0]:
			if hint_cooldown <= 0.0:
				hint_cooldown = 1.5
				popup(cell_center(best) + Vector2(0, -30), "Needs a %s" % Game.ITEMS[h[0]]["name"].to_lower(),
					Color(1, 1, 1, 0.85))
			return
		props[best]["hp"] = props[best].get("hp", HITS_TO_HARVEST) - 1
		if props[best]["hp"] <= 0:
			var count := rng.randi_range(h[2], h[3])
			Game.add_item(h[1], count)
			popup(cell_center(best) + Vector2(0, -30), "+%d %s" % [count, Game.ITEMS[h[1]]["name"]],
				Color(0.9, 0.8, 0.6))
			ring_fx(cell_center(best), 14.0, Color(0.9, 0.8, 0.6))
			_remove_prop(best)


func _shake(node: Node2D) -> void:
	var tw := create_tween()
	var x := node.position.x
	tw.tween_property(node, "position:x", x + 1, 0.04)
	tw.tween_property(node, "position:x", x - 1, 0.04)
	tw.tween_property(node, "position:x", x, 0.04)


func burn_bush(cell: Vector2i) -> void:
	var pos := cell_center(cell)
	_remove_prop(cell)
	Game.add_item("ash", 2)
	popup(pos + Vector2(0, -20), "+2 Ash", Color(0.85, 0.85, 0.85))
	ring_fx(pos, 16.0, Color(1, 0.5, 0.1))


func spawn_projectile(kind: String, from: Vector2, to: Vector2, dmg: float, upgrade := "") -> void:
	var p := PROJECTILE_SCRIPT.new()
	# aim from the hand to the cursor, but travel along the ground
	p.setup(self, kind, from, to + Vector2(0, 12), dmg, upgrade)
	entities.add_child(p)


func spawn_fiststamp(target: Vector2, dmg: float, upgrade := "") -> void:
	match upgrade:
		"slap":
			_drop_fist(target, dmg * 0.6, 70.0, 380.0, 0.18, 0.0, "slap", false)
		"double":
			for i in 2:
				var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(12.0, 50.0)
				off.y *= 0.5
				_drop_fist(target + off, dmg * 0.85, 34.0, 220.0, 0.18, i * 0.15, "fiststamp", false)
		"fast":
			_drop_fist(target, dmg * 1.25, 36.0, 240.0, 0.07, 0.0, "fiststamp", true)
		_:
			_drop_fist(target, dmg, 36.0, 220.0, 0.18, 0.0, "fiststamp", false)


func _drop_fist(target: Vector2, dmg: float, radius: float, knockback: float,
		fall_time: float, delay: float, tex: String, quake: bool) -> void:
	var fist := Sprite2D.new()
	fist.texture = Game.icons[tex]
	fist.scale = Vector2(2.5, 2.5) if tex == "slap" else Vector2(2, 2)
	fist.z_index = 50
	fist.position = target + Vector2(0, -70)
	fist.modulate.a = 0.0
	add_child(fist)
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(fist, "modulate:a", 1.0, 0.08)
	tw.tween_property(fist, "position", target + Vector2(0, -12), fall_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_fist_impact.bind(target, dmg, radius, knockback, quake))
	tw.tween_property(fist, "modulate:a", 0.0, 0.2)
	tw.tween_callback(fist.queue_free)


func _fist_impact(target: Vector2, dmg: float, radius: float, knockback: float, quake: bool) -> void:
	ring_fx(target, radius, Color(0.75, 0.55, 1.0), 0.4)
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: Vector2 = e.position - target
		if Vector2(d.x, d.y * 2.0).length() < radius + e.hit_radius:   # iso ellipse
			e.take_damage(dmg, target, knockback, "fiststamp")
	if quake:
		spawn_zone("quake", target, 48.0, 3.0, 0.0)


func spawn_zone(kind: String, pos: Vector2, radius: float, duration: float, dps: float) -> void:
	var z := ZONE_SCRIPT.new()
	z.world = self
	z.kind = kind
	z.position = pos
	z.radius = radius
	z.duration = duration
	z.dps = dps
	z.z_index = -5
	add_child(z)


func ring_fx(pos: Vector2, radius: float, color: Color, duration := 0.3) -> void:
	var fx := FX_SCRIPT.new()
	fx.position = pos
	fx.radius = radius
	fx.color = color
	fx.duration = duration
	fx.z_index = 40
	add_child(fx)


func popup(pos: Vector2, text: String, color: Color) -> void:
	## Floating text that rises and fades.
	var l := Label.new()
	l.text = text
	l.z_index = 100
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(120, 12)
	l.position = pos - Vector2(60, 6)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 14, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.3)
	tw.tween_callback(l.queue_free)


# --- building --------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_B:
		Game.build_mode = not Game.build_mode
		Game.changed.emit()
		return

	var mb := event as InputEventMouseButton
	if not (Game.build_mode and mb and mb.pressed) or Game.ui_open:
		return
	var cell := screen_to_grid(get_global_mouse_position())
	if mb.button_index == MOUSE_BUTTON_LEFT:
		var player_cell := screen_to_grid(player.position)
		if is_walkable_cell(cell) and cell != player_cell:
			props[cell] = {"type": "crate"}
			_spawn_prop_node(cell)
			Game.add_stat("building", Game.BUILDING_PER_BLOCK)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if props.has(cell) and props[cell]["type"] == "crate":
			_remove_prop(cell)
