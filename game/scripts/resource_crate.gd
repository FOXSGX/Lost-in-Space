extends Area2D
class_name ResourceCrate

var crate_id: int = 0
var taken := false

func setup(id: int) -> void:
    crate_id = id
    name = "ResourceCrate_%d" % id
    queue_redraw()

func set_taken(value: bool) -> void:
    taken = value
    queue_redraw()

func _process(_delta: float) -> void:
    z_index = int(position.y)

func _draw() -> void:
    draw_set_transform(Vector2(0, 12), 0.0, Vector2(1.25, 0.38))
    draw_circle(Vector2.ZERO, 16.0, Color(0.0, 0.02, 0.04, 0.5))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    if taken:
        draw_rect(Rect2(-12, -12, 24, 24), Color(0.16, 0.30, 0.29, 0.35), true)
        draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 20, Color(0.45, 0.62, 0.60, 0.45), 2.0)
        draw_string(ThemeDB.fallback_font, Vector2(-40.0, 40.0), "已取走", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 11, Color(0.55, 0.70, 0.68, 0.6))
        return
    draw_rect(Rect2(-12, -12, 24, 24), Color("#2b7c73"), true)
    draw_line(Vector2(-9, -9), Vector2(9, 9), Color("#8fe5cb"), 2.0)
    draw_line(Vector2(9, -9), Vector2(-9, 9), Color("#8fe5cb"), 2.0)
    draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 20, Color(0.56, 0.90, 0.80, 0.5), 2.0)
    draw_string(ThemeDB.fallback_font, Vector2(-40.0, 40.0), "F 拾取热能电池", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 11, Color("#8fe5cb"))
