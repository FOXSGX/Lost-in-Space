extends Node2D

var _pulse := 0.0
var safehouse_rect := Rect2(365, 400, 250, 205)
var danger_rect := Rect2(690, 175, 190, 230)
var heat_position := Vector2(490, 500)

func set_layout(next_safehouse: Rect2, next_danger: Rect2, next_heat: Vector2) -> void:
    safehouse_rect = next_safehouse
    danger_rect = next_danger
    heat_position = next_heat
    queue_redraw()

func _process(delta: float) -> void:
    _pulse += delta
    queue_redraw()

func _draw() -> void:
    var map_rect := Rect2(48, 138, 879, 534)
    draw_rect(map_rect, Color("#101f2c"), true)
    for x in range(64, 920, 32):
        draw_line(Vector2(x, 150), Vector2(x, 660), Color(0.30, 0.55, 0.62, 0.08), 1.0)
    for y in range(150, 660, 32):
        draw_line(Vector2(60, y), Vector2(915, y), Color(0.30, 0.55, 0.62, 0.08), 1.0)

    # 安全屋和危险区每次登陆都会重新选点；安全屋始终位于危险区左侧。
    draw_rect(safehouse_rect, Color("#1c3549"), true)
    draw_rect(safehouse_rect, Color("#77b7dd"), false, 2.0)
    draw_rect(danger_rect, Color("#3b2c35"), true)
    draw_rect(danger_rect, Color("#e3a45f"), false, 2.0)

    # 根据本局布局绘制探索路线，资源箱不再绑定到固定资源区。
    var safe_center := safehouse_rect.get_center()
    var danger_center := danger_rect.get_center()
    draw_line(Vector2(76, 360), safe_center, Color("#61c8b5"), 8.0)
    draw_line(Vector2(76, 360), safe_center, Color("#c4fff0"), 2.0)
    draw_line(safe_center, danger_center, Color("#d0b875"), 8.0)
    draw_line(safe_center, danger_center, Color("#fff1b8"), 2.0)
    draw_circle(Vector2(76, 360), 8.0, Color("#eaf8f4"))
    draw_circle((safe_center + danger_center) * 0.5, 8.0, Color("#fff1b8"))

    # 热源：内圈为恒温范围，玩家在此范围内回温。资源箱由 ResourceCrate 节点绘制。
    var heat_radius := 42.0 + sin(_pulse * 2.2) * 4.0
    draw_circle(heat_position, heat_radius, Color(1.0, 0.67, 0.26, 0.08))
    draw_arc(heat_position, heat_radius, 0.0, TAU, 32, Color("#ffcf7a"), 2.0)
    draw_circle(heat_position, 17.0, Color("#ffad4d"))
    draw_circle(heat_position, 9.0, Color("#fff1b8"))

    # 危险区的警戒条和岩柱。
    for x in range(int(danger_rect.position.x + 10.0), int(danger_rect.end.x - 10.0), 32):
        draw_line(Vector2(x, danger_rect.position.y + 10.0), Vector2(x + 22, danger_rect.position.y + 40.0), Color(1.0, 0.72, 0.38, 0.30), 4.0)
    for rock in [
        danger_rect.position + Vector2(42, danger_rect.size.y - 52),
        danger_rect.position + Vector2(danger_rect.size.x * 0.66, 55),
        danger_rect.position + Vector2(danger_rect.size.x - 32, danger_rect.size.y - 55),
    ]:
        draw_circle(rock, 17.0, Color("#543f4b"))
        draw_arc(rock, 17.0, 0.0, TAU, 16, Color("#b87868"), 2.0)

    # 投送与撤离点，资源在此上交。
    var exit_center := Vector2(845, 575)
    draw_circle(exit_center, 38.0, Color(0.35, 0.75, 1.0, 0.08))
    draw_arc(exit_center, 38.0, 0.0, TAU, 32, Color("#77d9ff"), 2.0)
    draw_arc(exit_center, 25.0, -_pulse, TAU - _pulse, 24, Color("#d2f5ff"), 3.0)
    draw_line(exit_center - Vector2(12, 0), exit_center + Vector2(12, 0), Color("#d2f5ff"), 2.0)
    draw_line(exit_center - Vector2(0, 12), exit_center + Vector2(0, 12), Color("#d2f5ff"), 2.0)

    draw_string(ThemeDB.fallback_font, safehouse_rect.position + Vector2(16, 28), "安全屋 / 热源 · 恒温区", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#b9ddff"))
    draw_string(ThemeDB.fallback_font, danger_rect.position + Vector2(16, 28), "危险区", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#ffd38a"))
    draw_string(ThemeDB.fallback_font, Vector2(784, 625), "投送 / 撤离点", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#bdeeff"))
    draw_string(ThemeDB.fallback_font, Vector2(72, 655), "示范星球 · 资源随机分布 → 安全屋 → 危险区 → 投送撤离", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#b7cbd6"))

func get_spawn_position(index: int) -> Vector2:
    var slots := [Vector2(145, 275), Vector2(235, 275), Vector2(325, 275), Vector2(415, 275)]
    return slots[index % slots.size()]
