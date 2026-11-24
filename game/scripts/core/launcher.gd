extends Node

## 迷失太空 · 五幕整合 · 启动器
##
## 主场景入口：选择 单人剧情 / 创建主机 / 加入主机。
## 选定后启动/复用 SessionHub 会话（host=创建 ENet 主机，client=加入），
## 然后统一进入第一幕 `res://act1/act01.tscn` 开始真实战役；
## 第一幕真实发车完成后走统一交接
## `Act1SessionBridge → SessionHub.complete_chapter("act01", …, "act23", …)`
## 进入 `scenes/act23.tscn`（Act23Chapter），后续各幕在同一会话内交接。

const ACT01_SCENE := "res://act1/act01.tscn"
const PORT_DEFAULT := 9877

var address: String = "127.0.0.1"
var address_edit: LineEdit
var status_label: Label


func _ready() -> void:
	InputSetup.ensure_actions()
	_build_ui()
	if "--packaged-smoke" in OS.get_cmdline_user_args():
		_run_packaged_smoke.call_deferred()


## Packaged-build acceptance: capture the real launcher menu, then drive it
## into Act 4 (the scene switch frees this node; Act 4's game.gd captures the
## entered shot when --packaged-smoke is passed through).
func _run_packaged_smoke() -> void:
	# Accept the shot directory from the caller so a packaged build never writes
	# into a developer's absolute desktop path.
	var out_dir: String = ""
	for arg_value in OS.get_cmdline_user_args():
		var arg: String = str(arg_value)
		if arg.begins_with("--shot-dir="):
			out_dir = arg.split("=", true, 1)[1]
	if out_dir.is_empty():
		out_dir = ProjectSettings.globalize_path("user://packaged_smoke")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var img0: Image = get_viewport().get_texture().get_image()
	if img0 != null:
		img0.save_png(out_dir + "/launcher_menu.png")
		print("PKG_SHOT launcher_menu")
	_start_solo()


func _build_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "UICanvas"
	add_child(canvas)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.035, 0.045, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 160)
	margin.add_theme_constant_override("margin_right", 160)
	margin.add_theme_constant_override("margin_top", 90)
	margin.add_theme_constant_override("margin_bottom", 90)
	canvas.add_child(margin)

	var center: VBoxContainer = VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 20)
	margin.add_child(center)

	var title: Label = Label.new()
	title.text = "迷失太空\nResonance 01 → 05 五幕整合"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	center.add_child(title)

	var sub: Label = Label.new()
	sub.text = "第一幕 · 静默矿站  →  发车进入第二三幕 · 矿车  →  第四幕 · 晶体  →  第五幕 · 地心"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.65, 0.85, 0.9))
	center.add_child(sub)

	center.add_child(_spacer(14))

	var solo_btn: Button = _make_button("开始单人剧情")
	solo_btn.pressed.connect(func() -> void: _start_solo())
	center.add_child(solo_btn)

	var host_btn: Button = _make_button("创建主机（等待队友加入）")
	host_btn.pressed.connect(func() -> void: _start_host())
	center.add_child(host_btn)

	var client_btn: Button = _make_button("加入主机")
	client_btn.pressed.connect(func() -> void: _start_client())
	center.add_child(client_btn)

	# LAN address field: a 2–4 player session across two machines needs a real
	# host IP, and the packaged build must not depend on editing a script.
	var addr_row: HBoxContainer = HBoxContainer.new()
	addr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	addr_row.add_theme_constant_override("separation", 10)
	center.add_child(addr_row)

	var addr_label: Label = Label.new()
	addr_label.text = "主机地址"
	addr_label.add_theme_font_size_override("font_size", 15)
	addr_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	addr_row.add_child(addr_label)

	address_edit = LineEdit.new()
	address_edit.text = address
	address_edit.placeholder_text = "127.0.0.1"
	address_edit.custom_minimum_size = Vector2(220, 38)
	address_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	address_edit.add_theme_font_size_override("font_size", 16)
	addr_row.add_child(address_edit)

	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.55, 0.88, 0.86))
	center.add_child(status_label)

	var hint: Label = Label.new()
	hint.text = "WASD 移动 · E 交互 · F 拾取/搬运 · Q 旋转晶体 · R 重置\n本地双人：开两个窗口，一个「创建主机」一个「加入主机」\n局域网联机：主机方把本机 IP 告诉队友，队友填进地址栏再点「加入主机」（端口 %d）" % PORT_DEFAULT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	center.add_child(hint)


func _make_button(text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(360, 56)
	btn.add_theme_font_size_override("font_size", 20)
	return btn


func _spacer(h: int) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _start_solo() -> void:
	SessionHub.mode = "solo"
	_set_status("正在载入第一幕 · 静默矿站…")
	_enter_act1()


func _start_host() -> void:
	var err: int = SessionHub.start(true, PORT_DEFAULT)
	if err == OK:
		SessionHub.session.add_player(1, "七号", true)
		_set_status("主机已开启 · 端口 %d · 等待队友加入…" % PORT_DEFAULT)
		_enter_act1()
	else:
		_show_error("主机启动失败：%d（端口 %d 可能被占用）" % [err, PORT_DEFAULT])


func _start_client() -> void:
	if address_edit != null and not address_edit.text.strip_edges().is_empty():
		address = address_edit.text.strip_edges()
	var err: int = SessionHub.start(false, PORT_DEFAULT, address)
	if err == OK:
		SessionHub.session.add_player(2, "队友", true)
		_set_status("正在连接 %s:%d…" % [address, PORT_DEFAULT])
		_enter_act1()
	else:
		_show_error("连接主机失败：%d（检查地址 %s 与主机是否已开启）" % [err, address])


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _enter_act1() -> void:
	get_tree().change_scene_to_file(ACT01_SCENE)


func _show_error(text: String) -> void:
	_set_status(text)
	print("LAUNCHER_ERROR ", text)