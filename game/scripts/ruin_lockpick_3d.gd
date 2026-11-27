extends CanvasLayer

## 腐墟星二级弹子锁小游戏。
##
## 所有门默认共用同一把锁：4 根弹子、同一套下压速度，没有随机难度。
## A/D 或左右选择弹子，按住鼠标左键/空格把弹子往下压；压到底后弹子卡住，
## 四根都卡住就开门。松开未到底的弹子会弹回，Esc 退出，R 重置。

const PIN_COUNT := 4
const PIN_PUSH_SPEED := 0.92
const PIN_SPRING_SPEED := 2.4

const COLOR_PANEL := Color("#0b1a20")
const COLOR_PANEL_EDGE := Color("#c9793b")
const COLOR_BRASS := Color("#d9a75f")
const COLOR_BRASS_DARK := Color("#3a2a1a")
const COLOR_CHANNEL := Color("#17120d")
const COLOR_TEAL := Color("#75aeb0")
const COLOR_DONE := Color("#9ff5c9")
const COLOR_TEXT := Color("#f2e2c4")
const COLOR_MUTED := Color("#a8b9b6")

var main: Node
var building_id := ""
var building_name := ""

var _pins: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _latched: Array[bool] = [false, false, false, false]
var _selected := 0
var _holding := false
var _solved := false
var _finished := false
var _close_timer := 0.0
var _pin_bodies: Array[ColorRect] = []
var _pin_latches: Array[ColorRect] = []
var _pick: ColorRect
var _pick_x := 70.0
var _pick_target_x := 70.0
var _pick_phase := 0.0
var _progress: Label
var _status: Label
var _hint: Label


