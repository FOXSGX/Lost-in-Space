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
signal resume_requested
signal restart_requested
signal mute_toggled
signal stage_requested(stage_index: int)
signal practice_requested
signal arcade_requested

const ACCENT := Color("#7dffd4")
const AMBER := Color("#ffcf5c")
const INK := Color("#0b1416")

var _font: Font
var _title_root: Control
var _title_best: Label
var _title_prompt: Label
var _title_tier: Label
var _title_progress: Label
var _title_time: Label
var _records_root: Control
var _count_root: Control
var _count_label: Label
var _result_root: Control
var _result_label: Label
var _pause_root: Control
var _pause_visible := false
var _mute_button: Button
var _resume: Button
var _restart: Button
var _confirm_restart := false
var _flash: ColorRect
var _float_root: Control
var _vignette: ColorRect
## 最近一局的结算数据（自测读取）
var last_result_score := -1
var last_result_goals := 0
var last_result_shots := 0
var last_result_saves := 0
var last_result_objectives := 0
## 本局三个目标：进球 3 / 连击 x4 / 订单命中 2。命中数写进 last_result_objectives。
const OBJECTIVE_GOALS := 3
const OBJECTIVE_COMBO := 4
const OBJECTIVE_ORDER_HITS := 2


func evaluate_objectives(goals: int, best_combo: int, order_hits: int) -> int:
	var met := 0
	if goals >= OBJECTIVE_GOALS:
		met += 1
	if best_combo >= OBJECTIVE_COMBO:
		met += 1
	if order_hits >= OBJECTIVE_ORDER_HITS:
		met += 1
	return met


func setup(font: Font) -> void:
	_font = font
	# 暂停时整棵树停摆，表现层（尤其是暂停菜单）必须继续响应。
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_vignette()
	_build_flash()
	_build_floats()
	_build_title()
	_build_countdown()
	_build_pause()


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

	var sub := _label("6 关 · 3 个场景 · 每关 90 秒 · 全过即通关", 20, Color("#c8ded8"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	box.add_child(spacer)

	var keys := _label("回车开始　·　1/2/3 难度　·　7/8/9 时段　·　4/5/6 练习　·　L 记录板　·　0 刷分", 15, Color("#9fb8b4"))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(keys)

	_title_best = _label("", 16, AMBER)
	_title_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_best)

	# 难度档 + 挑战进度：标题屏就把“这局在什么难度、还差几条挑战”讲清楚。
	_title_tier = _label("难度　标准　（1 / 2 / 3 切换）", 15, Color("#9fb8b4"))
	_title_tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_tier)

	_title_progress = _label("", 15, Color("#9fb8b4"))
	_title_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_progress)

	# 时段（P2）：只换光照与雾，标题屏可直接切。
	_title_time = _label("时段　正午　（7 / 8 / 9 切换）", 15, Color("#9fb8b4"))
	_title_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_time)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 26)
	box.add_child(spacer2)

	_title_prompt = _label("点击任意位置开始", 24, Color("#ffe9bd"))
	_title_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_prompt)

	var pulse := _title_prompt.create_tween().set_loops()
	pulse.tween_property(_title_prompt, "modulate:a", 0.45, 0.9).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_title_prompt, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	# 关卡 / 模式直达（对齐共振星试玩版的“单幕按钮”）
	var stage_row := HBoxContainer.new()
	stage_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stage_row.add_theme_constant_override("separation", 10)
	box.add_child(stage_row)
	for index in range(3):
		var stage_button := _button("第 %d 关" % (index + 1))
		stage_button.add_theme_font_size_override("font_size", 16)
		var stage_index := index + 1
		stage_button.pressed.connect(func() -> void: stage_requested.emit(stage_index))
		stage_row.add_child(stage_button)

	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 10)
	box.add_child(mode_row)
	var practice_button := _button("练习关")
	practice_button.add_theme_font_size_override("font_size", 16)
	practice_button.pressed.connect(func() -> void: practice_requested.emit())
	mode_row.add_child(practice_button)
	var arcade_button := _button("刷分模式")
	arcade_button.add_theme_font_size_override("font_size", 16)
	arcade_button.pressed.connect(func() -> void: arcade_requested.emit())
	mode_row.add_child(arcade_button)

	# 点击 / 回车开始（catcher 在底层，按钮在上层，点按钮不会误触发“开始”）
	var catcher := Control.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(_on_catch_input)
	_title_root.add_child(catcher)
	_title_root.move_child(catcher, 0)
	catcher.mouse_filter = Control.MOUSE_FILTER_PASS


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


