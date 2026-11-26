extends CanvasLayer

# Playtest HUD.
#
# The previous version stacked a full-width top panel, a full-width bottom panel
# containing the entire control manual, and a large world-space title, all visible
# at once. At 1280x800 that covered roughly a quarter of the frame, and the player
# could not see the deck they were standing on.
#
# Design now:
#   * one compact status line, top-left, no panel background
#   * one objective line that dims once it has been read
#   * one interaction hint near the bottom centre, only while actionable
#   * the control manual fades out after a few seconds of play
#   * F1 toggles a separate debug panel with the full numeric state

var stage: Node3D
var status: Label
var objective: Label
var hint: Label
var manual: Label
var debug_panel: Label
var debug_visible: bool = false
var _refresh: float = 0.0
var _manual_timer: float = 0.0
var _objective_timer: float = 0.0
var _last_objective: String = ""
var _hint_timer: float = 0.0
var _shown_hint: String = ""

const MANUAL_LINGER: float = 9.0
const MANUAL_FADE: float = 1.4
const OBJECTIVE_LINGER: float = 6.0
const HINT_LINGER: float = 2.6

func _ready() -> void:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	status = _make(root, 15, Color("#cfe3e6"), Control.PRESET_TOP_LEFT, Vector2(20, 14), 26)
	objective = _make(root, 17, Color("#ffd9a8"), Control.PRESET_TOP_LEFT, Vector2(20, 38), 26)
	hint = _make(root, 17, Color("#e8f4f2"), Control.PRESET_BOTTOM_WIDE, Vector2(0, -66), 26)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	manual = _make(root, 14, Color("#93a9ae"), Control.PRESET_BOTTOM_WIDE, Vector2(0, -34), 24)
	manual.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	manual.text = "WASD 移动 · Shift 跑 · 鼠标观察 · F 拾取 · X 缓放 · G 固定 · E 抓扶/发车 · B 制动 · R 回收 · F1 调试"
	debug_panel = _make(root, 14, Color("#8fe0b0"), Control.PRESET_TOP_RIGHT, Vector2(-350, 14), 210)
	debug_panel.visible = false
	debug_panel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _make(parent: Control, points: int, tint: Color, preset: int, offset: Vector2, height: float) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_override("font", stage.get("ui_font") as Font)
	label.add_theme_font_size_override("font_size", points)
	label.add_theme_color_override("font_color", tint)
	# A thin dark outline keeps text readable over both lit rock and dark shadow
	# without needing an opaque panel that would hide the scene.
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.03, 0.92))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.set_anchors_and_offsets_preset(preset)
	if preset == Control.PRESET_TOP_LEFT:
		label.offset_left = offset.x
		label.offset_top = offset.y
		label.offset_right = offset.x + 620
		label.offset_bottom = offset.y + height
	elif preset == Control.PRESET_TOP_RIGHT:
		label.offset_left = offset.x
		label.offset_right = -18
		label.offset_top = offset.y
		label.offset_bottom = offset.y + height
	else:
		label.offset_left = 24
		label.offset_right = -24
		label.offset_top = offset.y
		label.offset_bottom = offset.y + height
	return label

func toggle_help() -> void:
	debug_visible = not debug_visible
	debug_panel.visible = debug_visible
	if debug_visible:
		manual.modulate.a = 1.0
		_manual_timer = 0.0

func _process(delta: float) -> void:
	_animate(delta)
	_refresh += delta
	if _refresh < 0.12: return
	_refresh = 0.0
	var cart: Node3D = stage.get("cart") as Node3D
	var cargo: Node3D = stage.get("device") as Node3D
	var locked: int = int(cargo.call("locked_count"))
	# Compact: state, speed, progress, cargo. No repeated mission title.
	status.text = "%s · %.1f km/h · %.0f/90 m · 货物 %d/2" % [str(cart.get("state")), float(cart.get("speed")) * 3.6, float(cart.get("distance")), locked]
	_update_objective(cart)
	_update_hint()
	if debug_visible:
		debug_panel.text = _debug_text(cart, locked)

func _update_objective(cart: Node3D) -> void:
	var text: String
	if bool(cart.get("arrived")):
		text = "已到站 · 沿黄色踏步下车（Esc 重新开始）"
	elif bool(cart.get("event_active")):
		text = "共振弯道 · 抓扶稳住，或按 B 制动"
	elif float(cart.get("speed")) > 0.05:
		text = "行驶中 · 到站前处理货物"
	else:
		text = "登上甲板，到前端控制器按 E 发车"
	if text != _last_objective:
		_last_objective = text
		_objective_timer = OBJECTIVE_LINGER
	objective.text = text
	# Dim to a quiet reminder once the player has had time to read it.
	objective.modulate.a = 1.0 if _objective_timer > 0.0 else 0.45

func _update_hint() -> void:
	# Only surface a hint that the player can act on right now.
	var text: String = str(stage.get("feedback"))
	if text == "":
		hint.text = ""
		return
	if text != _shown_hint:
		_shown_hint = text
		_hint_timer = HINT_LINGER
	hint.text = text
	hint.modulate.a = clampf(_hint_timer / 0.8, 0.0, 1.0)

func _animate(delta: float) -> void:
	if _objective_timer > 0.0:
		_objective_timer = maxf(0.0, _objective_timer - delta)
	_hint_timer = maxf(0.0, _hint_timer - delta)
	if debug_visible: return
	_manual_timer += delta
	var alpha: float = 1.0
	if _manual_timer > MANUAL_LINGER:
		alpha = 1.0 - clampf((_manual_timer - MANUAL_LINGER) / MANUAL_FADE, 0.0, 1.0)
	manual.modulate.a = alpha

func _debug_text(cart: Node3D, locked: int) -> String:
	var player: CharacterBody3D = stage.get("player") as CharacterBody3D
	var local: Vector3 = cart.to_local(player.global_position)
	var event: Node3D = stage.get("bend_event") as Node3D
	# intensity is a plain property on the event node; calling it as a method
	# raised "Nonexistent function" every frame the debug panel was open.
	var intensity: float = float(event.get("intensity")) if event != null else 0.0
	var lines: Array[String] = []
	lines.append("F1 调试面板")
	lines.append("distance %.2f  speed %.3f" % [float(cart.get("distance")), float(cart.get("speed"))])
	lines.append("event %s  intensity %.2f" % [str(cart.get("event_active")), intensity])
	lines.append("player local %.2f %.2f %.2f" % [local.x, local.y, local.z])
	lines.append("on_floor %s  grip %d" % [str(player.is_on_floor()), int(player.get("grip_id"))])
	lines.append("locked %d  carrying %d" % [locked, int(player.get("carrying"))])
	lines.append("draw %d  fps %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), Engine.get_frames_per_second()])
	return "\n".join(lines)
