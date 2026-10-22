extends CanvasLayer

# WinchHud - two modes:
#   normal: objective, one status line, a tension strip, the current prompt
#   debug (F3): the full instrument panel with numbers, angle dial, fps
#
# The normal mode deliberately withholds degrees and metres: alignment is read
# from the physical marks on the rail and receiver, not from a number.

var rig: Node3D
var player: Node3D

var normal_panel: PanelContainer
var debug_panel: PanelContainer
var title_label: Label
var objective_label: Label
var status_label: Label
var advice_label: Label
var prompt_label: Label
var feedback_label: Label
var tension_bar: Control
var debug_label: Label
var fps_label: Label
var help_panel: Control

var _feedback_time: float = -99.0
var _feedback_tone: String = "info"
var _advice_time: float = -99.0
var _debug_visible: bool = false
var _fps_samples: Array[float] = []
var _last_state: String = ""
var _state_time: float = 0.0

const C_GOOD := Color("#7fe3a4")
const C_WARN := Color("#ffc37b")
const C_BAD := Color("#ff8a7a")
const C_DIM := Color("#9fb6bd")
const C_CYAN := Color("#7fd8ff")
const C_WHITE := Color("#eaf6f8")

func _ready() -> void:
	layer = 10
	_build()

func _panel_style(alpha: float = 0.86) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.065, alpha)
	style.border_color = Color(0.35, 0.62, 0.72, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style

func _build() -> void:
	var root: Control = Control.new()
	root.name = "HudRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_normal_panel(root)
	_build_debug_panel(root)
	_build_prompt_and_feedback(root)
	help_panel = _make_help(root)
	_build_toggle_hint(root)

func _build_normal_panel(root: Control) -> void:
	normal_panel = PanelContainer.new()
	normal_panel.name = "NormalPanel"
	normal_panel.position = Vector2(22, 22)
	normal_panel.custom_minimum_size = Vector2(392, 0)
	normal_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	normal_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(normal_panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	normal_panel.add_child(box)

	title_label = _label(box, "RESONANCE 03 · 绞盘轨道复位", 13, C_CYAN)
	title_label.add_theme_color_override("font_color", Color(0.45, 0.78, 0.86))

	objective_label = _label(box, "目标", 19, C_WHITE)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.custom_minimum_size = Vector2(360, 0)

	status_label = _label(box, "", 16, C_DIM)

	var tension_row: HBoxContainer = HBoxContainer.new()
	tension_row.add_theme_constant_override("separation", 8)
	box.add_child(tension_row)
	var tension_caption: Label = _label(tension_row, "张力", 13, C_DIM)
	tension_caption.custom_minimum_size = Vector2(30, 0)
	tension_bar = Control.new()
	tension_bar.name = "TensionBar"
	tension_bar.custom_minimum_size = Vector2(266, 14)
	tension_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tension_bar.draw.connect(_draw_tension)
	tension_row.add_child(tension_bar)
	var tension_state: Label = Label.new()
	tension_state.name = "TensionState"
	tension_state.text = ""
	tension_state.add_theme_font_size_override("font_size", 13)
	tension_state.add_theme_color_override("font_color", C_DIM)
	tension_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tension_row.add_child(tension_state)

	advice_label = _label(box, "", 15, C_WARN)
	advice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	advice_label.custom_minimum_size = Vector2(360, 0)
	advice_label.visible = false

func _build_debug_panel(root: Control) -> void:
	debug_panel = PanelContainer.new()
	debug_panel.name = "DebugPanel"
	debug_panel.position = Vector2(22, 22)
	debug_panel.custom_minimum_size = Vector2(410, 0)
	debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_panel.add_theme_stylebox_override("panel", _panel_style(0.92))
	debug_panel.visible = false
	root.add_child(debug_panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	debug_panel.add_child(box)
	_label(box, "DEBUG · F3 返回正常界面", 13, C_CYAN)
	debug_label = _label(box, "", 15, Color(0.82, 0.92, 0.95))
	debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_label.custom_minimum_size = Vector2(380, 0)

	fps_label = Label.new()
	fps_label.text = ""
	fps_label.add_theme_font_size_override("font_size", 12)
	fps_label.add_theme_color_override("font_color", C_DIM)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fps_label)
	fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fps_label.offset_left = -180.0
	fps_label.offset_right = -20.0
	fps_label.offset_top = 22.0
	fps_label.offset_bottom = 44.0
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.visible = false

func _build_prompt_and_feedback(root: Control) -> void:
	feedback_label = _label(root, "", 19, C_GOOD)
	feedback_label.name = "Feedback"
	feedback_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	feedback_label.offset_left = -340.0
	feedback_label.offset_right = 340.0
	feedback_label.offset_top = 104.0
	feedback_label.offset_bottom = 148.0
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	prompt_label = _label(root, "", 18, Color("#ffffff"))
	prompt_label.name = "Prompt"
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_left = -360.0
	prompt_label.offset_right = 360.0
	prompt_label.offset_top = -86.0
	prompt_label.offset_bottom = -46.0
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_toggle_hint(root: Control) -> void:
	var hint: Label = _label(root, "F1 操作 · F3 调试 · Esc 暂停", 12, Color(0.45, 0.55, 0.6))
	hint.name = "KeyHint"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 22.0
	hint.offset_right = 300.0
	hint.offset_top = -30.0
	hint.offset_bottom = -8.0

func _make_help(root: Control) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "HelpPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	panel.offset_left = 22.0
	panel.offset_right = 402.0
	panel.offset_top = -190.0
	panel.offset_bottom = 190.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(0.94))
	panel.visible = false
	root.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	_label(box, "操作", 17, C_CYAN)
	_label(box, "WASD 移动 · Shift 跑 · 鼠标观察", 14, C_DIM)
	_label(box, "E 挂缆绳 / 接管绞盘 / 插锁定销", 14, C_DIM)
	_label(box, "接管绞盘后：W 收缆 · S 放线", 14, C_DIM)
	_label(box, "Shift 慢速微调 · 空格 刹车", 14, C_DIM)
	_label(box, "Q 松缆绳 · F 装锁定销 · R 重置", 14, C_DIM)
	_label(box, "F1 帮助 · F3 调试信息 · Esc 暂停", 14, C_DIM)
	return panel

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func toggle_help() -> void:
	help_panel.visible = not help_panel.visible

func toggle_debug() -> void:
	_debug_visible = not _debug_visible
	debug_panel.visible = _debug_visible
	fps_label.visible = _debug_visible
	normal_panel.visible = not _debug_visible

func show_feedback(text: String, tone: String) -> void:
	_feedback_time = Time.get_ticks_msec() / 1000.0
	_feedback_tone = tone
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", _tone_color(tone))

func set_prompt(text: String) -> void:
	prompt_label.text = text

func _process(delta: float) -> void:
	if rig == null:
		return
	var snap: Dictionary = rig.call("rig_snapshot") as Dictionary
	if snap.is_empty():
		return
	var winch: Dictionary = snap.get("winch", {}) as Dictionary
	var rail: Dictionary = snap.get("rail", {}) as Dictionary
	var lock: Dictionary = snap.get("lock", {}) as Dictionary

	_update_objective(winch, rail, lock)
	_update_status(winch, rail)
	_update_advice(winch, rail, lock, delta)
	tension_bar.queue_redraw()
	_update_timers()
	if _debug_visible:
		_update_debug(snap, winch, rail, lock, delta)

func _update_objective(winch: Dictionary, rail: Dictionary, lock: Dictionary) -> void:
	var text: String = ""
	if bool(lock.get("locked", false)):
		text = "轨道已复位。按 R 重置，可以再来一次。"
	elif bool(winch.get("attached", false)) == false:
		text = "找到断裂轨道，把缆绳挂到吊耳上。"
	elif bool(rail.get("jammed", false)):
		text = "回到绞盘，按 W 收缆，把轨道从碎石里拉出来。"
	elif absf(float(rail.get("angle_deg", 0.0))) > 1.2:
		text = "调整轨道，让端部回到接收架的复位线。"
	else:
		text = "对位完成。去锁定座按 E 插入锁定销。"
	objective_label.text = text

func _update_status(winch: Dictionary, rail: Dictionary) -> void:
	var text: String = ""
	var color: Color = C_DIM
	if not bool(winch.get("attached", false)):
		text = "缆绳未连接"
	elif bool(rail.get("in_band", false)):
		text = "已进入锁定范围"
		color = C_GOOD
	elif bool(winch.get("stalled", false)):
		text = "离合器打滑 · 轨道没有动"
		color = C_BAD
	elif bool(rail.get("jammed", false)):
		text = "轨道卡死 · 绞盘正在吃力"
		color = C_WARN
	elif float(winch.get("tension_ratio", 0.0)) >= 0.86:
		text = "张力接近上限"
		color = C_WARN
	elif absf(float(rail.get("angular_velocity", 0.0))) > 0.02:
		text = "轨道正在移动"
		color = C_GOOD
	else:
		text = "轨道偏离复位线"
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)

