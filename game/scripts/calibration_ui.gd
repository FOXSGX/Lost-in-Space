class_name CalibrationUI
extends Control

## 校准小游戏的 HUD 绘制：三种形状 + 重试进度 + 成功/失败闪示。
##
## 只负责“把 state 画出来”，不持有玩法状态、不做判定——
## 判定在 CalibrationMinigame 里，HUD 读它的 current_state() 即可。
##
## 用法：
##     var hud: CalibrationUI = CalibrationUI.new()
##     hud.size = Vector2(580, 168)
##     hud.set_state(state)
##     hud.flash_result(result)      # 成功/失败时闪一下
##
## 形状：
##   bar     横向计时条（热阀、电源端、冷却座、模块接口……）
##   dial    圆盘刻度 + 指针（镜面节点、光束转盘）
##   stepped 圆盘 + 12 格步进（同 dial，但指针按格跳，绿区更窄）

const TRACK_BG: Color = Color(0.10, 0.16, 0.24)
const TRACK_EDGE: Color = Color(0.24, 0.38, 0.52)
const ZONE_COLOR: Color = Color("#2fbf8a")
const ZONE_ASSIST_COLOR: Color = Color("#5fd6a8")
const TICK_COLOR: Color = Color(0.45, 0.62, 0.78)
const CURSOR_COLOR: Color = Color("#ffe27a")
const CURSOR_HIT_COLOR: Color = Color("#7ef2c8")
const TIME_COLOR: Color = Color(0.55, 0.80, 0.98)
const RETRY_EMPTY: Color = Color(0.30, 0.34, 0.40)
const RETRY_FULL: Color = Color("#ff9a6a")
const SUCCESS_FLASH: Color = Color(0.62, 0.96, 0.80)
const FAIL_FLASH: Color = Color(1.0, 0.55, 0.42)

var mode: String = "bar"
var cursor: float = 0.0
var zone_start: float = 0.0
var zone_width: float = 0.0
var remaining: float = 0.0
var duration: float = 0.0
var retry_count: int = 0
var max_retries: int = 3
var assisted: bool = false
var active: bool = false

var _flash_color: Color = Color(0, 0, 0, 0)
var _flash_time: float = 0.0
var _flash_duration: float = 0.42


func _ready() -> void:
    set_process(true)
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_state(state: Dictionary) -> void:
    mode = String(state.get("mode", "bar"))
    cursor = float(state.get("cursor", 0.0))
    zone_start = float(state.get("zone_start", 0.0))
    zone_width = float(state.get("zone_width", 0.0))
    remaining = float(state.get("remaining", 0.0))
    duration = maxf(float(state.get("duration", 1.0)), 0.0001)
    retry_count = int(state.get("retry_count", 0))
    max_retries = maxi(int(state.get("max_retries", 3)), 1)
    assisted = bool(state.get("assist", false))
    active = bool(state.get("active", true))
    queue_redraw()


## 成功/失败时调用：整块面板闪一下对应颜色，0.42 秒衰减完。
func flash_result(result: Dictionary) -> void:
    var success: bool = bool(result.get("success", false))
    _flash_color = SUCCESS_FLASH if success else FAIL_FLASH
    _flash_time = _flash_duration
    queue_redraw()


func _process(delta: float) -> void:
    if _flash_time > 0.0:
        _flash_time = maxf(_flash_time - delta, 0.0)
        queue_redraw()


func _draw() -> void:
    if zone_width <= 0.0:
        return
    if mode == "bar":
        _draw_bar()
    else:
        _draw_dial()
    _draw_retries()
    _draw_flash()


# --------------------------------------------------------------------------
# 形状
# --------------------------------------------------------------------------
func _draw_bar() -> void:
    var track: Rect2 = Rect2(10.0, size.y * 0.42, size.x - 20.0, 26.0)
    draw_rect(track, TRACK_BG)
    draw_rect(track, TRACK_EDGE, false, 1.5)
    # 绿区（辅助模式下换成偏亮的绿，玩家能看出容错被放宽了）
    var zone_color: Color = ZONE_ASSIST_COLOR if assisted else ZONE_COLOR
    var zone_rect: Rect2 = _zone_rect_in(track, zone_start, zone_width)
    draw_rect(zone_rect, Color(zone_color.r, zone_color.g, zone_color.b, 0.85))
    # 绿区中段的高亮带：给出“最佳落点”的视觉锚
    var center_band: Rect2 = _zone_rect_in(track, zone_start + zone_width * 0.35, zone_width * 0.3)
    draw_rect(center_band, Color(1.0, 1.0, 1.0, 0.16))
    # 剩余时间：沿轨道底部的一条细条
    var time_ratio: float = clampf(remaining / duration, 0.0, 1.0)
    draw_rect(Rect2(track.position.x, track.position.y + track.size.y + 5.0, track.size.x * time_ratio, 3.0), TIME_COLOR)
    draw_rect(Rect2(track.position.x, track.position.y + track.size.y + 5.0, track.size.x, 3.0), Color(0.2, 0.28, 0.36, 0.7), false, 1.0)
    # 光标
    var cursor_x: float = track.position.x + clampf(cursor, 0.0, 1.0) * track.size.x
    var hit: bool = is_cursor_in_zone()
    var accent: Color = CURSOR_HIT_COLOR if hit else CURSOR_COLOR
    draw_rect(Rect2(cursor_x - 3.0, track.position.y - 9.0, 6.0, track.size.y + 18.0), accent)
    var tip: PackedVector2Array = PackedVector2Array([
        Vector2(cursor_x, track.position.y - 10.0),
        Vector2(cursor_x - 6.0, track.position.y - 18.0),
        Vector2(cursor_x + 6.0, track.position.y - 18.0)
    ])
    draw_colored_polygon(tip, accent)


