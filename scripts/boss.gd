extends Node2D
## Hive Mantis - end boss in the cave under the mountain.
##   Phase 1: the claw cage is closed. Only Magic Fiststamp hurts it;
##            CAGE_HITS fist hits burst it open.
##   Phase 2: the heart is exposed. Only fireballs damage it.
##            After OPEN_TIME seconds the claws close again.
## Attacks: acid spit at range, claw slam (red warning circle) up close.
## Spells never hurt the player; only the boss's own attacks do.

const HEART_MAX := 30.0
const CAGE_HITS := 3
const OPEN_TIME := 12.0
const SPIT_EVERY := 2.2
const SLAM_EVERY := 3.5
const SLAM_RANGE := 90.0
const SLAM_RADIUS := 30.0
const AGGRO_RANGE := 320.0
const HEART_OFFSET := Vector2(0, -29)   # heart, relative to the feet

var world: Node2D
var kind := "boss"
var hit_radius := 30.0
var dead := false
var heart := HEART_MAX
var cage_hits := 0
var open_t := 0.0
var spit_t := 2.5
var slam_t := 3.0
var hint_t := 0.0
var t := 0.0

var body: Sprite2D
var cage: Sprite2D
var heart_sprite: Sprite2D
var tex_cage := preload("res://assets/sprites/boss_cage.png")
var tex_open := preload("res://assets/sprites/boss_cage_open.png")


func _ready() -> void:
	add_to_group("enemies")
	body = Sprite2D.new()
	body.texture = preload("res://assets/sprites/boss_body.png")
	body.centered = false
	body.offset = Vector2(-64, -90)
	add_child(body)

	heart_sprite = Sprite2D.new()
	heart_sprite.texture = preload("res://assets/sprites/boss_heart.png")
	heart_sprite.hframes = 2
	heart_sprite.position = HEART_OFFSET
	add_child(heart_sprite)

	cage = Sprite2D.new()
	cage.texture = tex_cage
	cage.position = HEART_OFFSET
	add_child(cage)
	_sync()


func _physics_process(delta: float) -> void:
	if dead:
		return
	t += delta
	hint_t = maxf(hint_t - delta, 0.0)
	var bob := sin(t * 2.0) * 1.5
	body.position.y = bob
	heart_sprite.position = HEART_OFFSET + Vector2(0, bob)
	cage.position = HEART_OFFSET + Vector2(0, bob)
	heart_sprite.frame = int(t * (4.0 if is_open() else 2.0)) % 2

	if is_open():
		open_t -= delta
		if open_t <= 0.0:
			_close_cage()

	var player: Node2D = world.player
	var dist := player.position.distance_to(position)
	if not world.in_cave or dist > AGGRO_RANGE:
		return
	spit_t -= delta
	slam_t -= delta
	if spit_t <= 0.0:
		spit_t = SPIT_EVERY
		world.spawn_spit(position + Vector2(0, 6), player.position)
	if slam_t <= 0.0 and dist < SLAM_RANGE:
		slam_t = SLAM_EVERY
		var target := player.position
		world.spawn_warning(target, SLAM_RADIUS, 0.8, _slam.bind(target))


func _slam(target: Vector2) -> void:
	if dead:
		return
	world.ring_fx(target, SLAM_RADIUS, Color(1, 0.3, 0.2), 0.35)
	var d: Vector2 = world.player.position - target
	if Vector2(d.x, d.y * 2.0).length() < SLAM_RADIUS:
		world.player.hurt(2, target)


func is_open() -> bool:
	return cage_hits >= CAGE_HITS


func take_damage(amount: float, _from: Vector2, _knockback := 0.0, source := "") -> void:
	if dead:
		return
	if not is_open():
		if source == "fiststamp":
			cage_hits += 1
			Game.register_spell_hit(source)
			_shake(cage)
			if is_open():
				_open_cage()
			else:
				world.popup(global_position + Vector2(0, 16), "Crack! %d/%d" % [cage_hits, CAGE_HITS],
					Color(1, 0.9, 0.6))
		else:
			_hint("The claw cage blocks it!")
		_sync()
		return

	if source == "fireball":
		heart -= amount
		Game.register_spell_hit(source)
		world.popup(global_position + HEART_OFFSET + Vector2(0, -12), "%.1f" % amount, Color(1, 0.5, 0.3))
		var tw := create_tween()
		tw.tween_property(heart_sprite, "modulate", Color(3, 3, 3), 0.05)
		tw.tween_property(heart_sprite, "modulate", Color.WHITE, 0.15)
		if heart <= 0.0:
			_die()
	else:
		_hint("Only fire can burn the heart!")
	_sync()


func _open_cage() -> void:
	open_t = OPEN_TIME
	cage.texture = tex_open
	world.ring_fx(global_position + HEART_OFFSET, 40.0, Color(1, 0.95, 0.8), 0.4)
	world.popup(global_position + Vector2(0, 16), "The claw cage bursts open!", Color(1, 0.9, 0.4))


func _close_cage() -> void:
	cage_hits = 0
	cage.texture = tex_cage
	world.popup(global_position + Vector2(0, 16), "The claws close again!", Color(1, 0.6, 0.6))
	_sync()


func _hint(text: String) -> void:
	if hint_t <= 0.0:
		hint_t = 1.2
		world.popup(global_position + Vector2(0, 16), text, Color(1, 1, 1, 0.85))


func _shake(node: Node2D) -> void:
	var tw := create_tween()
	var x := node.position.x
	for k in [3.0, -3.0, 2.0, 0.0]:
		tw.tween_property(node, "position:x", x + k, 0.04)


func _die() -> void:
	dead = true
	remove_from_group("enemies")
	Game.boss_defeated = true
	Game.add_money(100)
	world.ring_fx(global_position + HEART_OFFSET, 70.0, Color(1, 0.4, 0.3), 0.8)
	world.popup(global_position + Vector2(0, -70), "The Hive Mantis is defeated!  +100 coins", Color(1, 0.85, 0.3))
	world.on_boss_killed()
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 0.3, 0.3, 0.0), 1.5)
	tw.tween_callback(queue_free)


func reset() -> void:
	heart = HEART_MAX
	cage_hits = 0
	open_t = 0.0
	cage.texture = tex_cage
	_sync()


func slow(_seconds: float) -> void:
	pass   # too big to be slowed


func root(_seconds: float) -> void:
	pass


func _sync() -> void:
	Game.boss = {
		"visible": world.in_cave and not dead,
		"heart": maxf(heart, 0.0),
		"max": HEART_MAX,
		"cage_hits": cage_hits,
		"cage_needed": CAGE_HITS,
		"open": is_open(),
	}
	Game.changed.emit()
