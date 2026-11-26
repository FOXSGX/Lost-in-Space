extends Control

# 双向耦合校准的现场仪表（M3/M4）
#
# 旧版本是"指针 vs 目标刻度"的两条进度条，用户反馈"调频太无聊"。
# 新版只显示机器状态本身：
#   · 一张二维共振盘：横轴是 X（频率偏差），纵轴是 Y（相位偏差），
#     绿框是稳定窗，白点是你和队友一起把机器推到哪儿了；
#   · 蓄能刻度：三段，负载上升时均衡点在动，刻度本身就是进度；
#   · A/B 两个读数带方向提示（谁在操作、往哪边推），以及单人时的副控标识。
# 画的是"两个人共同把点按进绿框"，不是两条各自独立的槽。

var device: Node3D
var actor: CharacterBody3D
var font: Font
var _timer: float = 0.0
var panel: StyleBoxFlat

const DISC_CENTER := Vector2(76.0, 92.0)
const DISC_RADIUS := 48.0
const ERROR_RANGE := 0.42        # 盘面半径对应的偏差绝对值
const RIGHT_X := 138.0

const C_DIM := Color("#405665")
const C_TEXT := Color("#d8eeec")
const C_SOFT := Color("#9fb6bd")
const C_OK := Color("#75c8b0")
const C_WARN := Color("#ffc37b")
const C_ACCENT := Color("#8ce3ce")

func configure(stage_device: Node3D, player: CharacterBody3D, ui_font: Font) -> void:
    device = stage_device; actor = player; font = ui_font
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel = StyleBoxFlat.new(); panel.bg_color = Color(.025,.045,.065,.88)
    panel.set_corner_radius_all(12)

func _process(delta: float) -> void:
    visible = str(actor.get("operating_role")) != ""
    _timer += delta
    if visible and _timer > 0.033:
        _timer = 0.0; queue_redraw()

func _stage_name(stage: int) -> String:
    if stage <= 0: return "初始同步"
    if stage == 1: return "充能升载"
    return "稳定锁定"

