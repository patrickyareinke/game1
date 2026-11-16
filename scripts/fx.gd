extends Node2D
## Short-lived expanding ring on the ground (impacts, fiststamp shockwave).

var radius := 10.0
var color := Color.WHITE
var duration := 0.3
var t := 0.0


func _process(delta: float) -> void:
	t += delta
	if t >= duration:
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	var k := t / duration
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, radius * (0.3 + 0.7 * k), 0.0, TAU, 32,
		Color(color, 1.0 - k), 2.0)
