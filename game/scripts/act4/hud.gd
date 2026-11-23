class_name EchoHUD
extends CanvasLayer
## Minimal diegetic-support HUD. No arrows, no propagation bars: the world is
## the primary feedback channel. Text is limited to objective, interaction
## prompt, short feedback line and the memory subtitles.

const CYAN := Color(0.42, 0.90, 1.0)
const AMBER := Color(1.0, 0.72, 0.34)
const TEXT := Color(0.90, 0.96, 1.0)
const MUTED := Color(0.58, 0.68, 0.78)

var objective_label: Label
var objective_caption: Label
var prompt_label: Label
var speaker_label: Label
var subtitle_label: Label
var subtitle_panel: PanelContainer
var title_label: Label
var toast_label: Label
var controls_label: Label
var completion_root: Control
var completion_title: Label
var completion_body: Label
var crosshair: ColorRect
var settings_root: Control
var settings_sensitivity: Label
var settings_invert: Label
var warning_panel: PanelContainer
var warning_label: Label

var _subtitle_tween: Tween
var _title_tween: Tween
var _toast_tween: Tween
var _warning_tween: Tween
var _font: Font


func _ready() -> void:
	layer = 20
	name = "EchoHUD"
	# The settings overlay must still draw while the gameplay tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = _make_font()
	_build()


func _make_font() -> Font:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI",
		"Microsoft YaHei",
		"Noto Sans CJK SC",
		"Source Han Sans SC",
		"SimHei",
		"sans-serif",
	])
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	font.allow_system_fallback = true
	return font


func _label(text_value: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _panel(background: Color, border_color: Color, border_width: int, radius: int = 4) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border_color
	style.border_width_left = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _build() -> void:
	var root: Control = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Objective, top-left.
	var objective_panel: PanelContainer = _panel(Color(0.02, 0.05, 0.08, 0.82), CYAN, 3)
	objective_panel.position = Vector2(24.0, 22.0)
	objective_panel.custom_minimum_size = Vector2(430.0, 0.0)
	root.add_child(objective_panel)
	var objective_box: VBoxContainer = VBoxContainer.new()
	objective_box.add_theme_constant_override("separation", 3)
	objective_panel.add_child(objective_box)
	objective_caption = _label("RESONANCE 04  ·  会记忆的晶体", 12, CYAN)
	objective_caption.add_theme_constant_override("outline_size", 0)
	objective_box.add_child(objective_caption)
	objective_label = _label("调查中央的共振撞钟", 19, TEXT)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.custom_minimum_size = Vector2(400.0, 0.0)
	objective_box.add_child(objective_label)

	# Controls hint, top-right.
	controls_label = _label("WASD 移动 · 鼠标 视角 · Shift 疾跑\nE 交互 · F 搬运 / 放置 · Q 旋转晶体\nEsc 视角设置 · R 重置关卡", 12, Color(0.62, 0.72, 0.82, 0.78))
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls_label.position = Vector2(-360.0, 24.0)
	controls_label.custom_minimum_size = Vector2(336.0, 0.0)
	root.add_child(controls_label)

	# Subtle centre dot.
	crosshair = ColorRect.new()
	crosshair.color = Color(0.75, 0.92, 1.0, 0.32)
	crosshair.size = Vector2(4.0, 4.0)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-2.0, -2.0)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)

	# Memory title, top-centre.
	title_label = _label("记忆一 · 正常生产", 34, AMBER)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_label.position = Vector2(-400.0, 74.0)
	title_label.custom_minimum_size = Vector2(800.0, 0.0)
	title_label.modulate.a = 0.0
	root.add_child(title_label)

	# Resonance warning banner, top-centre under the memory title. It is the
	# only HUD element that appears during the freight accident, so the player
	# reads "the fault is reacting" without a permanent alarm widget.
	warning_panel = _panel(Color(0.12, 0.03, 0.02, 0.90), Color(1.0, 0.32, 0.16), 3, 5)
	warning_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	warning_panel.position = Vector2(-360.0, 126.0)
	warning_panel.custom_minimum_size = Vector2(720.0, 0.0)
	warning_panel.visible = false
	warning_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(warning_panel)
	warning_label = _label("断层共振上升", 22, Color(1.0, 0.72, 0.42))
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_panel.add_child(warning_label)

	# Bottom stack: prompt, subtitle, toast.
	var bottom: VBoxContainer = VBoxContainer.new()
	bottom.name = "BottomStack"
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -430.0
	bottom.offset_right = 430.0
	bottom.offset_top = -214.0
	bottom.offset_bottom = -24.0
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.custom_minimum_size = Vector2(860.0, 0.0)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	toast_label = _label("", 16, AMBER)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.modulate.a = 0.0
	bottom.add_child(toast_label)

	prompt_label = _label("", 16, Color(0.86, 0.94, 1.0))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(prompt_label)

	subtitle_panel = _panel(Color(0.01, 0.03, 0.055, 0.86), Color(0.20, 0.45, 0.55, 0.8), 1, 6)
	subtitle_panel.custom_minimum_size = Vector2(860.0, 0.0)
	subtitle_panel.modulate.a = 0.0
	subtitle_panel.visible = false
	bottom.add_child(subtitle_panel)
	var subtitle_box: VBoxContainer = VBoxContainer.new()
	subtitle_box.add_theme_constant_override("separation", 3)
	subtitle_panel.add_child(subtitle_box)
	speaker_label = _label("", 12, AMBER)
	subtitle_box.add_child(speaker_label)
	subtitle_label = _label("", 20, TEXT)
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.custom_minimum_size = Vector2(830.0, 0.0)
	subtitle_box.add_child(subtitle_label)

	# Completion overlay.
	completion_root = Control.new()
	completion_root.name = "Completion"
	completion_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	completion_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	completion_root.visible = false
	root.add_child(completion_root)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.035, 0.80)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	completion_root.add_child(dim)
	var completion_box: VBoxContainer = VBoxContainer.new()
	completion_box.set_anchors_preset(Control.PRESET_CENTER)
	completion_box.position = Vector2(-380.0, -120.0)
	completion_box.custom_minimum_size = Vector2(760.0, 0.0)
	completion_box.alignment = BoxContainer.ALIGNMENT_CENTER
	completion_box.add_theme_constant_override("separation", 14)
	completion_root.add_child(completion_box)
	completion_title = _label("第四幕完成", 46, AMBER)
	completion_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	completion_box.add_child(completion_title)
	completion_body = _label("", 20, TEXT)
	completion_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	completion_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	completion_body.custom_minimum_size = Vector2(760.0, 0.0)
	completion_box.add_child(completion_body)

	_build_settings(root)

	# The HUD is read-only. Every Control ignores the mouse so a panel can never
	# swallow a click or a mouse-motion event that belongs to the camera.
	_make_ignored(root)


