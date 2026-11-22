extends CanvasLayer
class_name GuluPresentation

## 表现层（2026-11-23）：标题屏 / 3-2-1 开场 / 进球浮字与闪屏 / 结算面板。
##
## 只做“包装”，不碰玩法与判定：
## - 所有节点自建，不依赖场景文件；
## - 自动化模式（--selftest/--shots/--record/--perf）由 app 直接跳过标题与倒计时；
## - 动画全部用 Tween，节点用完即隐，不常驻开销。

signal start_requested
signal countdown_finished

const ACCENT := Color("#7dffd4")
const AMBER := Color("#ffcf5c")
const INK := Color("#0b1416")

var _font: Font
var _title_root: Control
var _title_best: Label
var _title_prompt: Label
var _count_root: Control
var _count_label: Label
var _result_root: Control
var _result_label: Label
var _flash: ColorRect
var _float_root: Control
var _vignette: ColorRect
## 最近一局的结算数据（自测读取）
var last_result_score := -1
var last_result_goals := 0


func setup(font: Font) -> void:
	_font = font
	layer = 20
	_build_vignette()
	_build_flash()
	_build_floats()
	_build_title()
	_build_countdown()


# ---------------------------------------------------------------- 构造

func _build_vignette() -> void:
	# 极轻的暗角：把注意力压到画面中心，是“发行感”最便宜的一步。
	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.02, 0.04, 0.05, 0.0)
	add_child(_vignette)
	_vignette.color = Color(0.02, 0.04, 0.05, 0.10)


func _build_flash() -> void:
	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)


func _build_floats() -> void:
	_float_root = Control.new()
	_float_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_float_root)


func _build_title() -> void:
	_title_root = Control.new()
	_title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_root.visible = false
	add_child(_title_root)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.055, 0.065, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_root.add_child(dim)

	var box := VBoxContainer.new()
	box.position = Vector2(240, 190)
	box.size = Vector2(800, 420)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_title_root.add_child(box)

	var kicker := _label("奶龙星 · 物流站", 18, ACCENT)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)

	var title := _label("装卸挑战", 64, Color("#f2f7f5"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := _label("90 秒 · 把能源球送进装货口 · 躲开奶龙", 20, Color("#c8ded8"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	box.add_child(spacer)

	var keys := _label("WASD 移动    左键 点射 / 按住蓄力    R 重开     Esc 松开鼠标", 16, Color("#9fb8b4"))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(keys)

	_title_best = _label("", 16, AMBER)
	_title_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_best)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 26)
	box.add_child(spacer2)

	_title_prompt = _label("点击任意位置开始", 24, Color("#ffe9bd"))
	_title_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_prompt)

	var pulse := _title_prompt.create_tween().set_loops()
	pulse.tween_property(_title_prompt, "modulate:a", 0.45, 0.9).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_title_prompt, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)

	# 点击 / 回车开始
	var catcher := Control.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(_on_catch_input)
	_title_root.add_child(catcher)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP


func _build_countdown() -> void:
	_count_root = Control.new()
	_count_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_count_root.visible = false
	add_child(_count_root)
	_count_label = _label("3", 120, Color("#f4fbf8"))
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.position = Vector2(0, 250)
	_count_label.size = Vector2(1280, 220)
	_count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_count_label.add_theme_constant_override("shadow_offset_x", 0)
	_count_label.add_theme_constant_override("shadow_offset_y", 6)
	_count_root.add_child(_count_label)


func _build_result() -> void:
	pass


# ---------------------------------------------------------------- 对外接口

func show_title(best: int) -> void:
	_title_best.text = ("最高分  %d" % best) if best > 0 else "第一次来？先踢进一个再说"
	_title_root.visible = true
	_title_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_title_root, "modulate:a", 1.0, 0.35)


func hide_title() -> void:
	var tween := create_tween()
	tween.tween_property(_title_root, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void: _title_root.visible = false)


## 3 → 2 → 1 → 开始！ 结束后发 countdown_finished。
func play_countdown() -> void:
	_count_root.visible = true
	_count_root.modulate.a = 1.0
	var steps := ["3", "2", "1", "开始！"]
	for index in range(steps.size()):
		_count_label.text = steps[index]
		_count_label.modulate.a = 1.0
		_count_label.scale = Vector2(1.35, 1.35)
		_count_label.pivot_offset = Vector2(640, 360)
		var grow := create_tween().set_parallel(true)
		grow.tween_property(_count_label, "scale", Vector2(1.0, 1.0), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(0.55).timeout
		var fade := create_tween()
		fade.tween_property(_count_label, "modulate:a", 0.0, 0.18)
		await fade.finished
	_count_root.visible = false
	countdown_finished.emit()


## 进球：闪屏 + 世界坐标浮字（+400 / 连击 x3）。
func celebrate(screen_pos: Vector2, points: int, combo: int, color: Color) -> void:
	flash(color, 0.18, 0.22)
	float_text(screen_pos, "+%d" % points, color, 30)
	if combo > 1:
		float_text(screen_pos + Vector2(0, 34), "连击 x%d" % combo, AMBER, 22)


func flash(color: Color, peak: float = 0.2, duration: float = 0.25) -> void:
	_flash.color = Color(color.r, color.g, color.b, peak)
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, duration)


func float_text(at: Vector2, text: String, color: Color, size: int = 28) -> void:
	var label := _label(text, size, color)
	label.position = at - Vector2(120, 18)
	label.size = Vector2(240, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 3)
	_float_root.add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 54.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tween.chain().tween_callback(func() -> void: label.queue_free())


## 结算面板：本局分数 / 最高分 / 进球 / 最佳连击。
func show_result(score: int, best: int, goals: int, best_combo: int, is_record: bool) -> void:
	last_result_score = score
	last_result_goals = goals
	var old := _result_root
	if old != null:
		old.queue_free()
	_result_root = Control.new()
	_result_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_result_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.05, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2(400, 210)
	panel.custom_minimum_size = Vector2(480, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.10, 0.11, 0.94)
	style.border_color = Color(0.30, 0.62, 0.58, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	_result_root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var head := _label("时间到", 34, Color("#f2f7f5"))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(head)

	var record_note := "新纪录！" if is_record else "本局成绩"
	var note := _label(record_note, 18, AMBER if is_record else Color("#9fb8b4"))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note)

	var score_label := _label("%d 分" % score, 58, ACCENT)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(score_label)

	var detail := _label("进球 %d · 最佳连击 x%d · 最高分 %d" % [goals, best_combo, best],
		18, Color("#c8ded8"))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(detail)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	column.add_child(spacer)

	var again := _label("按 R 再来一局", 22, Color("#ffe9bd"))
	again.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(again)

	_result_root.modulate.a = 0.0
	panel.scale = Vector2(0.94, 0.94)
	panel.pivot_offset = Vector2(240, 90)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_result_root, "modulate:a", 1.0, 0.3)
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_result() -> void:
	if _result_root != null and is_instance_valid(_result_root):
		_result_root.queue_free()
		_result_root = null


func result_visible() -> bool:
	return _result_root != null and is_instance_valid(_result_root) and _result_root.is_inside_tree()


# ---------------------------------------------------------------- 内部

func _on_catch_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		start_requested.emit()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			start_requested.emit()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	if _font != null:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
