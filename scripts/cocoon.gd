extends Node2D
## Silk cocoon behind the Hive Mantis with the girl inside. Once the boss is
## beaten, a fireball or a Magic Fiststamp bursts it open (2 hits).

const HITS := 2

var world: Node2D
var kind := "cocoon"
var hit_radius := 8.0
var dead := false
var hits := 0
var hint_t := 0.0
var sprite: Sprite2D
var t := 0.0


func _ready() -> void:
	add_to_group("enemies")          # so spells and fists can hit it
	sprite = Sprite2D.new()
	sprite.texture = preload("res://assets/sprites/cocoon.png")
	sprite.centered = false
	sprite.offset = Vector2(-13, -37)
	add_child(sprite)


func _process(delta: float) -> void:
	t += delta
	hint_t = maxf(hint_t - delta, 0.0)
	sprite.rotation = sin(t * 1.3) * 0.03     # gently swaying
	if Game.boss_defeated and int(t * 2.0) % 6 == 0:
		sprite.modulate = Color(1.15, 1.05, 1.15)   # faint pulse: someone moves inside
	else:
		sprite.modulate = Color.WHITE


func take_damage(_amount: float, _from: Vector2, _knockback := 0.0, source := "") -> void:
	if dead:
		return
	if not Game.boss_defeated:
		_hint("The Hive Mantis guards the cocoon!")
		return
	if source != "fireball" and source != "fiststamp":
		_hint("Too tough - burn it or punch it with magic!")
		return
	hits += 1
	var tw := create_tween()
	for k in [3.0, -3.0, 2.0, 0.0]:
		tw.tween_property(sprite, "position:x", k, 0.04)
	if hits < HITS:
		world.popup(position + Vector2(0, -44), "The silk tears!", Color(1, 0.9, 0.7))
		return
	dead = true
	remove_from_group("enemies")
	world.ring_fx(position + Vector2(0, -16), 26.0, Color(0.95, 0.9, 0.85), 0.5)
	for i in 8:                               # silk shreds flying off
		var shred := Sprite2D.new()
		shred.texture = sprite.texture
		shred.region_enabled = true
		shred.region_rect = Rect2(randi_range(2, 18), randi_range(6, 30), 6, 5)
		shred.position = position + Vector2(randf_range(-8, 8), randf_range(-30, -8))
		shred.z_index = 40
		world.add_child(shred)
		var st := shred.create_tween().set_parallel()
		st.tween_property(shred, "position", shred.position + Vector2.from_angle(randf() * TAU) * 26, 0.6)
		st.tween_property(shred, "rotation", randf_range(-3, 3), 0.6)
		st.tween_property(shred, "modulate:a", 0.0, 0.6)
		st.chain().tween_callback(shred.queue_free)
	world.on_cocoon_freed(self)
	queue_free()


func _hint(text: String) -> void:
	if hint_t <= 0.0:
		hint_t = 1.2
		world.popup(position + Vector2(0, -44), text, Color(1, 1, 1, 0.85))


func slow(_s: float) -> void:
	pass


func root(_s: float) -> void:
	pass
