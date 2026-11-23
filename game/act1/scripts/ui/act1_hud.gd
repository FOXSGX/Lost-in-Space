class_name Act1Hud
extends CanvasLayer

var root: Control
var crosshair: Act1Crosshair
var _objective: Label
var _objective_sub: Label
var _status: Label
var _prompt_panel: ColorRect
var _prompt: Label
var _hint: Label
var _participation: Label
var _wind_value: Label
var _wind_bar: ProgressBar
var _pressure_bar: ProgressBar
var _pressure_tick: ColorRect
var _vent_hint: Label
var _pressure_fill_ok: StyleBoxFlat
var _pressure_fill_low: StyleBoxFlat
var _toast: Label
var _toast_time := 0.0
var _intro: Control
var _intro_title: Label
var _intro_sub: Label
var _intro_hint: Label
var _fade: ColorRect
var _fade_tween: Tween
var _vignette: ColorRect
var _debug: Label
var _font: SystemFont


func _ready() -> void:
	layer = 20
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	root = Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top()
	_build_prompt()
	_build_right()
	_build_toast()
	_build_intro()
	_build_fade()
	crosshair = Act1Crosshair.new()
	root.add_child(crosshair)


func _build_top() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.008, 0.022, 0.032, 0.72)
	backdrop.position = Vector2(22, 20)
	backdrop.size = Vector2(560, 112)
	root.add_child(backdrop)
	var accent := ColorRect.new()
	accent.color = Color(0.20, 0.74, 0.82, 0.9)
	accent.position = Vector2(22, 20)
	accent.size = Vector2(4, 112)
	root.add_child(accent)
	_objective = _label(Vector2(42, 30), Vector2(524, 35), 23, Color(0.92, 0.97, 1.0))
	_objective_sub = _label(Vector2(42, 68), Vector2(524, 28), 15, Color(0.55, 0.76, 0.82))
	var chapter := _label(Vector2(42, 100), Vector2(524, 22), 12, Color(0.94, 0.63, 0.26))
	chapter.text = "RESONANCE 01  /  THE SILENT MINING STATION"
	root.add_child(_objective)
	root.add_child(_objective_sub)
	root.add_child(chapter)
	_status = _label(Vector2(0, 0), Vector2(0, 0), 13, Color(0.66, 0.82, 0.86))
	root.add_child(_status)
	_status.position = Vector2(22, 142)
	_status.size = Vector2(600, 22)


func _build_prompt() -> void:
	_prompt_panel = ColorRect.new()
	_prompt_panel.color = Color(0.01, 0.028, 0.04, 0.88)
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.position = Vector2(-340, -118)
	_prompt_panel.size = Vector2(680, 66)
	root.add_child(_prompt_panel)
	_prompt = _label(Vector2(0, 0), Vector2(680, 36), 20, Color(1.0, 0.96, 0.86))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt)
	_hint = _label(Vector2(0, 36), Vector2(680, 22), 12, Color(0.50, 0.68, 0.73))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = "WASD 移动   SHIFT 冲刺   E 交互/按住   Q 松手   R 重置   ESC 鼠标"
	_prompt_panel.add_child(_hint)


func _build_right() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0.008, 0.022, 0.032, 0.68)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-300, 20)
	panel.size = Vector2(278, 172)
	root.add_child(panel)
	var title := _label(Vector2(0, 0), Vector2(250, 22), 13, Color(0.54, 0.78, 0.84))
	title.text = "通风系统  /  VENTILATION"
	title.position = Vector2(16, 10)
	panel.add_child(title)
	_wind_bar = ProgressBar.new()
	_wind_bar.position = Vector2(16, 40)
	_wind_bar.size = Vector2(244, 16)
	_wind_bar.max_value = 1.0
	_wind_bar.show_percentage = false
	panel.add_child(_wind_bar)
	_pressure_bar = ProgressBar.new()
	_pressure_bar.position = Vector2(16, 64)
	_pressure_bar.size = Vector2(244, 12)
	_pressure_bar.max_value = 1.0
	_pressure_bar.show_percentage = false
	_pressure_fill_ok = StyleBoxFlat.new()
	_pressure_fill_ok.bg_color = Color(0.24, 0.78, 0.72)
	_pressure_fill_low = StyleBoxFlat.new()
	_pressure_fill_low.bg_color = Color(0.92, 0.58, 0.22)
	_pressure_bar.add_theme_stylebox_override("fill", _pressure_fill_ok)
	panel.add_child(_pressure_bar)
	# 58% threshold marker: the machine, this marker and the launch gate all read
	# Act1Ventilation.PRESSURE_MIN, so the visible target is the real target.
	_pressure_tick = ColorRect.new()
	_pressure_tick.color = Color(1.0, 0.76, 0.32, 0.95)
	_pressure_tick.position = Vector2(16.0 + 244.0 * Act1Ventilation.PRESSURE_MIN - 1.0, 61.0)
	_pressure_tick.size = Vector2(2.0, 18.0)
	_pressure_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_pressure_tick)
	_wind_value = _label(Vector2(16, 80), Vector2(244, 34), 12, Color(0.72, 0.86, 0.89))
	panel.add_child(_wind_value)
	_vent_hint = _label(Vector2(16, 116), Vector2(244, 50), 12, Color(0.62, 0.82, 0.80))
	panel.add_child(_vent_hint)
	_participation = _label(Vector2(24, 0), Vector2(500, 140), 13, Color(0.86, 0.76, 0.48))
	_participation.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_participation.position = Vector2(24, -158)
	_participation.size = Vector2(540, 130)
	root.add_child(_participation)
	_debug = _label(Vector2(0, 0), Vector2(500, 60), 11, Color(0.48, 0.92, 0.55))
	_debug.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_debug.position = Vector2(-520, -80)
	_debug.size = Vector2(490, 64)
	_debug.visible = false
	root.add_child(_debug)