func _update_advice(winch: Dictionary, rail: Dictionary, lock: Dictionary, delta: float) -> void:
	var state_key: String = "%s|%s|%s" % [str(winch.get("anchor_name", "")), str(rail.get("jammed", false)), str(winch.get("stalled", false))]
	if state_key != _last_state:
		_last_state = state_key
		_state_time = 0.0
	else:
		_state_time += delta

	var text: String = ""
	var tone: Color = C_WARN
	if bool(lock.get("locked", false)):
		text = ""
	elif bool(winch.get("stalled", false)) and bool(rail.get("jammed", false)) and _state_time > 1.0:
		var anchor_name: String = str(winch.get("anchor_name", ""))
		if anchor_name.contains("中段"):
			text = "这个连接点力臂不够，绞盘在打滑。轨道另一端还有一个吊耳。"
		else:
			text = "绞盘在打滑，轨道几乎没有动。换一个连接点试试。"
	elif float(rail.get("angle_deg", 0.0)) < -1.2:
		text = "拉过头了。按 S 放线，让轨道荡回复位线。"
	elif bool(rail.get("in_band", false)) and not bool(rail.get("settled", false)):
		text = "等轨道停稳，再插入锁定销。"
	elif bool(winch.get("attached", false)) and not bool(rail.get("jammed", false)) and not bool(rail.get("in_band", false)):
		text = "收缆让轨道靠近复位线；过头了就按 S 放线。"
	if text.is_empty():
		advice_label.visible = false
		return
	advice_label.visible = true
	advice_label.text = text
	advice_label.add_theme_color_override("font_color", tone)

