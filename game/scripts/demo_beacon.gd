extends Area2D

var _pulse := 0.0
var beacon_id: int = 0
var beacon_title := "示范信标"
var activated := false

func setup(id: int, title: String) -> void:
    beacon_id = id
    beacon_title = title
    name = "DemoBeacon_%d" % id
    queue_redraw()

func set_active(value: bool) -> void:
    activated = value
    queue_redraw()

func _process(delta: float) -> void:
    _pulse += delta
    if not activated:
        queue_redraw()

func _draw() -> void:
    var color := Color("#f5c76b") if not activated else Color("#8be28b")
    draw_circle(Vector2.ZERO, 25.0, Color(0.04, 0.08, 0.10, 0.9))
    draw_circle(Vector2.ZERO, 17.0, Color(color, 0.28))
    draw_arc(Vector2.ZERO, 25.0, 0.0, TAU, 32, color, 3.0)
    draw_circle(Vector2.ZERO, 8.0, color)
    if not activated:
        draw_arc(Vector2.ZERO, 31.0 + sin(_pulse * 3.0) * 4.0, 0.0, TAU, 24, Color(color, 0.32), 2.0)
    draw_string(ThemeDB.fallback_font, Vector2(-52, 44), beacon_title, HORIZONTAL_ALIGNMENT_CENTER, 104.0, 13, Color("#e7f2f7"))
    draw_string(ThemeDB.fallback_font, Vector2(-52, 61), "已完成" if activated else "按 E 扫描", HORIZONTAL_ALIGNMENT_CENTER, 104.0, 11, color)