func _build_toast() -> void:
	_toast = _label(Vector2(0, 0), Vector2(760, 40), 18, Color(0.96, 0.86, 0.65))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-380, 70)
	_toast.size = Vector2(760, 44)
	_toast.modulate.a = 0.0
	root.add_child(_toast)


func _build_intro() -> void:
	_intro = Control.new()
	_intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_intro)
	var band := ColorRect.new()
	band.color = Color(0.005, 0.014, 0.020, 0.82)
	band.position = Vector2(0, 214)
	band.size = Vector2(1280, 274)
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.offset_top = 214
	band.offset_bottom = 488
	_intro.add_child(band)
	_intro_title = _label(Vector2(0, 260), Vector2(1280, 66), 42, Color(0.90, 0.95, 1.0))
	_intro_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_title.text = "K-17  ·  沉默矿区"
	_intro.add_child(_intro_title)
	_intro_sub = _label(Vector2(0, 326), Vector2(1280, 30), 20, Color(0.53, 0.78, 0.84))
	_intro_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_sub.text = "无人值守的工业矿站。恢复电源，启动通风，把矿车开到深层矿区。"
	_intro.add_child(_intro_sub)
	_intro_hint = _label(Vector2(0, 384), Vector2(1280, 55), 15, Color(0.85, 0.72, 0.44))
	_intro_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_hint.text = "单人可完成全部流程  ·  1–4 人合作时，每名玩家都需要在至少两个工序里做出真实改变\nE 交互  ·  按住 E 推门/推车  ·  W/S 推拉  ·  Q 松手  ·  R 重置"
	_intro.add_child(_intro_hint)


func _build_fade() -> void:
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)


