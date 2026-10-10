extends Control
class_name SpaceFrontend

signal host_requested(solo: bool)
signal join_requested(address: String)
signal destination_requested(id: String)
signal closed
signal disconnect_requested

const INK := Color("#e7eff6")
const MUTED := Color("#91a8bb")
const CYAN := Color("#67dfcd")
var view := "home"
var elapsed := 0.0
var content: Control
var notice: Label
var ip_field: LineEdit
var action_buttons: Dictionary = {}
var transit_bar: ProgressBar
var transit_detail: Label
var transit_title: Label
var transit_elapsed := 0.0
var transit_duration := 2.4
var transit_to := "demo"
var transit_reason := ""
var route_host := false
var route_count := 1

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    show_home()

func _process(delta: float) -> void:
    if not visible:
        return
    elapsed += delta
    if view == "transit":
        transit_elapsed += delta
        transit_bar.value = minf(transit_elapsed / transit_duration * 100.0, 95.0)
        if transit_elapsed >= transit_duration:
            transit_detail.text = "等待全队同步抵达…"
    queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
    if visible and event.is_action_pressed("ui_cancel"):
        if view == "route":
            hide_screen()
            closed.emit()
        elif view in ["help", "room"]:
            show_home()
        get_viewport().set_input_as_handled()

func _reset(next_view: String) -> void:
    view = next_view
    show()
    if is_instance_valid(content):
        remove_child(content)
        content.queue_free()
    content = Control.new()
    content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    content.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(content)
    action_buttons.clear()
    notice = null
    _label("L / S     LOST IN SPACE", Vector2(56, 34), Vector2(600, 28), 17, CYAN)
    _label("214  /  合作生存航行", Vector2(930, 35), Vector2(294, 26), 15, MUTED)
    _label("迷失太空    ·    找到回家的航线", Vector2(56, 655), Vector2(700, 24), 14, MUTED)
    _label("1 — 4 位宇航员", Vector2(1050, 655), Vector2(174, 24), 14, MUTED)

func _label(text: String, pos: Vector2, bounds: Vector2, font_size: int, color: Color = INK) -> Label:
    var label := Label.new()
    label.position = pos
    label.size = bounds
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.clip_text = true
    label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    content.add_child(label)
    return label

func _style(color: Color, border: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(8)
    style.content_margin_left = 18
    style.content_margin_right = 18
    return style

func _button(id: String, text: String, pos: Vector2, bounds: Vector2, callback: Callable, primary := false) -> Button:
    var button := Button.new()
    button.position = pos
    button.size = bounds
    button.text = text
    button.add_theme_font_size_override("font_size", 18)
    button.add_theme_stylebox_override("normal", _style(Color("#67dfcd") if primary else Color("#12263a"), CYAN if primary else Color("#29445b")))
    button.add_theme_stylebox_override("hover", _style(Color("#98efe1") if primary else Color("#1d3c51"), CYAN))
    button.add_theme_stylebox_override("pressed", _style(Color("#49b8a7") if primary else Color("#0d1e2d"), CYAN))
    button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), INK))
    button.add_theme_color_override("font_color", Color("#08212b") if primary else INK)
    button.add_theme_color_override("font_hover_color", Color("#08212b") if primary else INK)
    button.add_theme_color_override("font_pressed_color", Color("#08212b") if primary else INK)
    button.pressed.connect(callback)
    content.add_child(button)
    action_buttons[id] = button
    return button

