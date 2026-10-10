extends Area2D
class_name PowerNode

var node_id: int = 0
var node_title := "电力节点"
var activated := false

func setup(id: int, title: String) -> void:
    node_id = id
    node_title = title
    name = "PowerNode_%d" % id
    queue_redraw()

func set_active(value: bool) -> void:
    activated = value
    queue_redraw()

func _draw() -> void:
    var core_color := Color("#61dafb") if not activated else Color("#8be28b")
    var ring_color := Color(0.38, 0.85, 1.0, 0.24) if not activated else Color(0.55, 1.0, 0.55, 0.28)
    draw_circle(Vector2.ZERO, 34.0, Color(0.02, 0.07, 0.12, 0.9))
    draw_circle(Vector2.ZERO, 27.0, ring_color)
    draw_circle(Vector2.ZERO, 14.0, core_color)
    draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 36, core_color, 3.0)
    var state_text := "已激活" if activated else "按 E 激活"
    draw_string(ThemeDB.fallback_font, Vector2(-58.0, 54.0), node_title, HORIZONTAL_ALIGNMENT_CENTER, 116.0, 14, Color("#d5e7f7"))
    draw_string(ThemeDB.fallback_font, Vector2(-58.0, 72.0), state_text, HORIZONTAL_ALIGNMENT_CENTER, 116.0, 12, core_color)