func _build_pause() -> void:
	_pause_root = Control.new()
	_pause_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_root.visible = false
	add_child(_pause_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.05, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.10, 0.11, 0.95)
	style.border_color = Color(0.30, 0.62, 0.58, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var head := _label("比赛暂停", 34, Color("#f2f7f5"))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(head)

	var hint := _label("P / Esc 继续", 16, Color("#9fb8b4"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	column.add_child(gap)

	_resume = _button("继续比赛")
	_resume.add_theme_color_override("font_color", ACCENT)
	_resume.pressed.connect(func() -> void: resume_requested.emit())
	column.add_child(_resume)

	_restart = _button("重新开始")
	_restart.pressed.connect(func() -> void:
		if not _confirm_restart:
			restart_requested.emit()
		else:
			_confirm_restart = false
			_restart.text = "确认放弃本局并重开")
	column.add_child(_restart)

	_mute_button = _button("音效：开")
	_mute_button.pressed.connect(func() -> void: mute_toggled.emit())
	column.add_child(_mute_button)


## 暂停菜单：显示时释放鼠标，按钮用鼠标点；键盘 P/Esc 也能继续。
func show_pause(muted: bool, has_progress: bool = false) -> void:
	_confirm_restart = has_progress
	if _pause_root == null:
		return
	_pause_visible = true
	set_mute_state(muted)
	_pause_root.visible = true
	_restart.text = "重新开始"
	_resume.grab_focus()
	_pause_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_pause_root, "modulate:a", 1.0, 0.16)


func hide_pause() -> void:
	_pause_visible = false
	if _pause_root != null:
		_pause_root.visible = false


func pause_visible() -> bool:
	return _pause_visible


func restart_confirmation_text() -> String:
	return _restart.text if _restart != null else ""


func request_pause_restart() -> void:
	if _restart != null:
		_restart.pressed.emit()


func set_mute_state(muted: bool) -> void:
	if _mute_button != null:
		_mute_button.text = "音效：关" if muted else "音效：开"


func _input(event: InputEvent) -> void:
	# 只在暂停菜单出现时接管键盘；平时 P/Esc 归 gulu_app 处理。
	if not _pause_visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			resume_requested.emit()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 对外接口

func show_title(best: int, tier_name: String = "标准", challenges_done: int = 0,
		challenges_total: int = 10, time_name: String = "正午") -> void:
	_title_best.text = ("最高分  %d" % best) if best > 0 else "第一次来？先踢进一个再说"
	set_tier_label(tier_name)
	set_time_label(time_name)
	var tail := "　全部完成！" if challenges_total > 0 and challenges_done >= challenges_total else ""
	_title_progress.text = "挑战进度 %d / %d%s" % [challenges_done, challenges_total, tail]
	_title_root.visible = true
	_title_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_title_root, "modulate:a", 1.0, 0.35)


func set_tier_label(tier_name: String) -> void:
	if _title_tier != null:
		_title_tier.text = "难度　%s　（1 / 2 / 3 切换）" % tier_name


func set_time_label(time_name: String) -> void:
	if _title_time != null:
		_title_time.text = "时段　%s　（7 / 8 / 9 切换）" % time_name


## 记录板（P2）：三档最高分 + 挑战清单 + 当前难度/时段。纯展示，不改任何状态。
## entries: { tiers: Array[int], names: Array[String], current: int, done: int, total: int,
##            challenges: Array[{label:String, done:bool}], time_name: String }
func show_records(entries: Dictionary) -> void:
	hide_records()
	_records_root = Control.new()
	_records_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_records_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.05, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_records_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_records_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.10, 0.11, 1.0)
	style.border_color = Color(0.30, 0.62, 0.58, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var head := _label("记录板", 30, Color("#f2f7f5"))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(head)

	var tiers: Array = entries.get("tiers", [])
	var names: Array = entries.get("names", [])
	var current := int(entries.get("current", 1))
	for index in range(mini(tiers.size(), names.size())):
		var mark := "▶" if index == current else "　"
		var line := _label("%s %s　最高分 %d" % [mark, str(names[index]), int(tiers[index])], 18,
			AMBER if index == current else Color("#c8ded8"))
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(line)

	var summary := _label("挑战 %d / %d　·　时段 %s" % [
		int(entries.get("done", 0)), int(entries.get("total", 0)), str(entries.get("time_name", "正午"))],
		16, Color("#9fb8b4"))
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(summary)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	column.add_child(spacer)

	for item in entries.get("challenges", []):
		var done := bool(item.get("done", false))
		var row := _label("%s  %s" % ["✔" if done else "□", str(item.get("label", ""))], 16,
			ACCENT if done else Color("#7e9a96"))
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(row)

	var close := _label("按 L 或 Esc 关闭", 14, Color("#9fb8b4"))
	close.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(close)

	# 记录板直接不透明出现：它在演示片/截图里是“定格页”，淡入反而会拍到半透明帧。
	_records_root.modulate = Color(1, 1, 1, 1)


func hide_records() -> void:
	if _records_root != null and is_instance_valid(_records_root):
		_records_root.queue_free()
	_records_root = null


func records_visible() -> bool:
	return _records_root != null and is_instance_valid(_records_root) and _records_root.is_inside_tree()


func hide_title() -> void:
	var tween := create_tween()
	tween.tween_property(_title_root, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void: _title_root.visible = false)


func title_visible() -> bool:
	return _title_root != null and _title_root.visible


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


## 结算面板：本局分数 / 最高分 / 进球 / 最佳连击 / 射门与被扑出次数。
func show_result(score: int, best: int, goals: int, best_combo: int, is_record: bool,
		shots: int = 0, saves: int = 0, order_hits: int = 0,
		challenges_done: int = 0, challenges_total: int = 10,
		new_challenges: Array = []) -> void:
	last_result_score = score
	last_result_goals = goals
	last_result_shots = shots
	last_result_saves = saves
	last_result_objectives = evaluate_objectives(goals, best_combo, order_hits)
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
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_root.add_child(center)
	panel.custom_minimum_size = Vector2(480, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.10, 0.11, 0.94)
	style.border_color = Color(0.30, 0.62, 0.58, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

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

	var extra := _label("射门 %d · 被扑出 %d · 进球率 %d%%" % [shots, saves, _hit_rate(goals, shots)],
		16, Color("#9fb8b4"))
	extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(extra)

	# 本局目标（P0-8）：三条，达成的打勾、未达成留空框，让结算页有“下一局想做到什么”。
	var objectives_met := evaluate_objectives(goals, best_combo, order_hits)
	var objective_title := _label("本局目标　%d / 3" % objectives_met, 15, Color("#9fb8b4"))
	objective_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(objective_title)
	var rows := [
		["进球 ≥ %d" % OBJECTIVE_GOALS, goals >= OBJECTIVE_GOALS],
		["最佳连击 ≥ x%d" % OBJECTIVE_COMBO, best_combo >= OBJECTIVE_COMBO],
		["订单命中 ≥ %d" % OBJECTIVE_ORDER_HITS, order_hits >= OBJECTIVE_ORDER_HITS],
	]
	for row in rows:
		var ok: bool = row[1]
		var line := _label("%s  %s" % ["✔" if ok else "□", row[0]], 16,
			ACCENT if ok else Color("#7e9a96"))
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(line)

	# 挑战清单进度（本地存盘）；本局新达成的条目单独列一行。
	var progress := _label("挑战进度 %d / %d" % [challenges_done, challenges_total], 15,
		Color("#9fb8b4"))
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(progress)
	if not new_challenges.is_empty():
		var labels: Array[String] = []
		for item in new_challenges:
			labels.append(str(item))
		var unlocked := _label("本局解锁：%s" % ", ".join(labels), 16, AMBER)
		unlocked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(unlocked)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	column.add_child(spacer)

	var again := _button("再来一局　[R]")
	again.name = "ResultRestartButton"
	again.focus_mode = Control.FOCUS_ALL
	again.add_theme_color_override("font_color", AMBER)
	again.pressed.connect(func() -> void: restart_requested.emit())
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


func _hit_rate(goals: int, shots: int) -> int:
	if shots <= 0:
		return 0
	return int(round(100.0 * float(goals) / float(shots)))


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 42)
	button.focus_mode = Control.FOCUS_ALL
	if _font != null:
		button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color("#eaf7f4"))
	button.add_theme_color_override("font_hover_color", Color("#0b1416"))
	button.add_theme_color_override("font_pressed_color", Color("#0b1416"))
	button.add_theme_color_override("font_focus_color", INK)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.20, 0.21, 0.92)
	normal.border_color = Color(0.30, 0.62, 0.58, 0.75)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(10)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.49, 1.0, 0.83, 0.95)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.36, 0.78, 0.66, 0.98)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	return button


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	if _font != null:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
