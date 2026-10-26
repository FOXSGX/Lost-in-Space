extends Node

# Container-first menu/pause/settings adapter, based on the skill's pause_menu
# and settings_menu templates. Network time continues while a local menu opens.
var stage: Node3D
var screen: String = "main"
var overlay: Control
var column: VBoxContainer
var status: Label
var start_button: Button
var form_error: Label
var address: LineEdit
var port_input: LineEdit
var font: SystemFont
var ui_theme: Theme
var message: String = ""
var volume: float = 0.7
var sensitivity: float = 1.0
var reduced_effects: bool = false
var _refresh: float = 0.0

func _ready() -> void:
    font = SystemFont.new()
    font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
    ui_theme = (load("res://scripts/playtest_theme.gd") as Script).create_theme(font) as Theme
    var canvas: CanvasLayer = CanvasLayer.new()
    canvas.layer = 20
    add_child(canvas)
    overlay = Control.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.theme = ui_theme
    canvas.add_child(overlay)
    show_main()
    AudioServer.set_bus_volume_db(0, linear_to_db(volume))

func _page(heading: String, subtitle: String) -> void:
    for child: Node in overlay.get_children():
        overlay.remove_child(child)
        child.queue_free()
    overlay.show()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var dim: ColorRect = ColorRect.new()
    dim.color = Color(0.015, 0.035, 0.055, 0.96 if stage == null else 0.86)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(dim)
    var center: CenterContainer = CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.add_child(center)
    var panel: PanelContainer = PanelContainer.new()
    panel.custom_minimum_size.x = 620
    center.add_child(panel)
    column = VBoxContainer.new()
    panel.add_child(column)
    _label("LOST IN SPACE   /   CO-OP PLAYTEST 01", 16, Color("#ffc37b"))
    _label(heading, 34)
    _label(subtitle, 17, Color("#a3c5ca"))
    var rule: HSeparator = HSeparator.new()
    column.add_child(rule)
    status = null
    start_button = null
    form_error = null

func _label(text: String, points: int = 20, tint: Color = Color("#def1ee")) -> Label:
    var label: Label = Label.new()
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.custom_minimum_size.x = 556
    label.add_theme_font_size_override("font_size", points)
    label.add_theme_color_override("font_color", tint)
    column.add_child(label)
    return label

func _button(text: String, callback: Callable) -> Button:
    var button: Button = Button.new()
    button.text = text
    button.custom_minimum_size.y = 48
    button.pressed.connect(callback)
    column.add_child(button)
    return button

func show_main() -> void:
    screen = "main"
    _page("迷失太空 · 共振星", "矿车停靠站   /   1—2 人合作校准")
    if message != "": _label(message, 18, Color("#ffc37b"))
    _button("单人试玩", start_solo).grab_focus()
    _button("创建房间", show_host)
    _button("加入房间", show_join)
    _button("设置", show_settings)
    _button("退出", func() -> void: get_tree().quit())
    _label("本版用于真人试玩。合作乐趣和首次上手体验尚未验证。", 16, Color("#a3c5ca"))

func _make_stage() -> void:
    stage = (load("res://station.tscn") as PackedScene).instantiate() as Node3D
    stage.name = "Station"
    add_child(stage)
    stage.set("input_blocked", true)
    (stage.get("player") as Node).set("paused", true)
    var network: Node = stage.get("session") as Node
    network.connect("mission_started", _enter_mission)
    network.connect("transport_lost", _lost)
    (stage.get("hud") as CanvasLayer).hide()
    _apply_settings()

func start_solo() -> void:
    message = ""
    _make_stage()
    _enter_mission()

func show_host() -> void:
    screen = "host"
    _page("创建房间", "与队友在同一局域网内连接。房间最多 2 人。")
    _label("UDP 端口", 18)
    port_input = LineEdit.new()
    port_input.text = "26741"
    port_input.max_length = 5
    column.add_child(port_input)
    _button("创建并等待队友", create_room).grab_focus()
    _button("返回主菜单", show_main)

func _valid_port() -> int:
    var text: String = port_input.text.strip_edges()
    if not text.is_valid_int() or int(text) < 1024 or int(text) > 65535:
        _form_error("端口请输入 1024—65535 的整数。")
        return 0
    return int(text)

func _form_error(text: String) -> void:
    if form_error == null:
        form_error = _label(text, 17, Color("#ffc37b"))
    else:
        form_error.text = text

func create_room() -> void:
    var port: int = _valid_port()
    if port == 0: return
    _make_stage()
    var network: Node = stage.get("session") as Node
    network.set("port", port)
    if not bool(network.call("start_host")):
        message = str(stage.get("session_status")) + "。检查端口是否被占用。"
        leave_room(message)
        return
    _show_lobby()

func show_join() -> void:
    screen = "join"
    _page("加入房间", "输入房主的局域网 IPv4 地址与相同端口。")
    _label("主机 IP 地址", 18)
    address = LineEdit.new()
    address.placeholder_text = "例如 192.168.1.25（本机测试 127.0.0.1）"
    address.max_length = 80
    column.add_child(address)
    _label("UDP 端口", 18)
    port_input = LineEdit.new()
    port_input.text = "26741"
    port_input.max_length = 5
    column.add_child(port_input)
    _button("连接房间", connect_room)
    _button("返回主菜单", show_main)
    address.grab_focus()

