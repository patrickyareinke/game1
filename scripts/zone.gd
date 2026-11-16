extends Node2D
## Lasting ground effect from an upgraded spell. Only affects enemies,
## never the player.
##   lava  - burns enemies standing in it (damage every 0.5 s)
##   mud   - sticky puddle, slows enemies
##   quake - earthquake area, slows enemies

const TICK := 0.5

var world: Node2D
var kind := "lava"
var radius := 14.0         # horizontal radius; the area is an iso ellipse
var duration := 6.0
var dps := 1.0
var t := 0.0
var tick := 0.0


func _physics_process(delta: float) -> void:
	t += delta
	if t >= duration:
		queue_free()
		return
	tick -= delta
	var do_tick := tick <= 0.0
	if do_tick:
		tick = TICK
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: Vector2 = e.position - position
		if Vector2(d.x, d.y * 2.0).length() > radius + e.hit_radius:
			continue
		match kind:
			"lava":
				if do_tick:
					e.take_damage(dps * TICK, position, 0.0)
			_:
				e.slow(0.3)
	queue_redraw()


func _draw() -> void:
	var fade := clampf((duration - t) / 0.5, 0.0, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	match kind:
		"lava":
			var pulse := 0.5 + 0.5 * sin(t * 6.0)
			draw_circle(Vector2.ZERO, radius, Color(0.45, 0.08, 0.04, 0.9 * fade))
			draw_circle(Vector2.ZERO, radius * 0.78, Color(0.95, 0.3 + 0.15 * pulse, 0.05, 0.9 * fade))
			draw_circle(Vector2(-radius * 0.25, -radius * 0.2), radius * 0.3, Color(1, 0.85, 0.3, 0.8 * fade))
			draw_circle(Vector2(radius * 0.35, radius * 0.25), radius * 0.15, Color(1, 0.9, 0.5, pulse * fade))
		"mud":
			draw_circle(Vector2.ZERO, radius, Color(0.28, 0.18, 0.09, 0.8 * fade))
			draw_circle(Vector2(-radius * 0.3, -radius * 0.25), radius * 0.4, Color(0.45, 0.32, 0.18, 0.7 * fade))
			draw_circle(Vector2(radius * 0.35, radius * 0.2), radius * 0.2, Color(0.45, 0.32, 0.18, 0.6 * fade))
		"quake":
			for i in 3:
				var k := fmod(t * 1.5 + i / 3.0, 1.0)
				draw_arc(Vector2.ZERO, radius * k, 0.0, TAU, 32,
					Color(0.75, 0.62, 0.42, (1.0 - k) * fade), 2.0)
			# cracks
			for i in 5:
				var a := TAU * i / 5.0 + 0.4
				draw_line(Vector2.from_angle(a) * radius * 0.2, Vector2.from_angle(a) * radius * 0.7,
					Color(0.3, 0.2, 0.1, 0.7 * fade), 1.5)