func _label(pos: Vector2, sz: Vector2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = sz
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func set_objective(text: String, sub: String = "") -> void:
	_objective.text = text
	_objective_sub.text = sub


func set_prompt(text: String) -> void:
	_prompt.text = text
	_prompt_panel.visible = text != ""
	crosshair.focused = text != ""


func set_prompt_visible(value: bool) -> void:
	_prompt_panel.visible = value


func set_status(text: String) -> void:
	_status.text = text


func set_wind(value: float, pressure: float, damper: float, running: bool, emergency: bool,
		governor := 0.55, test_seconds := 0.0, complete := false, damper_open := false,
		fan_prepped := false, power_ready := false) -> void:
	_wind_bar.value = value
	_pressure_bar.value = pressure
	_pressure_bar.add_theme_stylebox_override("fill",
		_pressure_fill_ok if pressure > Act1Ventilation.PRESSURE_MIN else _pressure_fill_low)
	var state := "待机"
	if emergency:
		state = "紧急停机"
	elif running:
		state = "运行"
	var target := int(round(Act1Ventilation.PRESSURE_MIN * 100.0))
	_wind_value.text = "风机 %s · 转速 %3d%% · 调速器 %3d%%\n风压 %3d%% / ≥%d%% · 风门 %3d%%" % [
		state, int(round(value * 100.0)), int(round(governor * 100.0)),
		int(round(pressure * 100.0)), target, int(round(damper * 100.0))
	]
	_vent_hint.text = _vent_hint_text(value, pressure, damper, running, emergency,
		governor, test_seconds, complete, damper_open, fan_prepped, power_ready)
	_vent_hint.add_theme_color_override("font_color", _vent_hint_color(pressure, running, emergency,
		complete, damper_open))


## One-line state + reason + recovery. The HUD never computes the pressure test
## itself: `complete` and `test_seconds` come from Act1Ventilation on the host or
## from its snapshots on a client.
##
## `fan_prepped` (rotor lock pulled + coupling engaged) and `power_ready` let the
## idle line say why the start handle does nothing: the rotor can be serviced
## without auxiliary power, but the fan cannot run without it.
func _vent_hint_text(value: float, pressure: float, damper: float, running: bool, emergency: bool,
		governor: float, test_seconds: float, complete: bool, damper_open: bool,
		fan_prepped := false, power_ready := false) -> String:
	if emergency:
		return "紧急停机中 · 按 E 解除后才能建立风压"
	if not running:
		if fan_prepped and not power_ready:
			return "检修就绪（锁已拔·联轴器已接）\n控制回路未得电 · 先恢复辅助电源再启动"
		if power_ready:
			return "风机未启动 · 在控制廊拉动主启动手柄"
		return "风机未启动 · 先恢复辅助电源，再拉控制廊的主启动手柄"
	if pressure <= Act1Ventilation.PRESSURE_MIN:
		if governor > Act1Ventilation.PRESSURE_MIN and value + 0.01 < governor:
			return "风机升速中：%d%% → %d%%\n风压 %d%%，等待转速建立" % [
				int(round(value * 100.0)), int(round(governor * 100.0)), int(round(pressure * 100.0))]
		if not damper_open:
			return "主风道未开（风门 %d%%）\n按 E 打开风门才能建立压力" % int(round(damper * 100.0))
		if damper < 0.98:
			return "主风道正在打开（%d%%）\n风压会随风门到位上升" % int(round(damper * 100.0))
		var nxt := Act1Ventilation.next_governor_value(governor)
		if nxt > Act1Ventilation.PRESSURE_MIN:
			return "风压不足：%d%% < %d%%\n按 E 调速器 %d%% → %d%%（保持主风道）" % [
				int(round(pressure * 100.0)), int(round(Act1Ventilation.PRESSURE_MIN * 100.0)),
				int(round(governor * 100.0)), int(round(nxt * 100.0))]
		return "风压不足：%d%% < %d%%\n调速器已在最高档 · 检查风门与紧急停机" % [
			int(round(pressure * 100.0)), int(round(Act1Ventilation.PRESSURE_MIN * 100.0))]
	if complete:
		return "压力测试通过 · 可前往发车台"
	if not damper_open or damper <= Act1Ventilation.DAMPER_OPEN_MIN:
		return "主风道未开（风门 %d%%）· 按 E 打开风门" % int(round(damper * 100.0))
	if test_seconds > 0.0:
		return "风压达标 · 稳定计时 %.1f / %.0f 秒" % [
			minf(test_seconds, Act1Ventilation.PRESSURE_TEST_SECONDS), Act1Ventilation.PRESSURE_TEST_SECONDS]
	return "风压达标 · 保持 %.0f 秒即可通过" % Act1Ventilation.PRESSURE_TEST_SECONDS


func _vent_hint_color(pressure: float, running: bool, emergency: bool, complete: bool, damper_open: bool) -> Color:
	if emergency or not running or pressure <= Act1Ventilation.PRESSURE_MIN or not damper_open:
		return Color(1.0, 0.72, 0.38)
	if complete:
		return Color(0.52, 0.90, 0.72)
	return Color(0.62, 0.82, 0.80)


## Read-only accessor used by tests and the F1 debug view.
func vent_readout() -> String:
	return _wind_value.text + "\n" + _vent_hint.text


func set_participation(lines: Array[String]) -> void:
	_participation.text = "有效参与  /  VERIFIED CONTRIBUTIONS\n" + "\n".join(lines)


func toast(text: String, seconds: float = 3.0) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_time = seconds


func show_intro(seconds: float = 7.0) -> void:
	_intro.visible = true
	_intro.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(seconds)
	t.tween_property(_intro, "modulate:a", 0.0, 0.8)
	t.tween_callback(func() -> void: _intro.visible = false)


func fade_to(amount: float, seconds: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", amount, seconds)


func fade_alpha() -> float:
	return _fade.color.a


func show_debug(text: String) -> void:
	_debug.visible = true
	_debug.text = text


func hide_debug() -> void:
	_debug.visible = false


func set_blocked(value: bool) -> void:
	crosshair.blocked = value


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time < 0.7:
			_toast.modulate.a = clampf(_toast_time / 0.7, 0.0, 1.0)
	elif _toast.modulate.a > 0.0:
		_toast.modulate.a = 0.0
	if _intro.visible:
		_intro_title.modulate = Color(0.90, 0.95, 1.0) * (0.96 + 0.04 * sin(Time.get_ticks_msec() * 0.0015))