extends Node2D
## Red warning circle on the ground; calls on_done when the time is up.

var radius := 28.0
var duration := 0.8
var on_done: Callable
var t := 0.0


func _process(delta: float) -> void:
	t += delta
	if t >= duration:
		if on_done.is_valid():
			on_done.call()
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := t / duration
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, radius, Color(1, 0.1, 0.1, 0.15 + 0.25 * k))
	draw_arc(Vector2.ZERO, radius * k, 0.0, TAU, 32, Color(1, 0.35, 0.25, 0.9), 2.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(1, 0.2, 0.2, 0.8), 1.0)