func setup(main_node: Node, id: String, display_name: String) -> void:
	main = main_node
	building_id = id
	building_name = display_name
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "LockpickRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.012, 0.018, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var panel := Panel.new()
	panel.name = "LockpickPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -330.0
	panel.offset_top = -275.0
	panel.offset_right = 330.0
	panel.offset_bottom = 275.0
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = COLOR_PANEL_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var title := _label(panel, "二级弹子锁", Vector2(32, 18), Vector2(596, 36), 26, COLOR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := _label(panel, building_name, Vector2(32, 56), Vector2(596, 24), 14, COLOR_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var body := Panel.new()
	body.position = Vector2(60, 98)
	body.size = Vector2(540, 292)
	var body_style := StyleBoxFlat.new()
	body_style.bg_color = COLOR_BRASS_DARK
	body_style.border_color = Color("#8a5a2b")
	body_style.set_border_width_all(2)
	body_style.set_corner_radius_all(8)
	body.add_theme_stylebox_override("panel", body_style)
	panel.add_child(body)

	# 锁芯里的四条弹子槽。弹子从槽顶往下压，压到底部横线后卡住。
	for index: int in PIN_COUNT:
		var x := 54.0 + float(index) * 116.0
		var number := _label(body, "%d" % (index + 1), Vector2(x + 4, 12), Vector2(40, 24), 15, COLOR_MUTED)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var channel := ColorRect.new()
		channel.color = COLOR_CHANNEL
		channel.position = Vector2(x, 42)
		channel.size = Vector2(48, 196)
		channel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(channel)
		var pin := ColorRect.new()
		pin.color = COLOR_BRASS
		pin.position = Vector2(x + 10, 48)
		pin.size = Vector2(28, 60)
		pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(pin)
		_pin_bodies.append(pin)
		var target := ColorRect.new()
		target.color = COLOR_TEAL
		target.position = Vector2(x + 4, 218)
		target.size = Vector2(40, 3)
		target.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(target)
		var latch := ColorRect.new()
		latch.color = Color("#4a3522")
		latch.position = Vector2(x + 4, 226)
		latch.size = Vector2(40, 9)
		latch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(latch)
		_pin_latches.append(latch)

	_pick = ColorRect.new()
	_pick.color = COLOR_PANEL_EDGE
	_pick.size = Vector2(16, 28)
	_pick.position = Vector2(70, 252)
	_pick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_pick)

	_progress = _label(panel, "", Vector2(32, 404), Vector2(596, 30), 20, COLOR_TEAL)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = _label(panel, "弹子到底会卡住；松开未到底的弹子会回弹。", Vector2(32, 438), Vector2(596, 30), 15, COLOR_TEXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint = _label(panel, "A / D 或 ← → 选择弹子   ·   按住左键 / 空格下压   ·   Esc 退出   ·   R 重置", Vector2(32, 482), Vector2(596, 26), 13, COLOR_MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_visuals()


func _label(parent: Control, text: String, at: Vector2, box: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = box
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _process(delta: float) -> void:
	if _solved:
		_close_timer -= delta
		if _close_timer <= 0.0 and not _finished:
			_finished = true
			main.call("finish_ruin_lockpick", true)
		return

	if _holding and not _latched[_selected]:
		_pins[_selected] = minf(_pins[_selected] + delta * PIN_PUSH_SPEED, 1.0)
		if _pins[_selected] >= 1.0:
			_latched[_selected] = true
			_status.text = "咔哒 · 第 %d 根弹子卡住了。" % (_selected + 1)
	else:
		for index: int in PIN_COUNT:
			if _latched[index] or (_holding and index == _selected):
				continue
			_pins[index] = maxf(_pins[index] - delta * PIN_SPRING_SPEED, 0.0)

	if _latched.all(func(value: bool) -> bool: return value) and not _solved:
		_solved = true
		_close_timer = 0.55
		_status.text = "咔哒 · 锁芯归位，门锁打开了。"
	# 撬锁针平滑移动到当前弹子；下压时轻微抖动，避免静态贴图感。
	_pick_phase += delta
	_pick_x = lerpf(_pick_x, _pick_target_x, 1.0 - exp(-18.0 * delta))
	var wobble := sin(_pick_phase * 22.0) * (2.5 if _holding and not _latched[_selected] else 0.6)
	_pick.position = Vector2(_pick_x + wobble, 252.0 + (4.0 if _holding else 0.0))
	_pick.rotation = deg_to_rad(wobble * 1.8 + (6.0 if _holding else 0.0))
	_update_visuals()


func _update_visuals() -> void:
	if _progress == null:
		return
	var count := 0
	for index: int in PIN_COUNT:
		if _latched[index]:
			count += 1
		if index < _pin_bodies.size():
			_pin_bodies[index].position.y = 48.0 + _pins[index] * 100.0
			_pin_bodies[index].color = COLOR_DONE if _latched[index] else COLOR_BRASS
		if index < _pin_latches.size():
			_pin_latches[index].color = COLOR_DONE if _latched[index] else Color("#4a3522")
	_pick_target_x = 54.0 + float(_selected) * 116.0 + 16.0
	_progress.text = "已固定 %d / %d" % [count, PIN_COUNT]


func _input(event: InputEvent) -> void:
	if not visible or _finished:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var key := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
		if not key_event.pressed:
			if key == KEY_SPACE:
				_holding = false
				get_viewport().set_input_as_handled()
			return
		if key_event.echo:
			return
		match key:
			KEY_ESCAPE:
				_cancel()
			KEY_A, KEY_LEFT:
				_selected = (_selected + PIN_COUNT - 1) % PIN_COUNT
				_holding = false
				_update_visuals()
			KEY_D, KEY_RIGHT:
				_selected = (_selected + 1) % PIN_COUNT
				_holding = false
				_update_visuals()
			KEY_R:
				_reset()
			KEY_SPACE:
				_holding = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_holding = mouse_event.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


func _reset() -> void:
	if _solved:
		return
	for index: int in PIN_COUNT:
		_pins[index] = 0.0
		_latched[index] = false
	_selected = 0
	_holding = false
	_status.text = "弹子已复位。"
	_update_visuals()


func _cancel() -> void:
	if _finished:
		return
	_finished = true
	main.call("finish_ruin_lockpick", false)
