extends Control

## 校准仪表：三种形状共用一块画布。
## mode = "bar"     横向计时条
## mode = "dial"    圆盘刻度（光束转盘）
## mode = "stepped" 角度指针（镜面角度，每次按键跳一格）

var mode: String = "bar"
var cursor: float = 0.0
var zone_start: float = 0.0
var zone_width: float = 0.0
var accent: Color = Color("#ffe27a")

const TRACK_BG := Color(0.10, 0.16, 0.24)
const ZONE_COLOR := Color("#2fbf8a")
const TICK_COLOR := Color(0.45, 0.62, 0.78)

func _draw() -> void:
    if mode == "bar":
        _draw_bar()
    else:
        _draw_dial()

func _draw_bar() -> void:
    var track: Rect2 = Rect2(12.0, 22.0, size.x - 24.0, 30.0)
    draw_rect(track, TRACK_BG)
    var zone_x: float = track.position.x + zone_start * track.size.x
    var zone_w: float = zone_width * track.size.x
    draw_rect(Rect2(zone_x, track.position.y, zone_w, track.size.y), ZONE_COLOR)
    var cursor_x: float = track.position.x + clampf(cursor, 0.0, 1.0) * track.size.x
    draw_rect(Rect2(cursor_x - 4.0, track.position.y - 8.0, 8.0, track.size.y + 16.0), accent)

func _draw_dial() -> void:
    var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.94)
    var radius: float = minf(size.x * 0.40, size.y * 0.80)
    var start_angle: float = deg_to_rad(150.0)
    var sweep: float = deg_to_rad(240.0)
    # 外圈底座
    draw_arc(center, radius, start_angle, start_angle + sweep, 48, TRACK_BG, 10.0, true)
    # 刻度
    var tick_count: int = 13 if mode == "dial" else 12
    for index in tick_count:
        var t: float = float(index) / float(tick_count - 1)
        var angle: float = start_angle + sweep * t
        var direction: Vector2 = Vector2(cos(angle), sin(angle))
        draw_line(center + direction * (radius - 12.0), center + direction * radius, TICK_COLOR, 2.0)
    # 绿色合格弧
    var arc_steps: int = 28
    var zone_from: float = start_angle + sweep * zone_start
    var zone_to: float = start_angle + sweep * (zone_start + zone_width)
    var polygon: PackedVector2Array = PackedVector2Array()
    for index in arc_steps + 1:
        var angle: float = lerpf(zone_from, zone_to, float(index) / float(arc_steps))
        polygon.append(center + Vector2(cos(angle), sin(angle)) * (radius - 2.0))
    for index in range(arc_steps, -1, -1):
        var angle: float = lerpf(zone_from, zone_to, float(index) / float(arc_steps))
        polygon.append(center + Vector2(cos(angle), sin(angle)) * (radius - 20.0))
    if polygon.size() >= 3:
        draw_colored_polygon(polygon, ZONE_COLOR)
    # 指针
    var needle_angle: float = start_angle + sweep * clampf(cursor, 0.0, 1.0)
    var needle: Vector2 = center + Vector2(cos(needle_angle), sin(needle_angle)) * (radius - 8.0)
    draw_line(center, needle, accent, 4.0, true)
    draw_circle(center, 7.0, accent)
