class_name Act1Crosshair
extends Control

var focused := false
var blocked := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	var c := size * 0.5
	var col := Color(0.75, 0.92, 1.0, 0.92) if not focused else Color(1.0, 0.78, 0.35, 1.0)
	if blocked:
		col = Color(1.0, 0.35, 0.28, 1.0)
	var gap := 5.0
	var arm := 10.0 if focused else 7.0
	draw_line(c + Vector2(-gap - arm, 0), c + Vector2(-gap, 0), col, 1.6)
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + arm, 0), col, 1.6)
	draw_line(c + Vector2(0, -gap - arm), c + Vector2(0, -gap), col, 1.6)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + arm), col, 1.6)
	draw_circle(c, 1.5, col)
	if focused:
		draw_arc(c, 17.0, 0.0, TAU, 32, Color(1.0, 0.76, 0.31, 0.55), 1.4)