func _draw_dial() -> void:
    var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.92)
    var radius: float = minf(size.x * 0.36, size.y * 0.72)
    var start_angle: float = deg_to_rad(150.0)
    var sweep: float = deg_to_rad(240.0)
    draw_arc(center, radius, start_angle, start_angle + sweep, 56, TRACK_BG, 11.0, true)
    draw_arc(center, radius, start_angle, start_angle + sweep, 56, TRACK_EDGE, 1.5, true)
    var tick_count: int = 13 if mode == "dial" else 12
    for index in tick_count:
        var t: float = float(index) / float(tick_count - 1)
        var angle: float = start_angle + sweep * t
        var direction: Vector2 = Vector2(cos(angle), sin(angle))
        draw_line(center + direction * (radius - 13.0), center + direction * radius, TICK_COLOR, 2.0)
    # 绿弧
    var zone_color: Color = ZONE_ASSIST_COLOR if assisted else ZONE_COLOR
    var steps: int = 28
    var zone_from: float = start_angle + sweep * zone_start
    var zone_to: float = start_angle + sweep * minf(zone_start + zone_width, 1.0)
    var polygon: PackedVector2Array = PackedVector2Array()
    for index in steps + 1:
        var angle: float = lerpf(zone_from, zone_to, float(index) / float(steps))
        polygon.append(center + Vector2(cos(angle), sin(angle)) * (radius - 3.0))
    for index in range(steps, -1, -1):
        var angle: float = lerpf(zone_from, zone_to, float(index) / float(steps))
        polygon.append(center + Vector2(cos(angle), sin(angle)) * (radius - 22.0))
    if polygon.size() >= 3:
        draw_colored_polygon(polygon, Color(zone_color.r, zone_color.g, zone_color.b, 0.9))
    # 剩余时间弧（内圈，细）
    var time_ratio: float = clampf(remaining / duration, 0.0, 1.0)
    draw_arc(center, radius - 28.0, start_angle, start_angle + sweep * time_ratio, 40, TIME_COLOR, 2.5, true)
    # 指针
    var needle_angle: float = start_angle + sweep * clampf(cursor, 0.0, 1.0)
    var accent: Color = CURSOR_HIT_COLOR if is_cursor_in_zone() else CURSOR_COLOR
    var needle: Vector2 = center + Vector2(cos(needle_angle), sin(needle_angle)) * (radius - 7.0)
    draw_line(center, needle, accent, 4.0, true)
    draw_circle(center, 6.0, accent)


func _draw_retries() -> void:
    # 重试进度：底部一排小方块，填满表示已经失败几次
    var pip_size: float = 8.0
    var gap: float = 5.0
    var total_width: float = float(max_retries) * (pip_size + gap) - gap
    var origin: Vector2 = Vector2(size.x * 0.5 - total_width * 0.5, size.y - 12.0)
    for index in max_retries:
        var pip: Rect2 = Rect2(origin.x + float(index) * (pip_size + gap), origin.y, pip_size, 4.0)
        draw_rect(pip, RETRY_FULL if index < retry_count else RETRY_EMPTY)


func _draw_flash() -> void:
    if _flash_time <= 0.0:
        return
    var strength: float = clampf(_flash_time / _flash_duration, 0.0, 1.0)
    var wash: Color = Color(_flash_color.r, _flash_color.g, _flash_color.b, 0.20 * strength)
    draw_rect(Rect2(Vector2.ZERO, size), wash)


# --------------------------------------------------------------------------
# 工具
# --------------------------------------------------------------------------
func is_cursor_in_zone() -> bool:
    if zone_width <= 0.0:
        return false
    var end: float = zone_start + zone_width
    if end <= 1.0:
        return cursor >= zone_start and cursor <= end
    return cursor >= zone_start or cursor <= end - 1.0


func _zone_rect_in(track: Rect2, start: float, width: float) -> Rect2:
    var end: float = start + width
    if end <= 1.0:
        return Rect2(track.position.x + start * track.size.x, track.position.y, width * track.size.x, track.size.y)
    # 绿区绕回：画两段（尾段 + 头段）
    var head_width: float = 1.0 - start
    return Rect2(
        track.position.x + start * track.size.x,
        track.position.y,
        maxf(head_width, width - head_width) * track.size.x,
        track.size.y
    )
