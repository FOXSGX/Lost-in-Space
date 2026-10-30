extends StaticBody2D
class_name FrostObstacle

enum ObstacleKind { ICE_SPIRE, ICE_RIDGE, CREVASSE, WRECK }

var kind := ObstacleKind.ICE_SPIRE
var obstacle_size := Vector2(72.0, 52.0)
var obstacle_angle := 0.0
var wall_height := 30.0
var active := true

func setup(next_position: Vector2, next_size: Vector2, next_kind: int, next_angle: float) -> void:
    position = next_position
    obstacle_size = next_size
    kind = next_kind
    obstacle_angle = next_angle
    rotation = obstacle_angle
    wall_height = 46.0 if kind == ObstacleKind.ICE_RIDGE else 34.0
    collision_layer = 2
    collision_mask = 1
    var shape := RectangleShape2D.new()
    shape.size = Vector2(maxf(obstacle_size.x * 0.72, 24.0), maxf(obstacle_size.y * 0.64, 24.0))
    var collision := CollisionShape2D.new()
    collision.name = "ObstacleCollision"
    collision.shape = shape
    add_child(collision)
    z_index = int(position.y)
    queue_redraw()

func set_active(next_active: bool) -> void:
    active = next_active
    visible = active
    collision_layer = 2 if active else 0
    collision_mask = 1 if active else 0

func _draw() -> void:
    var half := obstacle_size * 0.5
    draw_set_transform(Vector2(12.0, 18.0), 0.0, Vector2(1.16, 0.42))
    _draw_shadow(half)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    match kind:
        ObstacleKind.ICE_RIDGE:
            _draw_ice_ridge(half)
        ObstacleKind.CREVASSE:
            _draw_crevasse(half)
        ObstacleKind.WRECK:
            _draw_wreck(half)
        _:
            _draw_ice_spire(half)

func _draw_shadow(half: Vector2) -> void:
    var points := PackedVector2Array()
    for index in range(32):
        var angle := TAU * float(index) / 32.0
        points.append(Vector2(cos(angle) * maxf(half.x * 1.05, 22.0), sin(angle) * maxf(half.y * 0.9, 16.0)))
    draw_colored_polygon(points, Color(0.0, 0.015, 0.03, 0.62))

func _draw_box(half: Vector2, top_color: Color, front_color: Color, side_color: Color) -> void:
    var top_left := Vector2(-half.x, -half.y)
    var top_right := Vector2(half.x, -half.y)
    var bottom_right := Vector2(half.x, half.y)
    var bottom_left := Vector2(-half.x, half.y)
    var lift := Vector2(0.0, wall_height)
    draw_colored_polygon(PackedVector2Array([bottom_left, bottom_right, bottom_right + lift, bottom_left + lift]), front_color)
    draw_colored_polygon(PackedVector2Array([top_right, bottom_right, bottom_right + lift, top_right + lift]), side_color)
    draw_rect(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0), top_color, true)
    draw_line(top_left, top_right, Color("#efffff", 0.9), 2.0)
    draw_line(top_right, bottom_right, Color("#4c859c", 0.9), 2.0)
    draw_line(bottom_left + lift, bottom_right + lift, Color("#172c3d", 0.65), 2.0)

func _draw_ice_spire(half: Vector2) -> void:
    _draw_box(half, Color("#8fe5f2"), Color("#35677d"), Color("#4d9bb4"))
    var peak := Vector2(0.0, -half.y * 1.28)
    draw_colored_polygon(PackedVector2Array([Vector2(-half.x, -half.y), peak, Vector2(0.0, half.y * 0.08)]), Color("#d8fbff"))
    draw_colored_polygon(PackedVector2Array([peak, Vector2(half.x, -half.y), Vector2(0.0, half.y * 0.08)]), Color("#63b7cf"))
    draw_line(peak, peak + Vector2(0.0, wall_height), Color("#f4ffff", 0.85), 2.0)

func _draw_ice_ridge(half: Vector2) -> void:
    _draw_box(half, Color("#79d2e4"), Color("#24475e"), Color("#3d7e96"))
    draw_colored_polygon(PackedVector2Array([
        Vector2(-half.x, -half.y), Vector2(-half.x * 0.45, -half.y * 1.22),
        Vector2(half.x * 0.2, -half.y), Vector2(half.x, -half.y * 0.82),
    ]), Color("#baf4f7"))
    draw_line(Vector2(-half.x * 0.45, -half.y * 1.22), Vector2(-half.x * 0.45, -half.y * 1.22 + wall_height), Color("#efffff", 0.9), 2.0)

func _draw_crevasse(half: Vector2) -> void:
    var lip_height := 9.0
    draw_colored_polygon(PackedVector2Array([
        Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
        Vector2(half.x, half.y), Vector2(-half.x, half.y),
    ]), Color("#081724"))
    draw_colored_polygon(PackedVector2Array([
        Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
        Vector2(half.x, -half.y + lip_height), Vector2(-half.x, -half.y + lip_height),
    ]), Color("#9de4eb"))
    draw_colored_polygon(PackedVector2Array([
        Vector2(-half.x, half.y - lip_height), Vector2(half.x, half.y - lip_height),
        Vector2(half.x, half.y), Vector2(-half.x, half.y),
    ]), Color("#355d70"))
    draw_line(Vector2(-half.x * 0.6, -half.y * 0.35), Vector2(half.x * 0.7, half.y * 0.32), Color("#72cddd", 0.75), 2.0)

func _draw_wreck(half: Vector2) -> void:
    _draw_box(half, Color("#778f9a"), Color("#304451"), Color("#52707a"))
    draw_line(Vector2(-half.x * 0.62, -half.y * 0.48), Vector2(half.x * 0.62, half.y * 0.48), Color("#f0c16c"), 3.0)
    draw_line(Vector2(-half.x * 0.62, half.y * 0.48), Vector2(half.x * 0.58, -half.y * 0.48), Color("#d8e8e8", 0.75), 2.0)
