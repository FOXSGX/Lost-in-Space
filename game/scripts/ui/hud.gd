class_name GameHud
extends CanvasLayer

## Diegetic-first HUD: the world carries the balance feedback, the HUD only
## carries interaction prompts, objectives, subtitles and system messages.

signal help_toggled(visible: bool)

var font: SystemFont
var root_control: Control
var crosshair: Crosshair
var objective_panel: PanelContainer
var objective_label: Label
var objective_title: Label
var prompt_panel: PanelContainer
var prompt_label: Label
var subtitle_panel: PanelContainer
var subtitle_speaker: Label
var subtitle_text: Label
var toast_label: Label
var title_layer: Control
var title_label: Label
var title_sub: Label
var help_panel: PanelContainer
var pause_panel: Control
var end_panel: Control
var end_title: Label
var end_body: Label
var end_hint: Label
var fade_rect: ColorRect
var debug_label: Label
var alert_panel: PanelContainer
var alert_label: Label
var crew_panel: PanelContainer
var crew_title: Label
var crew_rows: Label
var crew_hint: Label
var net_status: Label
var flash_rect: ColorRect
var debug_visible: bool = false
var help_visible: bool = false
var paused: bool = false
var _alert_time: float = 0.0
var _flash_time: float = 0.0
var _crew_refresh: float = 0.0
var _subtitle_queue: Array[Dictionary] = []
var _subtitle_time: float = 0.0
var _subtitle_total: float = 0.0
var _toast_time: float = 0.0

const BG := Color(0.035, 0.085, 0.105, 0.82)
const BORDER := Color(0.28, 0.72, 0.80, 0.65)
const ACCENT := Color(0.42, 0.94, 1.0, 1.0)
const WARM := Color(1.0, 0.72, 0.32, 1.0)
const TEXT := Color(0.88, 0.96, 1.0, 1.0)
const MUTED := Color(0.58, 0.70, 0.76, 1.0)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.hinting = TextServer.HINTING_LIGHT
	_build()


func _style(bg: Color = BG, border: Color = BORDER, border_width: int = 1) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = border_width
	sb.border_width_top = border_width
	sb.border_width_right = border_width
	sb.border_width_bottom = border_width
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _label(text: String, size: int, color: Color = TEXT, bold: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	if bold:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _build() -> void:
	root_control = Control.new()
	root_control.name = "HudRoot"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	crosshair = Crosshair.new()
	crosshair.name = "Crosshair"
	root_control.add_child(crosshair)

	objective_panel = PanelContainer.new()
	objective_panel.name = "ObjectivePanel"
	objective_panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.075, 0.095, 0.72), Color(0.24, 0.62, 0.70, 0.55)))
	root_control.add_child(objective_panel)
	objective_panel.anchor_left = 0.0
	objective_panel.anchor_top = 0.0
	objective_panel.anchor_right = 0.0
	objective_panel.anchor_bottom = 0.0
	objective_panel.offset_left = 24
	objective_panel.offset_top = 20
	objective_panel.offset_right = 468
	objective_panel.offset_bottom = 116
	var obj_vbox: VBoxContainer = VBoxContainer.new()
	obj_vbox.add_theme_constant_override("separation", 2)
	objective_panel.add_child(obj_vbox)
	objective_title = _label("当前目标", 13, Color(0.45, 0.85, 0.90, 1.0))
	obj_vbox.add_child(objective_title)
	objective_label = _label("进入地心设施", 18, TEXT)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.custom_minimum_size = Vector2(396, 0)
	obj_vbox.add_child(objective_label)

	prompt_panel = PanelContainer.new()
	prompt_panel.name = "PromptPanel"
	prompt_panel.add_theme_stylebox_override("panel", _style(Color(0.04, 0.10, 0.12, 0.86), ACCENT, 1))
	prompt_panel.visible = false
	root_control.add_child(prompt_panel)
	prompt_label = _label("", 19, Color(0.95, 0.98, 1.0))
	prompt_panel.add_child(prompt_label)
	prompt_panel.anchor_left = 0.5
	prompt_panel.anchor_right = 0.5
	prompt_panel.anchor_top = 1.0
	prompt_panel.anchor_bottom = 1.0
	prompt_panel.offset_left = -320
	prompt_panel.offset_right = 320
	prompt_panel.offset_top = -158
	prompt_panel.offset_bottom = -104
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	subtitle_panel = PanelContainer.new()
	subtitle_panel.name = "SubtitlePanel"
	subtitle_panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.05, 0.06, 0.58), Color(0.25, 0.55, 0.62, 0.35)))
	subtitle_panel.visible = false
	root_control.add_child(subtitle_panel)
	subtitle_panel.anchor_left = 0.5
	subtitle_panel.anchor_right = 0.5
	subtitle_panel.anchor_top = 1.0
	subtitle_panel.anchor_bottom = 1.0
	subtitle_panel.offset_left = -430
	subtitle_panel.offset_right = 430
	subtitle_panel.offset_top = -286
	subtitle_panel.offset_bottom = -192
	var sub_vbox: VBoxContainer = VBoxContainer.new()
	sub_vbox.add_theme_constant_override("separation", 4)
	subtitle_panel.add_child(sub_vbox)
	subtitle_speaker = _label("", 14, ACCENT)
	sub_vbox.add_child(subtitle_speaker)
	subtitle_text = _label("", 21, TEXT)
	subtitle_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_text.custom_minimum_size = Vector2(780, 0)
	sub_vbox.add_child(subtitle_text)

	toast_label = _label("", 18, WARM)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.visible = false
	root_control.add_child(toast_label)
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 0.0
	toast_label.anchor_bottom = 0.0
	toast_label.offset_left = -420
	toast_label.offset_right = 420
	toast_label.offset_top = 100
	toast_label.offset_bottom = 138

	debug_label = _label("", 13, Color(0.65, 1.0, 0.8, 1.0))
	debug_label.visible = false
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.add_theme_constant_override("outline_size", 3)
	root_control.add_child(debug_label)
	debug_label.anchor_left = 0.55
	debug_label.anchor_right = 1.0
	debug_label.anchor_top = 0.0
	debug_label.anchor_bottom = 0.0
	debug_label.offset_top = 16
	debug_label.offset_right = -22
	debug_label.offset_left = 0
	debug_label.offset_bottom = 300

	_build_title()
	_build_help()
	_build_coop()
	_build_pause()
	_build_end()

	fade_rect = ColorRect.new()
	fade_rect.name = "Fade"
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(fade_rect)
	root_control.move_child(end_panel, root_control.get_child_count() - 1)


