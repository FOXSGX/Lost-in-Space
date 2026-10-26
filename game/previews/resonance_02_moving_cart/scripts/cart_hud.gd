extends CanvasLayer

var stage: Node3D
var speed_label: Label
var goal: Label
var feedback: Label
var help: Label
var _timer: float = 0.0

func _ready() -> void:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 22)
	root.add_child(margin)
	var panel: PanelContainer = PanelContainer.new()
	margin.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	speed_label = _label(column, "RESONANCE 02 / 移动矿车", 22)
	goal = _label(column, "登车 → 自由处理货物 → 发车 → 弯道 → 短途终点", 18)
	var bottom: MarginContainer = MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("margin_left", 22)
	bottom.add_theme_constant_override("margin_right", 22)
	bottom.add_theme_constant_override("margin_bottom", 18)
	root.add_child(bottom)
	var lower: PanelContainer = PanelContainer.new()
	bottom.add_child(lower)
	var lower_column: VBoxContainer = VBoxContainer.new()
	lower.add_child(lower_column)
	feedback = _label(lower_column, "", 19)
	help = _label(lower_column, "WASD 移动 / Shift 跑 / 鼠标观察  ·  F 拾取 / X 缓放 / G 固定\nE 抓扶、松开或前端发车  ·  B 随时制动 / 停车后 R 救援回收  ·  Esc 菜单 / F1 提示", 17)

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_override("font", stage.get("ui_font") as Font)
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func toggle_help() -> void:
	help.visible = not help.visible

func _process(delta: float) -> void:
	_timer += delta
	if _timer < 0.10: return
	_timer = 0.0
	var cart: Node3D = stage.get("cart") as Node3D
	var cargo: Node3D = stage.get("device") as Node3D
	var locked: int = int(cargo.call("locked_count"))
	speed_label.text = "RESONANCE 02   |   %s   %.1f km/h   |   %.0f / 90 m   |   固定 %d / 2" % [str(cart.get("state")), float(cart.get("speed")) * 3.6, float(cart.get("distance")), locked]
	goal.text = "共振弯道 · 可抓扶或 B 制动，停车后处理货物" if bool(cart.get("event_active")) else ("已到站 · 沿黄色踏步下车。货物 %d / 2 已固定；Esc 可重新开始。" % locked if bool(cart.get("arrived")) else "可提前固定，也可途中停车补救 · 任务没有倒计时")
	feedback.text = str(stage.get("feedback"))
