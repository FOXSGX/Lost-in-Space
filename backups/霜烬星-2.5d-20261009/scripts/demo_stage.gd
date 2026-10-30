extends Node2D

const FROST_OBSTACLE_SCENE := preload("res://scenes/frost_obstacle.tscn")

var _pulse := 0.0
var safehouse_rect := Rect2(475, 515, 290, 225)
var danger_rect := Rect2(1030, 225, 260, 300)
var heat_position := Vector2(620, 627)
var obstacle_nodes: Array[Node] = []

func set_layout(next_safehouse: Rect2, next_danger: Rect2, next_heat: Vector2, next_obstacles: Array = []) -> void:
    safehouse_rect = next_safehouse
    danger_rect = next_danger
    heat_position = next_heat
    _set_obstacles(next_obstacles)
    queue_redraw()

func _set_obstacles(layout: Array) -> void:
    for obstacle in obstacle_nodes:
        if is_instance_valid(obstacle):
            obstacle.queue_free()
    obstacle_nodes.clear()
    for raw in layout:
        if raw is not Array or raw.size() < 4:
            continue
        var obstacle := FROST_OBSTACLE_SCENE.instantiate() as FrostObstacle
        add_child(obstacle)
        obstacle.setup(raw[0], raw[1], int(raw[2]), float(raw[3]))
        obstacle_nodes.append(obstacle)

func set_obstacles_active(active: bool) -> void:
    for obstacle in obstacle_nodes:
        if is_instance_valid(obstacle) and obstacle.has_method("set_active"):
            obstacle.set_active(active)

func _process(delta: float) -> void:
    _pulse += delta
    queue_redraw()

func _draw() -> void:
    var map_rect := Rect2(72, 152, 1320, 680)
    draw_rect(map_rect, Color("#0b1828"), true)
    draw_rect(Rect2(map_rect.position + Vector2(0, 12), map_rect.size), Color(0.01, 0.03, 0.06, 0.75), true)
    for x in range(88, 1390, 48):
        draw_line(Vector2(x, 168), Vector2(x, 816), Color(0.30, 0.55, 0.62, 0.075), 1.0)
    for y in range(176, 820, 48):
        draw_line(Vector2(88, y), Vector2(1376, y), Color(0.30, 0.55, 0.62, 0.075), 1.0)

    # 斜向冰层和远景脊线，让灰盒地图具备 2.5D 的前后层次。
    for ridge in range(6):
        var ridge_y := 230.0 + ridge * 118.0
        var ridge_points := PackedVector2Array([
            Vector2(90, ridge_y + 38), Vector2(330, ridge_y - 22), Vector2(560, ridge_y + 24),
            Vector2(820, ridge_y - 36), Vector2(1080, ridge_y + 26), Vector2(1372, ridge_y - 18),
            Vector2(1372, ridge_y + 12), Vector2(1080, ridge_y + 70), Vector2(820, ridge_y + 16),
            Vector2(560, ridge_y + 76), Vector2(330, ridge_y + 32), Vector2(90, ridge_y + 86),
        ])
        draw_colored_polygon(ridge_points, Color(0.16, 0.35, 0.46, 0.025 + ridge * 0.004))

    # 安全屋和危险区每次登陆都会重新选点；安全屋始终位于危险区左侧。
    draw_colored_polygon(PackedVector2Array([
        safehouse_rect.position + Vector2(0, 18), safehouse_rect.position + Vector2(safehouse_rect.size.x, 18),
        safehouse_rect.end + Vector2(0, 18), safehouse_rect.end + Vector2(-safehouse_rect.size.x, 18),
    ]), Color(0.01, 0.04, 0.07, 0.65))
    draw_rect(safehouse_rect, Color("#1c3549"), true)
    draw_rect(safehouse_rect, Color("#77b7dd"), false, 2.0)
    draw_colored_polygon(PackedVector2Array([
        danger_rect.position + Vector2(0, 18), danger_rect.position + Vector2(danger_rect.size.x, 18),
        danger_rect.end + Vector2(0, 18), danger_rect.end + Vector2(-danger_rect.size.x, 18),
    ]), Color(0.06, 0.02, 0.04, 0.70))
    draw_rect(danger_rect, Color("#3b2c35"), true)
    draw_rect(danger_rect, Color("#e3a45f"), false, 2.0)

    # 根据本局布局绘制探索路线，热能电池不再绑定到固定资源区。
    var safe_center := safehouse_rect.get_center()
    var danger_center := danger_rect.get_center()
    draw_line(Vector2(125, 470), safe_center, Color("#61c8b5"), 10.0)
    draw_line(Vector2(125, 470), safe_center, Color("#c4fff0"), 2.0)
    draw_line(safe_center, danger_center, Color("#d0b875"), 8.0)
    draw_line(safe_center, danger_center, Color("#fff1b8"), 2.0)
    draw_circle(Vector2(125, 470), 10.0, Color("#eaf8f4"))
    draw_circle((safe_center + danger_center) * 0.5, 8.0, Color("#fff1b8"))

    # 热源：内圈为恒温范围，玩家在此范围内回温。热能电池由 ResourceCrate 节点绘制。
    var heat_radius := 42.0 + sin(_pulse * 2.2) * 4.0
    draw_circle(heat_position + Vector2(0, 10), heat_radius * 1.15, Color(0.01, 0.02, 0.03, 0.55))
    draw_circle(heat_position, heat_radius * 1.8, Color(1.0, 0.67, 0.26, 0.035))
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

    # 投送与撤离点，热能电池在此上交。
    var exit_center := Vector2(1290, 760)
    draw_circle(exit_center, 38.0, Color(0.35, 0.75, 1.0, 0.08))
    draw_arc(exit_center, 38.0, 0.0, TAU, 32, Color("#77d9ff"), 2.0)
    draw_arc(exit_center, 25.0, -_pulse, TAU - _pulse, 24, Color("#d2f5ff"), 3.0)
    draw_line(exit_center - Vector2(12, 0), exit_center + Vector2(12, 0), Color("#d2f5ff"), 2.0)
    draw_line(exit_center - Vector2(0, 12), exit_center + Vector2(0, 12), Color("#d2f5ff"), 2.0)

    draw_string(ThemeDB.fallback_font, safehouse_rect.position + Vector2(16, 28), "安全屋 / 热源 · 恒温区", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#b9ddff"))
    draw_string(ThemeDB.fallback_font, danger_rect.position + Vector2(16, 28), "危险区", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#ffd38a"))
    draw_string(ThemeDB.fallback_font, Vector2(1195, 815), "G 投送 / 撤离点", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#bdeeff"))
    draw_string(ThemeDB.fallback_font, Vector2(96, 810), "霜烬星  /  FROST ASH  ·  局部视野  ·  暴风雪航线", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#b7cbd6"))

func get_spawn_position(index: int) -> Vector2:
    var slots := [Vector2(170, 360), Vector2(260, 360), Vector2(350, 360), Vector2(440, 360)]
    return slots[index % slots.size()]