func connect_room() -> void:
    var port: int = _valid_port()
    if port == 0: return
    var host: String = address.text.strip_edges()
    if not host.is_valid_ip_address():
        _form_error("请输入有效的 IP 地址。")
        return
    _make_stage()
    var network: Node = stage.get("session") as Node
    network.set("port", port)
    if not bool(network.call("join_host", host)):
        leave_room(str(stage.get("session_status")))
        return
    _show_lobby()

func _show_lobby() -> void:
    screen = "lobby"
    _page("船员集结", "双方进入房间后，由房主开始任务。")
    status = _label("连接中…", 19)
    var network: Node = stage.get("session") as Node
    if str(network.get("mode")) == "host":
        var addresses: PackedStringArray = []
        for ip: String in IP.get_local_addresses():
            if "." in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."):
                addresses.append(ip)
        _label("本机地址：" + (", ".join(addresses) if not addresses.is_empty() else "未检测到局域网 IPv4") + "\n端口：%d / UDP" % int(network.get("port")), 17)
        start_button = _button("等待第二名船员", func() -> void: network.call("start_mission"))
    else:
        _label("连接成功后，请等待房主开始。", 18)
    _button("取消 / 返回主菜单", func() -> void: leave_room("已离开房间"))
    _label("仅直连；任务开始后谢绝新加入。无公网匹配或 NAT 自动穿透。", 16, Color("#a3c5ca"))

func _enter_mission() -> void:
    screen = "playing"
    overlay.hide()
    stage.set("input_blocked", false)
    (stage.get("player") as Node).set("paused", false)
    (stage.get("hud") as CanvasLayer).show()
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func show_pause() -> void:
    screen = "pause"
    stage.set("input_blocked", true)
    (stage.get("player") as Node).set("paused", true)
    (stage.get("session") as Node).call("send_axis", 0.0)
    _page("任务菜单", "联机世界继续运行；暂离会停止本端的操作。")
    _button("继续探索", _enter_mission).grab_focus()
    if multiplayer.is_server():
        if str((stage.get("device") as Node).get("phase")) == "free":
            _button("找回地上的核心", func() -> void:
                stage.call("request_action", "recover_core")
                _enter_mission())
        _button("重新开始任务", func() -> void:
            stage.call("request_action", "reset")
            _enter_mission())
    _button("设置", show_settings)
    _button("返回主菜单 / 离开房间", func() -> void: leave_room("已离开房间"))
    _label("WASD 移动 · Shift 跑 · 鼠标视角\nF 拾取 · X 放下 · G 安装 · E 操作 / 离开\nA 端 A/D 调频 · B 端 W/S 调相位 · C 停机重试\nF1 提示 · F9 调试 · M 静音", 17)

func show_settings() -> void:
    screen = "settings"
    _page("设置", "设置立即生效，保留到本次程序退出。")
    _label("总音量", 18)
    var audio: HSlider = HSlider.new()
    audio.min_value = 0.0
    audio.max_value = 1.0
    audio.step = 0.05
    audio.value = volume
    audio.value_changed.connect(func(value: float) -> void:
        volume = value
        AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, volume))))
    column.add_child(audio)
    _label("鼠标灵敏度", 18)
    var mouse: HSlider = HSlider.new()
    mouse.min_value = 0.4
    mouse.max_value = 2.0
    mouse.step = 0.1
    mouse.value = sensitivity
    mouse.value_changed.connect(func(value: float) -> void:
        sensitivity = value
        _apply_settings())
    column.add_child(mouse)
    var reduce: CheckButton = CheckButton.new()
    reduce.text = "减少能量流与局部脉动灯光"
    reduce.button_pressed = reduced_effects
    reduce.toggled.connect(func(value: bool) -> void:
        reduced_effects = value
        _apply_settings())
    column.add_child(reduce)
    _button("返回", show_pause if stage != null else show_main)
    audio.grab_focus()

func _apply_settings() -> void:
    if stage == null: return
    (stage.get("player") as Node).set("mouse_sensitivity", sensitivity)
    var device: Node = stage.get("device") as Node
    (device.get("fx") as Node).set("enabled", not reduced_effects)

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel") and stage != null and screen in ["playing", "pause", "settings"]:
        if screen == "playing": show_pause()
        else: _enter_mission()
        get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
    _refresh += delta
    if _refresh < 0.2 or stage == null: return
    _refresh = 0.0
    if screen == "lobby" and status != null:
        var count: int = (stage.get("actors") as Dictionary).size()
        status.text = str(stage.get("session_status")) + "\n船员：%d / 2" % count
        if count == 2: status.text += "  ·  房主 1 / 队友 2 已就绪"
        if start_button != null:
            start_button.disabled = count < 2
            start_button.text = "开始合作任务" if count == 2 else "等待第二名船员"

func _lost(reason: String) -> void:
    leave_room.call_deferred(reason)

func leave_room(reason: String = "") -> void:
    if stage != null:
        (stage.get("session") as Node).call("close_session")
        remove_child(stage)
        stage.queue_free()
        stage = null
    message = reason
    show_main()