## First-person view settings (Esc). Keyboard only, so the game never has to
## show a cursor during play; the overlay itself is still mouse-transparent.
func _build_settings(root: Control) -> void:
	settings_root = Control.new()
	settings_root.name = "ViewSettings"
	settings_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_root.visible = false
	root.add_child(settings_root)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.035, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_root.add_child(dim)
	var panel: PanelContainer = _panel(Color(0.02, 0.05, 0.08, 0.92), CYAN, 2, 6)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	panel.position = Vector2(-310.0, -150.0)
	settings_root.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title: Label = _label("视角设置 · 已暂停", 26, TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	settings_sensitivity = _label("灵敏度 0.126 °/px", 18, CYAN)
	settings_sensitivity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(settings_sensitivity)
	settings_invert = _label("Y 轴反转：关闭（默认）", 18, CYAN)
	settings_invert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(settings_invert)
	var hint: Label = _label("[  ] 调整灵敏度    ·    Y 切换 Y 轴反转    ·    Esc 继续游戏\n鼠标始终由玩家控制，不会自动回正。", 15, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _make_ignored(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_make_ignored(child)


func set_objective(text: String) -> void:
	if objective_label != null:
		objective_label.text = text


func show_prompt(text: String) -> void:
	if prompt_label == null:
		return
	prompt_label.text = text
	prompt_label.visible = not text.is_empty()


func show_subtitle(speaker: String, text: String, duration: float = 3.8) -> void:
	if subtitle_panel == null:
		return
	if _subtitle_tween != null:
		_subtitle_tween.kill()
	speaker_label.text = speaker
	subtitle_label.text = text
	subtitle_panel.visible = true
	subtitle_panel.modulate.a = 0.0
	_subtitle_tween = create_tween()
	_subtitle_tween.tween_property(subtitle_panel, "modulate:a", 1.0, 0.18)
	_subtitle_tween.tween_interval(maxf(duration, 0.6))
	_subtitle_tween.tween_property(subtitle_panel, "modulate:a", 0.0, 0.35)
	_subtitle_tween.tween_callback(func() -> void: subtitle_panel.visible = false)


func show_memory_title(text: String, duration: float = 3.4) -> void:
	if title_label == null:
		return
	if _title_tween != null:
		_title_tween.kill()
	title_label.text = text
	title_label.modulate.a = 0.0
	_title_tween = create_tween()
	_title_tween.tween_property(title_label, "modulate:a", 1.0, 0.35)
	_title_tween.tween_interval(duration)
	_title_tween.tween_property(title_label, "modulate:a", 0.0, 0.8)


func show_toast(text: String, duration: float = 3.0) -> void:
	if toast_label == null:
		return
	if _toast_tween != null:
		_toast_tween.kill()
	toast_label.text = text
	toast_label.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast_label, "modulate:a", 0.95, 0.2)
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.45)


## High-priority banner for the resonance warning and the shock. It never
## blocks input and it is not a permanent HUD widget.
func show_warning(text: String, duration: float = 3.0) -> void:
	if warning_panel == null:
		return
	if _warning_tween != null:
		_warning_tween.kill()
	warning_label.text = text
	warning_panel.visible = true
	warning_panel.modulate.a = 0.0
	_warning_tween = create_tween()
	_warning_tween.tween_property(warning_panel, "modulate:a", 1.0, 0.16)
	_warning_tween.tween_interval(maxf(duration, 0.4))
	_warning_tween.tween_property(warning_panel, "modulate:a", 0.0, 0.35)
	_warning_tween.tween_callback(func() -> void: warning_panel.visible = false)


func show_completion(body_text: String) -> void:
	completion_body.text = body_text
	completion_root.visible = true
	completion_root.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(completion_root, "modulate:a", 1.0, 0.6)


func hide_completion() -> void:
	completion_root.visible = false


func set_controls_visible(value: bool) -> void:
	controls_label.visible = value


func show_view_settings(open: bool, sensitivity: float, invert: bool) -> void:
	if settings_root == null:
		return
	settings_root.visible = open
	if settings_sensitivity != null:
		settings_sensitivity.text = "灵敏度 %.3f °/px" % rad_to_deg(sensitivity)
	if settings_invert != null:
		settings_invert.text = "Y 轴反转：%s" % ("开启" if invert else "关闭（默认）")