func show_home() -> void:
    _reset("home")
    _label("漂流于星海，
一起找到归途。", Vector2(56, 124), Vector2(590, 160), 48)
    _label("在陌生星球搜集物资，为飞船寻找下一段航程。
探索、战斗、救援，与队友一同返回。", Vector2(60, 303), Vector2(480, 62), 17, MUTED)
    _button("solo", "开始单人航行   →", Vector2(60, 407), Vector2(390, 52), func(): host_requested.emit(true), true)
    _button("multiplayer", "联机航行", Vector2(60, 475), Vector2(390, 48), show_room)
    _button("help", "操作说明", Vector2(60, 539), Vector2(184, 42), show_help)
    _button("quit", "退出游戏", Vector2(266, 539), Vector2(184, 42), func(): get_tree().quit())
    _label("DEEP SPACE / 未知航域", Vector2(760, 541), Vector2(410, 24), 14, CYAN)
    _label("一艘飞船。数颗星球。一条回家的路。", Vector2(760, 575), Vector2(420, 48), 17, MUTED)

func show_room(message := "") -> void:
    _reset("room")
    _label("召集你的船员", Vector2(60, 145), Vector2(540, 62), 42)
    _label("由一位船员创建飞船，其他人通过主机 IP 加入。
当前支持同一局域网内最多 4 人协作。", Vector2(60, 226), Vector2(510, 70), 18, MUTED)
    _button("host", "创建飞船 / 成为主机", Vector2(60, 326), Vector2(430, 52), func(): host_requested.emit(false), true)
    _label("加入已有飞船 · 主机 IP", Vector2(60, 402), Vector2(430, 28), 17, MUTED)
    ip_field = LineEdit.new()
    ip_field.position = Vector2(60, 440)
    ip_field.size = Vector2(430, 48)
    ip_field.placeholder_text = "例如 192.168.1.10"
    ip_field.text = "127.0.0.1"
    ip_field.add_theme_font_size_override("font_size", 20)
    content.add_child(ip_field)
    ip_field.text_submitted.connect(func(_text): _submit_join())
    _button("join", "加入飞船", Vector2(60, 508), Vector2(430, 48), _submit_join)
    _button("back", "← 返回主界面", Vector2(60, 580), Vector2(210, 42), show_home)
    notice = _label(message, Vector2(535, 444), Vector2(650, 100), 18, Color("#ffcf7a"))
    _label("同行者，不必独自面对未知。", Vector2(710, 552), Vector2(510, 60), 25)

func _submit_join() -> void:
    join_requested.emit(ip_field.text.strip_edges())

func set_notice(message: String) -> void:
    if view == "room" and is_instance_valid(notice):
        notice.text = message

func set_connecting(connecting: bool) -> void:
    for id in ["host", "join", "back"]:
        if action_buttons.has(id):
            action_buttons[id].disabled = connecting
    if is_instance_valid(ip_field):
        ip_field.editable = not connecting

func show_help() -> void:
    _reset("help")
    _label("宇航员操作手册", Vector2(60, 126), Vector2(600, 66), 42)
    _label("WASD / 方向键      移动\n空格                         按住连续攻击\nQ                             扫描脉冲（期间无法移动）\nE                              修复信标 / 激活电力节点\nF / G                        拾取电池 / 投送电池\nR                              救援队友\nESC                         关闭航线图 / 返回上级菜单", Vector2(64, 220), Vector2(860, 226), 20)
    _label("霜烬星：修复 3 个气象信标、收集并投送 4 枚热能电池。
进入安全屋的热源范围补氧回温；暴风雪期间能见度与扫描范围下降。
每 15 秒出现一波敌人；目标就绪后停止增援。队友倒地后靠近按 R 救援。", Vector2(64, 459), Vector2(1040, 116), 18, MUTED)
    _button("back", "← 返回主界面", Vector2(64, 587), Vector2(270, 44), show_home)

func show_route(host: bool, count: int) -> void:
    route_host = host
    route_count = count
    _reset("route")
    _label("选择下一段航程", Vector2(60, 128), Vector2(660, 64), 42)
    _label("全队 %d 人 · %s" % [count, "由你指挥登陆" if host else "等待主机选择目的地"], Vector2(60, 214), Vector2(660, 32), 18, MUTED)
    _label("当前位置", Vector2(84, 340), Vector2(200, 30), 16, MUTED)
    _label("归航号", Vector2(84, 375), Vector2(200, 50), 28)
    _label("01 / 可登陆", Vector2(426, 312), Vector2(300, 30), 16, CYAN)
    _label("霜烬星", Vector2(426, 356), Vector2(330, 48), 32)
    _label("气象信标 · 热能电池 · 暴风雪撤离", Vector2(426, 416), Vector2(340, 60), 17, MUTED)
    _button("land_demo", "确认航程 / 登陆  →", Vector2(426, 498), Vector2(320, 48), func(): destination_requested.emit("demo"), true).disabled = not host
    _label("02 / 尚未开放", Vector2(876, 316), Vector2(330, 30), 16, MUTED)
    _label("电磁星球", Vector2(876, 359), Vector2(330, 48), 28, MUTED)
    _label("接收到微弱信号
等待关卡接入", Vector2(876, 419), Vector2(260, 74), 17, MUTED)
    _button("back", "← 返回飞船", Vector2(60, 587), Vector2(270, 44), func(): hide_screen(); closed.emit())

func show_transit(destination: String, reason: String, duration: float) -> void:
    transit_to = destination
    transit_reason = reason
    transit_duration = maxf(duration, 0.1)
    transit_elapsed = 0.0
    _reset("transit")
    var entry := PlanetRegistry.info(destination)
    _label("FLIGHT / 全队同步航行", Vector2(60, 134), Vector2(640, 28), 16, CYAN)
    transit_title = _label("正在返回飞船" if destination == "ship" else "正在登陆%s" % entry.get("title", destination), Vector2(60, 198), Vector2(650, 90), 42)
    _label(reason, Vector2(64, 310), Vector2(590, 104), 21, MUTED)
    transit_detail = _label("建立航线 · 校准坐标 · 同步船员", Vector2(64, 466), Vector2(560, 32), 17, CYAN)
    transit_bar = ProgressBar.new()
    transit_bar.position = Vector2(64, 518)
    transit_bar.size = Vector2(550, 8)
    transit_bar.show_percentage = false
    transit_bar.add_theme_stylebox_override("background", _style(Color("#1c3549"), Color("#1c3549")))
    transit_bar.add_theme_stylebox_override("fill", _style(CYAN, CYAN))
    content.add_child(transit_bar)
    _label("航行期间暂停移动与战斗。抵达后全队一起进入目的地。", Vector2(64, 559), Vector2(560, 64), 16, MUTED)
    _button("cancel", "断开并返回主界面", Vector2(896, 586), Vector2(290, 42), func(): disconnect_requested.emit())

func hide_screen() -> void:
    hide()

func _draw() -> void:
    draw_rect(Rect2(0, 0, 1280, 720), Color("#070f1b"))
    for i in 95:
        var point := Vector2(fmod(float(i * 193 + 37), 1280.0), fmod(float(i * 127 + 43), 720.0))
        var alpha := 0.15 + 0.25 * (sin(elapsed * 0.45 + i) + 1.0) * 0.5
        draw_circle(point, 1.0 if i % 4 else 1.8, Color(0.64, 0.78, 0.9, alpha))
    draw_line(Vector2(56, 79), Vector2(1224, 79), Color("#23384b"), 1.0)
    draw_line(Vector2(56, 639), Vector2(1224, 639), Color("#23384b"), 1.0)
    if view == "route":
        draw_line(Vector2(250, 386), Vector2(408, 386), CYAN, 2.0)
        for x in range(773, 856, 16):
            draw_line(Vector2(x, 386), Vector2(x + 8, 386), Color("#34485b"), 2.0)
        draw_circle(Vector2(291, 386), 8, CYAN)
        draw_rect(Rect2(405, 290, 364, 274), Color("#102a3c"))
        draw_rect(Rect2(405, 290, 364, 274), Color("#3b6879"), false, 1)
        draw_rect(Rect2(855, 290, 347, 274), Color("#101d2d"))
    else:
        var center := Vector2(929, 320)
        var radius := 160.0 if view != "transit" else 145.0
        draw_circle(center, radius + 36, Color(0.27, 0.6, 0.79, 0.03))
        draw_arc(center, radius + 36, 0, TAU, 100, Color("#244352"), 1)
        draw_circle(center, radius, Color("#173849"))
        draw_circle(center + Vector2(-30, -36), radius * 0.70, Color("#205264"))
        draw_circle(center + Vector2(-65, -47), radius * 0.38, Color("#276473"))
        draw_arc(center, radius, -PI * 0.8, PI * 0.1, 60, Color("#78c9cc"), 2)
        draw_arc(center, radius + 18, -0.4 + elapsed * 0.04, 2.7 + elapsed * 0.04, 60, Color("#67dfcd"), 1)
        var ship := center + Vector2(cos(elapsed * 0.17), sin(elapsed * 0.17)) * (radius + 47)
        draw_colored_polygon(PackedVector2Array([ship + Vector2(13, 0), ship + Vector2(-9, -6), ship + Vector2(-5, 0), ship + Vector2(-9, 6)]), INK)
        if view == "transit":
            for i in 20:
                var x := fmod(elapsed * 210.0 + i * 103.0, 1280.0)
                draw_line(Vector2(x, 175 + i * 18), Vector2(x + 26, 175 + i * 18), Color(0.4, 0.8, 0.85, 0.14), 1)