func _build_title() -> void:
	title_layer = Control.new()
	title_layer.name = "TitleCard"
	title_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(title_layer)
	var band: ColorRect = ColorRect.new()
	band.color = Color(0.01, 0.03, 0.04, 0.55)
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_layer.add_child(band)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.42
	vbox.anchor_bottom = 0.42
	vbox.offset_left = -430
	vbox.offset_right = 430
	vbox.offset_top = -100
	vbox.offset_bottom = 120
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	title_layer.add_child(vbox)
	var kicker: Label = _label("RESONANCE 05  ·  共振星", 16, ACCENT)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(kicker)
	title_label = _label("地心的回声", 58, Color(0.92, 0.99, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)
	title_sub = _label("", 20, Color(0.72, 0.86, 0.90))
	title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_sub.custom_minimum_size = Vector2(780, 0)
	vbox.add_child(title_sub)


func _build_help() -> void:
	help_panel = PanelContainer.new()
	help_panel.name = "HelpPanel"
	help_panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.06, 0.075, 0.92), BORDER, 1))
	help_panel.visible = false
	root_control.add_child(help_panel)
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.anchor_left = 0.5
	help_panel.anchor_right = 0.5
	help_panel.anchor_top = 0.5
	help_panel.anchor_bottom = 0.5
	help_panel.offset_left = -330
	help_panel.offset_right = 330
	help_panel.offset_top = -230
	help_panel.offset_bottom = 230
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	help_panel.add_child(vbox)
	vbox.add_child(_label("操作说明", 24, ACCENT))
	vbox.add_child(_label("W A S D    移动          SHIFT  疾跑          SPACE  跳跃", 17))
	vbox.add_child(_label("鼠标        视角          E      交互 / 抓住 / 松开", 17))
	vbox.add_child(_label("W / S       操作机械手柄、推动闸门", 17))
	vbox.add_child(_label("F1  帮助      F3  调试信息      R  回到检查点", 17))
	vbox.add_child(_label("F5  从头开始      ESC  暂停 / 释放鼠标", 17))
	var hint: Label = _label("机械反馈优先于数字：观察核心摆幅、配重位置和机械指针。", 16, WARM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(600, 0)
	vbox.add_child(hint)
	var close: Label = _label("再次按 F1 关闭", 14, MUTED)
	close.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(close)


func _build_pause() -> void:
	pause_panel = Control.new()
	pause_panel.name = "PausePanel"
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.visible = false
	root_control.add_child(pause_panel)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.01, 0.025, 0.03, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(bg)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -360
	vbox.offset_right = 360
	vbox.offset_top = -200
	vbox.offset_bottom = 200
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	pause_panel.add_child(vbox)
	var t: Label = _label("已暂停", 40, TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(t)
	var hint: Label = _label("ESC 继续        R 回到最近检查点        F5 从头开始", 18, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	var hint2: Label = _label("Q 退出游戏", 16, MUTED)
	hint2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint2)
	var tip: Label = _label("提示：松开手柄后配重仍有惯性；反向推动可以修正过冲。", 16, WARM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tip)


func _build_end() -> void:
	end_panel = Control.new()
	end_panel.name = "EndPanel"
	end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.visible = false
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(end_panel)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.01, 0.02, 0.03, 0.0)
	bg.name = "EndBg"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_panel.add_child(bg)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -460
	vbox.offset_right = 460
	vbox.offset_top = -250
	vbox.offset_bottom = 250
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	end_panel.add_child(vbox)
	var kicker: Label = _label("RESONANCE 05  ·  完成", 15, ACCENT)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(kicker)
	end_title = _label("地心的回声", 48, Color(0.94, 0.99, 1.0))
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(end_title)
	end_body = _label("", 20, Color(0.82, 0.92, 0.95))
	end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_body.custom_minimum_size = Vector2(850, 0)
	vbox.add_child(end_body)
	end_hint = _label("F5 重新开始", 17, WARM)
	end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(end_hint)


func set_objective(text: String) -> void:
	objective_label.text = text


# ---------------------------------------------------------------------------
# Co-op panels: crew duty board mirror + alarm banner + impact flash
# ---------------------------------------------------------------------------

func _build_coop() -> void:
	alert_panel = PanelContainer.new()
	alert_panel.name = "AlertPanel"
	alert_panel.add_theme_stylebox_override("panel", _style(Color(0.20, 0.04, 0.03, 0.90), Color(1.0, 0.42, 0.18, 0.95), 2))
	alert_panel.visible = false
	root_control.add_child(alert_panel)
	alert_panel.anchor_left = 0.5
	alert_panel.anchor_right = 0.5
	alert_panel.anchor_top = 0.0
	alert_panel.anchor_bottom = 0.0
	alert_panel.offset_left = -280
	alert_panel.offset_right = 280
	alert_panel.offset_top = 22
	alert_panel.offset_bottom = 80
	alert_label = _label("", 24, Color(1.0, 0.86, 0.70))
	alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alert_panel.add_child(alert_label)

	crew_panel = PanelContainer.new()
	crew_panel.name = "CrewPanel"
	crew_panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.075, 0.095, 0.72), Color(0.24, 0.62, 0.70, 0.55)))
	root_control.add_child(crew_panel)
	crew_panel.anchor_left = 1.0
	crew_panel.anchor_right = 1.0
	crew_panel.anchor_top = 0.0
	crew_panel.anchor_bottom = 0.0
	crew_panel.offset_left = -372
	crew_panel.offset_right = -22
	crew_panel.offset_top = 116
	crew_panel.offset_bottom = 300
	var crew_box: VBoxContainer = VBoxContainer.new()
	crew_box.add_theme_constant_override("separation", 3)
	crew_panel.add_child(crew_box)
	crew_title = _label("全员参与", 15, ACCENT)
	crew_box.add_child(crew_title)
	crew_rows = _label("", 15, TEXT)
	crew_rows.custom_minimum_size = Vector2(320, 0)
	crew_box.add_child(crew_rows)
	crew_hint = _label("", 13, WARM)
	crew_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crew_hint.custom_minimum_size = Vector2(320, 0)
	crew_box.add_child(crew_hint)

	net_status = _label("", 13, MUTED)
	net_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	net_status.visible = false
	root_control.add_child(net_status)
	net_status.anchor_left = 0.35
	net_status.anchor_right = 1.0
	net_status.anchor_top = 1.0
	net_status.anchor_bottom = 1.0
	net_status.offset_left = 0
	net_status.offset_right = -22
	net_status.offset_top = -34
	net_status.offset_bottom = -10

	flash_rect = ColorRect.new()
	flash_rect.name = "ImpactFlash"
	flash_rect.color = Color(1.0, 0.22, 0.08, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(flash_rect)
	root_control.move_child(flash_rect, 0)


func show_alert(text: String, seconds: float = 3.0) -> void:
	if alert_label == null:
		return
	alert_label.text = text
	alert_panel.visible = true
	_alert_time = maxf(0.2, seconds)


func hide_alert() -> void:
	if alert_panel != null:
		alert_panel.visible = false
	_alert_time = 0.0


func shake(amount: float) -> void:
	# Deliberately NOT a camera shake: the world moves, the HUD only flashes.
	if flash_rect == null:
		return
	_flash_time = 0.45
	flash_rect.color = Color(1.0, 0.22, 0.08, clampf(0.10 + amount * 0.22, 0.0, 0.34))


func update_crew(text: String, hint: String = "", title: String = "") -> void:
	if crew_rows == null:
		return
	crew_rows.text = text
	crew_hint.text = hint
	if title != "":
		crew_title.text = title
	crew_panel.visible = text != ""


func update_net_status(text: String, visible: bool = true) -> void:
	if net_status == null:
		return
	net_status.text = text
	net_status.visible = visible && text != ""


func _process_coop(delta: float) -> void:
	if _alert_time > 0.0:
		_alert_time -= delta
		if _alert_time <= 0.0 and alert_panel != null:
			alert_panel.visible = false
	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		if flash_rect != null:
			var a: float = clampf(_flash_time / 0.45, 0.0, 1.0) * 0.30
			flash_rect.color = Color(1.0, 0.22, 0.08, a)


func set_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_panel.visible = text != ""
	crosshair.set_active(text != "")


func subtitle(text: String, speaker: String = "", duration: float = 4.0) -> void:
	_subtitle_queue.append({"text": text, "speaker": speaker, "duration": duration})


func clear_subtitles() -> void:
	_subtitle_queue.clear()
	_subtitle_time = 0.0
	subtitle_panel.visible = false


func toast(text: String, duration: float = 3.0) -> void:
	toast_label.text = text
	toast_label.visible = true
	_toast_time = duration


func show_title(subtitle_text: String, seconds: float = 6.0) -> void:
	title_sub.text = subtitle_text
	title_layer.visible = true
	title_layer.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_interval(maxf(1.0, seconds - 1.4))
	tween.tween_property(title_layer, "modulate:a", 0.0, 1.2)
	tween.tween_callback(func() -> void: title_layer.visible = false)


func show_help(visible: bool) -> void:
	help_visible = visible
	help_panel.visible = visible


func show_pause(visible: bool) -> void:
	paused = visible
	pause_panel.visible = visible


func show_end(lines: String) -> void:
	end_panel.visible = true
	end_body.text = lines
	var bg: ColorRect = end_panel.get_node("EndBg") as ColorRect
	bg.color = Color(0.01, 0.02, 0.03, 0.0)
	var tween: Tween = create_tween()
	tween.tween_property(bg, "color:a", 0.88, 1.2)


func show_end_hidden() -> void:
	end_panel.visible = false
	var bg: ColorRect = end_panel.get_node_or_null("EndBg") as ColorRect
	if bg != null:
		bg.color = Color(0.01, 0.02, 0.03, 0.0)


func set_debug(visible: bool) -> void:
	debug_visible = visible
	debug_label.visible = visible
	toast("调试信息 " + ("开" if visible else "关"), 1.5)


func update_debug(lines: String) -> void:
	if debug_visible:
		debug_label.text = lines


func fade(alpha: float, duration: float = 0.8) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(fade_rect, "color:a", alpha, duration)


func _process(delta: float) -> void:
	_process_coop(delta)
	if _subtitle_time > 0.0:
		_subtitle_time -= delta
		if _subtitle_time <= 0.0:
			subtitle_panel.visible = false
			_subtitle_time = 0.0
	if _subtitle_time <= 0.0 and not _subtitle_queue.is_empty():
		var item: Dictionary = _subtitle_queue.pop_front() as Dictionary
		subtitle_speaker.text = str(item.get("speaker", ""))
		subtitle_speaker.visible = str(item.get("speaker", "")) != ""
		subtitle_text.text = str(item.get("text", ""))
		subtitle_panel.visible = true
		_subtitle_time = float(item.get("duration", 4.0))
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			toast_label.visible = false
