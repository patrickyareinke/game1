extends Node2D
## The girl from the victory scene. Same sheet layout as the hero
## (assets/sprites/girl_sheet.png: rows idle, walk, run, attack, hurt, sleep;
## cols 0-3 down, 4-6 right (mirrored for left), 7-9 up).

signal arrived

const SPEED := 45.0
const DIR_COLS := {"down": [0, 1, 2, 3], "up": [7, 8, 9], "left": [4, 5, 6], "right": [4, 5, 6]}

var target := Vector2.ZERO
var walking := false
var facing := "down"
var t := 0.0
var sprite: Sprite2D


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = preload("res://assets/sprites/girl_sheet.png")
	sprite.hframes = 10
	sprite.vframes = 6
	sprite.centered = false
	sprite.offset = Vector2(-17, -33)
	add_child(sprite)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.3))


func walk_to(p: Vector2) -> void:
	target = p
	walking = true


func face(dir: String) -> void:
	facing = dir


func _physics_process(delta: float) -> void:
	t += delta
	var row := 0
	if walking:
		var to := target - position
		if to.length() < 1.5:
			position = target
			walking = false
			arrived.emit()
		else:
			position += to.normalized() * minf(SPEED * delta, to.length())
			if absf(to.x) > absf(to.y):
				facing = "left" if to.x < 0 else "right"
			else:
				facing = "up" if to.y < 0 else "down"
			row = 1
	var cols: Array = DIR_COLS[facing]
	var fps := 8.0 if row == 1 else 3.0
	sprite.flip_h = facing == "left"
	sprite.frame = row * 10 + cols[int(t * fps) % cols.size()]
