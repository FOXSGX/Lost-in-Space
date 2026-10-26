extends Control

# 录像用的实时帧时间曲线（只用于诊断视频，不参与游戏）。
# 任务书要求"提供关键帧时间曲线，不要仅在画面角落显示 FPS 数字"，
# 所以这里画的是每次采样的真实帧间隔，并叠加 p50 / p99 与阈值参考线。
# 纵轴自动量程：70 fps 的画面上限约 20ms，掉到 30 fps 才接近上限。

var samples: Array = []          # 每项是一帧的毫秒数
var label: String = ""
var capacity: int = 420
var floor_ms: float = 20.0       # 纵轴下限，避免正常帧被压成一条边

const PAD := 12.0
const BAR_W := 520.0
const BAR_H := 168.0
const HEAD_H := 46.0             # 顶部两行文字
const FOOT_H := 18.0

func push(frame_ms: float, tag: String = "") -> void:
    samples.append(frame_ms)
    if samples.size() > capacity:
        samples.pop_front()
    if tag != "":
        label = tag
    queue_redraw()

func _percentile(sorted_values: Array, q: float) -> float:
    if sorted_values.is_empty():
        return 0.0
    var index: int = clampi(int(round(float(sorted_values.size() - 1) * q)), 0, sorted_values.size() - 1)
    return float(sorted_values[index])

func _draw() -> void:
    var box := Rect2(Vector2(size.x - BAR_W - PAD, 76.0), Vector2(BAR_W, BAR_H))
    draw_rect(box, Color(0.02, 0.05, 0.07, 0.88))
    draw_rect(box, Color(0.25, 0.45, 0.55, 0.9), false, 1.5)
    if samples.is_empty():
        return

    var sorted_copy: Array = samples.duplicate()
    sorted_copy.sort()
    var p50: float = _percentile(sorted_copy, 0.50)
    var p95: float = _percentile(sorted_copy, 0.95)
    var p99: float = _percentile(sorted_copy, 0.99)
    var peak: float = float(sorted_copy[sorted_copy.size() - 1])

    var plot := Rect2(Vector2(box.position.x + 6.0, box.position.y + HEAD_H),
        Vector2(box.size.x - 12.0, box.size.y - HEAD_H - FOOT_H))
    # 自动量程：至少 20ms，峰值大时放大到峰值的 1.25 倍
    var y_cap: float = maxf(floor_ms, peak * 1.25)

    for ms: float in [16.7, 50.0, 100.0]:
        if ms > y_cap:
            continue
        var y: float = plot.position.y + plot.size.y - (ms / y_cap) * plot.size.y
        draw_line(Vector2(plot.position.x, y), Vector2(plot.position.x + plot.size.x, y),
            Color(0.30, 0.42, 0.48, 0.6), 1.0)
        draw_string(ThemeDB.fallback_font, Vector2(plot.position.x + plot.size.x - 44.0, y - 2.0),
            "%d" % int(ms), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.42, 0.55, 0.60))

    var step: float = plot.size.x / float(capacity)
    for i: int in range(samples.size()):
        var ms: float = float(samples[i])
        var h: float = clampf(ms / y_cap, 0.0, 1.0) * plot.size.y
        var color: Color = Color(0.45, 0.90, 0.80)
        if ms > 50.0:
            color = Color(1.0, 0.36, 0.30)
        elif ms > 20.0:
            color = Color(1.0, 0.76, 0.36)
        var x: float = plot.position.x + step * float(i)
        draw_rect(Rect2(Vector2(x, plot.position.y + plot.size.y - h), Vector2(maxf(step, 1.0), h)), color)

    for pair: Array in [[p50, Color(0.55, 1.0, 0.85)], [p99, Color(1.0, 0.45, 0.35)]]:
        var value: float = float(pair[0])
        var y: float = plot.position.y + plot.size.y - clampf(value / y_cap, 0.0, 1.0) * plot.size.y
        draw_line(Vector2(plot.position.x, y), Vector2(plot.position.x + plot.size.x, y), pair[1], 1.6)

    draw_string(ThemeDB.fallback_font, Vector2(box.position.x + 8.0, box.position.y + 18.0),
        "帧间隔 (ms)   p50 %.1f   p95 %.1f   p99 %.1f   max %.1f" % [p50, p95, p99, peak],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.88, 0.95, 0.95))
    draw_string(ThemeDB.fallback_font, Vector2(box.position.x + 8.0, box.position.y + 36.0),
        "真实墙钟 · 实时抓屏录制 · 纵轴 0–%d ms · %s" % [int(y_cap), label],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.62, 0.78, 0.82))
    draw_string(ThemeDB.fallback_font, Vector2(box.position.x + 8.0, box.position.y + box.size.y - 5.0),
        "绿 = p50    红 = p99     灰线 16.7 / 50 ms", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
        Color(0.45, 0.60, 0.66))