func _update_debug(snap: Dictionary, winch: Dictionary, rail: Dictionary, lock: Dictionary, delta: float) -> void:
	var state: String = str(snap.get("state", ""))
	var angle: float = float(rail.get("angle_deg", 0.0))
	var lateral: float = float(rail.get("lateral_error", 0.0))
	var tension: float = float(winch.get("tension", 0.0))
	var ratio: float = float(winch.get("tension_ratio", 0.0))
	var max_force: float = 3200.0
	if rig.get("winch") != null:
		max_force = float((rig.get("winch") as Node3D).get("max_force"))
	debug_label.text = "\n".join([
		"任务：%s  完成：%s ×%d" % [state, str(snap.get("completed", false)), int(snap.get("completions", 0))],
		"轨道角：%+.2f°  端部偏差：%.2f m" % [angle, lateral],
		"缆绳：%.2f m  张力：%.0f / %.0f N (%.0f%%)" % [float(winch.get("free_length", 0.0)), tension, max_force, ratio * 100.0],
		"模式：%s  刹车：%s  打滑：%s" % [str(winch.get("mode", "")), str(winch.get("brake", false)), str(winch.get("stalled", false))],
		"卡滞：%s  对位：%s  可锁：%s  稳定：%s" % [str(rail.get("jammed", false)), str(rail.get("in_band", false)), str(rail.get("lockable", false)), str(rail.get("settled", false))],
		"锚点：%s" % str(winch.get("anchor_name", "无")),
	])
	_fps_samples.append(delta)
	if _fps_samples.size() > 60:
		_fps_samples.pop_front()
	var total: float = 0.0
	for sample: float in _fps_samples:
		total += sample
	var average: float = total / float(maxi(_fps_samples.size(), 1))
	fps_label.text = "%.0f fps · %.1f ms" % [1.0 / maxf(average, 0.0001), average * 1000.0]

func _draw_tension() -> void:
	if tension_bar == null:
		return
	var width: float = tension_bar.size.x
	var height: float = tension_bar.size.y
	var ratio: float = 0.0
	if rig != null and rig.get("winch") != null:
		ratio = float(rig.call("tension_state").get("tension_ratio", 0.0))
	tension_bar.draw_rect(Rect2(0, 0, width, height), Color(0.05, 0.07, 0.09, 0.9))
	tension_bar.draw_rect(Rect2(1, 1, width * 0.60 - 1, height - 2), Color(0.22, 0.55, 0.58, 0.75))
	tension_bar.draw_rect(Rect2(width * 0.60, 1, width * 0.26, height - 2), Color(0.78, 0.55, 0.18, 0.8))
	tension_bar.draw_rect(Rect2(width * 0.86, 1, width * 0.14 - 1, height - 2), Color(0.85, 0.28, 0.22, 0.85))
	var needle: float = clampf(ratio, 0.0, 1.0) * width
	tension_bar.draw_rect(Rect2(needle - 1.5, 0, 3, height), Color(0.95, 0.98, 1.0, 0.95))
	var state_text: String = "松弛"
	if ratio >= 0.86:
		state_text = "过载"
	elif ratio >= 0.60:
		state_text = "偏高"
	elif ratio >= 0.15:
		state_text = "正常"
	var label: Label = tension_bar.get_parent().get_node_or_null("TensionState") as Label
	if label != null:
		label.text = state_text
		label.add_theme_color_override("font_color", C_BAD if ratio >= 0.86 else (C_WARN if ratio >= 0.60 else C_DIM))

func _update_timers() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _feedback_time > 5.0:
		feedback_label.text = ""

func _tone_color(tone: String) -> Color:
	match tone:
		"error":
			return C_BAD
		"warn":
			return C_WARN
		"ok", "success":
			return C_GOOD
		_:
			return C_DIM