func _draw() -> void:
    if device == null or font == null: return
    var model: RefCounted = device.get("calibration") as RefCounted
    if model == null: return
    var role: String = str(actor.get("operating_role"))
    if role == "": return

    var ex: float = float(model.call("error_x"))
    var ey: float = float(model.call("error_y"))
    var window: float = float(model.call("frequency_window"))
    var progress: float = float(model.get("progress"))
    var stage: int = int(model.get("stage"))
    var load: float = float(model.get("load"))
    var stable: bool = bool(model.get("stable_now"))
    var cooperative: bool = bool(model.get("cooperative"))
    var aux_role: String = str(model.get("solo_aux_role"))

    draw_style_box(panel, Rect2(Vector2.ZERO, size))

    # ── 共振盘 ────────────────────────────────────────────────────────────
    draw_circle(DISC_CENTER, DISC_RADIUS, Color("#0b1720"))
    draw_arc(DISC_CENTER, DISC_RADIUS, 0.0, TAU, 48, C_DIM, 2.0, true)
    draw_line(DISC_CENTER - Vector2(DISC_RADIUS, 0), DISC_CENTER + Vector2(DISC_RADIUS, 0), C_DIM, 1.0)
    draw_line(DISC_CENTER - Vector2(0, DISC_RADIUS), DISC_CENTER + Vector2(0, DISC_RADIUS), C_DIM, 1.0)
    # 稳定窗（绿框）：两条偏差都落在里面才算稳住
    var half: float = window / ERROR_RANGE * DISC_RADIUS
    draw_rect(Rect2(DISC_CENTER - Vector2(half, half), Vector2(half, half) * 2.0), C_OK, false, 2.0)
    # 误差点：X 向右为正，Y 向上为正
    var scale: float = DISC_RADIUS / ERROR_RANGE
    var point: Vector2 = DISC_CENTER + Vector2(
        clampf(ex * scale, -DISC_RADIUS, DISC_RADIUS),
        clampf(-ey * scale, -DISC_RADIUS, DISC_RADIUS))
    draw_line(DISC_CENTER, point, C_ACCENT, 1.0)
    draw_circle(point, 6.0, C_ACCENT if stable else C_WARN)
    draw_circle(point, 2.0, Color("#0b1720"))
    draw_string(font, Vector2(DISC_CENTER.x - 30.0, DISC_CENTER.y + DISC_RADIUS + 16.0),
        "双方偏差", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_SOFT)

    # ── 右侧：阶段、蓄能、两侧读数 ────────────────────────────────────────
    draw_string(font, Vector2(RIGHT_X, 24.0), "共振校准 · " + _stage_name(stage),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_TEXT)
    # 蓄能刻度：三段的边界直接画在条上
    var bar := Rect2(Vector2(RIGHT_X, 34.0), Vector2(246.0, 10.0))
    draw_rect(bar, Color("#223e49"))
    draw_rect(Rect2(bar.position, Vector2(maxf(1.0, bar.size.x * progress), bar.size.y)), C_ACCENT)
    for edge: float in [0.34, 0.72]:
        var x: float = bar.position.x + bar.size.x * edge
        draw_line(Vector2(x, bar.position.y - 3.0), Vector2(x, bar.position.y + bar.size.y + 3.0), C_DIM, 2.0)
    draw_string(font, Vector2(RIGHT_X + 250.0, 44.0), "%d%%" % int(progress * 100.0),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_SOFT)

    # 负载：和进度不是同一件事，单独一行，说明"均衡点在动"
    var load_bar := Rect2(Vector2(RIGHT_X, 52.0), Vector2(246.0, 5.0))
    draw_rect(load_bar, Color("#1a2f39"))
    draw_rect(Rect2(load_bar.position, Vector2(maxf(1.0, load_bar.size.x * load), load_bar.size.y)), C_WARN)

    # A / B 两侧读数
    var a_value: float = float(model.get("frequency"))
    var b_value: float = float(model.get("preload_value"))
    var a_target: float = float(model.call("target_a"))
    var b_target: float = float(model.call("target_b"))
    var users: Dictionary = model.get("users") as Dictionary
    var a_arrow: String = "↑" if a_target > a_value else "↓"
    var b_arrow: String = "↑" if b_target > b_value else "↓"
    var a_tag: String = "你" if role == "frequency" else ("副控" if aux_role == "frequency" else "队友")
    var b_tag: String = "你" if role == "preload" else ("副控" if aux_role == "preload" else "队友")
    if not cooperative:
        a_tag = "你" if role == "frequency" else a_tag
        b_tag = "你" if role == "preload" else b_tag
    draw_string(font, Vector2(RIGHT_X, 78.0),
        "A 频率 %d%%  %s   %s" % [int(a_value * 100.0), a_arrow, a_tag],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TEXT if role == "frequency" else C_SOFT)
    draw_string(font, Vector2(RIGHT_X, 98.0),
        "B 相位 %d%%  %s   %s" % [int(b_value * 100.0), b_arrow, b_tag],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TEXT if role == "preload" else C_SOFT)
    # 队友那端是否真的在操作：这是"要交流"的最直接依据
    if cooperative:
        var other: String = "preload" if role == "frequency" else "frequency"
        var held: bool = int(users.get(other, 0)) > 0
        draw_string(font, Vector2(RIGHT_X, 118.0), "对端" + ("已接入" if held else "未接入 · 需要有人去那台设备"),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_OK if held else C_WARN)

    # 状态一句话
    var reason: String = str(model.get("reason"))
    draw_string(font, Vector2(RIGHT_X, 140.0), reason, HORIZONTAL_ALIGNMENT_LEFT, 246.0, 13,
        C_OK if stable else C_SOFT)

    # 单人：副控在动哪一端，必须让玩家看见，否则以为是游戏自己变好
    if not cooperative and aux_role != "":
        draw_string(font, Vector2(RIGHT_X, 160.0),
            "副控正在补偿 " + ("A 频率" if aux_role == "frequency" else "B 相位") + " · 速度只有你的一半",
            HORIZONTAL_ALIGNMENT_LEFT, 246.0, 13, C_WARN)
    elif not cooperative:
        draw_string(font, Vector2(RIGHT_X, 160.0), "接入任意一端，另一端交给副控",
            HORIZONTAL_ALIGNMENT_LEFT, 246.0, 13, C_SOFT)
