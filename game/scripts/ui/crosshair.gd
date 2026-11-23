class_name Crosshair
extends Control

var color: Color = Color(0.78, 0.96, 1.0, 0.9)
var radius: float = 9.0
var active: bool = false
var accent: Color = Color(0.35, 0.95, 1.0, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_active(value: bool) -> void:
	if active != value:
		active = value
		queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var col: Color = accent if active else color
	draw_circle(c, 2.0, col)
	for i in range(4):
		var dir: Vector2 = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN][i] as Vector2
		var a: Vector2 = c + dir * (radius - 3.0)
		var b: Vector2 = c + dir * radius
		draw_line(a, b, col, 1.5)
	if active:
		draw_arc(c, radius + 4.0, 0.0, TAU, 24, Color(accent.r, accent.g, accent.b, 0.45), 1.0)
