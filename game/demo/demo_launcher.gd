extends Node

## Resonance Star demo entry screen.
##
## This menu starts the real Act23 chapter directly. Act23, Act04 and Act05
## keep their production hand-off contracts; the demo only narrows the entry
## point and presents instructions for the verified vertical-slice route.

const ACT23_SCENE: String = "res://scenes/act23.tscn"
const PORT_DEFAULT: int = 9877

var address_edit: LineEdit
var status_label: Label


func _ready() -> void:
	InputSetup.ensure_actions()
	_build_ui()


func _build_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "DemoMenuCanvas"
	add_child(canvas)

	var background: ColorRect = ColorRect.new()
	background.color = Color("09131c")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(background)

	var accent: ColorRect = ColorRect.new()
	accent.color = Color("43d7d0")
	accent.position = Vector2(0.0, 0.0)
	accent.size = Vector2(8.0, 720.0)
	canvas.add_child(accent)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 150)
	margin.add_theme_constant_override("margin_right", 150)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 38)
	canvas.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var eyebrow: Label = Label.new()
	eyebrow.text = "MIDTERM EVALUATION · WINDOWS VERTICAL SLICE"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", Color("7de8e0"))
	content.add_child(eyebrow)

	var title: Label = Label.new()
	title.text = "Lost in Space"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color("f3f7f4"))
	content.add_child(title)

	var demo_title: Label = Label.new()
	demo_title.text = "RESONANCE STAR"
	demo_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	demo_title.add_theme_font_size_override("font_size", 25)
	demo_title.add_theme_color_override("font_color", Color("ffc979"))
	content.add_child(demo_title)

	var route: Label = Label.new()
	route.text = "Act23 安全刹车与救援  →  Act04《会记忆的晶体》  →  Act05 章节交接"
	route.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	route.add_theme_font_size_override("font_size", 17)
	route.add_theme_color_override("font_color", Color("b7cbd0"))
	content.add_child(route)

	content.add_child(_spacer(10))

	var objective: Label = Label.new()
	objective.text = "合作目标：一名船员负责安全刹车与救援，另一名船员完成晶体搬运、校准与出口确认。每个章节必须通过真实操作才能进入下一幕。"
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.custom_minimum_size = Vector2(0.0, 46.0)
	objective.add_theme_font_size_override("font_size", 15)
	objective.add_theme_color_override("font_color", Color("d9e5e5"))
	content.add_child(objective)

	var controls: Label = Label.new()
	controls.text = "操作：WASD 移动 · 鼠标环视 · E 交互 · F 搬运/拾取 · B 安全刹车 · R 救援\n矿车维修：W/S 收放绞盘 · Shift 微调 · Space 绞盘制动 · Q 释放；晶体章节：Q 旋转"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_font_size_override("font_size", 14)
	controls.add_theme_color_override("font_color", Color("9fb4ba"))
	content.add_child(controls)

	content.add_child(_spacer(8))

	var address_row: HBoxContainer = HBoxContainer.new()
	address_row.alignment = BoxContainer.ALIGNMENT_CENTER
	address_row.add_theme_constant_override("separation", 10)
	content.add_child(address_row)

	var address_label: Label = Label.new()
	address_label.text = "主机地址"
	address_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	address_label.add_theme_font_size_override("font_size", 15)
	address_row.add_child(address_label)

	address_edit = LineEdit.new()
	address_edit.text = "127.0.0.1"
	address_edit.placeholder_text = "127.0.0.1"
	address_edit.custom_minimum_size = Vector2(210.0, 38.0)
	address_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	address_edit.add_theme_font_size_override("font_size", 16)
	address_row.add_child(address_edit)

	var solo_button: Button = _make_button("开始演示 · 单人")
	solo_button.pressed.connect(_start_solo)
	content.add_child(solo_button)

	var host_button: Button = _make_button("创建双人主机 · 端口 %d" % PORT_DEFAULT)
	host_button.pressed.connect(_start_host)
	content.add_child(host_button)

	var client_button: Button = _make_button("加入双人主机")
	client_button.pressed.connect(_start_client)
	content.add_child(client_button)

	status_label = Label.new()
	status_label.text = "准备就绪"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color("7de8e0"))
	content.add_child(status_label)

	var footer: Label = Label.new()
	footer.text = "当前 Demo 在 Act05 真实交接后结束；完成本 Demo 不代表完整五幕游戏完成。"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color("71868d"))
	content.add_child(footer)


func _make_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(430.0, 48.0)
	button.add_theme_font_size_override("font_size", 18)
	return button


func _spacer(height: int) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, float(height))
	return spacer


func _address_value() -> String:
	if address_edit == null or address_edit.text.strip_edges().is_empty():
		return "127.0.0.1"
	return address_edit.text.strip_edges()


func _start_solo() -> void:
	SessionHub.mode = "solo"
	SessionHub.session.setup(1, true)
	SessionHub.session.add_player(1, "七号", true)
	_set_status("正在加载 Act23…")
	_enter_act23()


func _start_host() -> void:
	var error: int = SessionHub.start(true, PORT_DEFAULT)
	if error != OK:
		_show_error("主机启动失败：%d" % error)
		return
	SessionHub.session.add_player(1, "七号", true)
	_set_status("主机已启动，等待队友加入…")
	_enter_act23()


func _start_client() -> void:
	var target: String = _address_value()
	var error: int = SessionHub.start(false, PORT_DEFAULT, target)
	if error != OK:
		_show_error("连接主机失败：%d" % error)
		return
	_set_status("正在连接 %s:%d…" % [target, PORT_DEFAULT])
	_enter_act23()


func _enter_act23() -> void:
	get_tree().change_scene_to_file(ACT23_SCENE)


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _show_error(text: String) -> void:
	_set_status(text)
	print("DEMO_LAUNCHER_ERROR ", text)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_close_session()
		get_tree().quit()


func _close_session() -> void:
	if SessionHub != null and SessionHub.net != null:
		SessionHub.net.shutdown()
