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
var coop_line: Label
var outcome: Label
var prompt: Label
var hint: Label
var manual: Label
var debug_panel: Label
var blocked_banner: Label
var debug_visible: bool = false
var link_text: String = "离线"
var roster_cache: Dictionary = {}
var _refresh: float = 0.0
var _manual_timer: float = 0.0
var _objective_timer: float = 0.0
var _last_objective: String = ""
var _hint_timer: float = 0.0
var _shown_hint: String = ""
var _frame_times: Array[float] = []
var alignment_gauge: Control

const MANUAL_LINGER: float = 11.0
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
	# Roster / link line: who is on the crew and whether this is a real session.
	coop_line = _make(root, 14, Color("#9fd4dd"), Control.PRESET_TOP_LEFT, Vector2(20, 64), 24)
	# End-of-run verdict. It only appears once the cart has actually arrived, and
	# it names who produced work and who did not.
	outcome = _make(root, 18, Color("#b7f5c7"), Control.PRESET_TOP_WIDE, Vector2(0, 96), 60)
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome.visible = false
	prompt = _make(root, 18, Color("#ffe9c4"), Control.PRESET_BOTTOM_WIDE, Vector2(0, -98), 26)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Air-wall banner: only visible while F3 is on and the capsule is actually
	# being refused. It names the blocking object, which is the whole point of
	# the inspector - "you cannot go there" is not an answer a player can act on.
	blocked_banner = _make(root, 16, Color("#ff9c80"), Control.PRESET_BOTTOM_WIDE, Vector2(0, -132), 30)
	blocked_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blocked_banner.visible = false
	hint = _make(root, 17, Color("#e8f4f2"), Control.PRESET_BOTTOM_WIDE, Vector2(0, -66), 26)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	manual = _make(root, 14, Color("#93a9ae"), Control.PRESET_BOTTOM_WIDE, Vector2(0, -34), 24)
	manual.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	manual.text = "WASD 移动 · Shift 跑 · E 抓扶/发车/互动/锁爪 · B 手制动（连按换档） · F 拾取 · X 缓放 · G 放置 · R 回收 · Q 拆缆 · 空格鼓刹 · F3 空气墙检查 · F4 扫描"
	debug_panel = _make(root, 14, Color("#8fe0b0"), Control.PRESET_TOP_RIGHT, Vector2(-360, 14), 250)
	debug_panel.visible = false
	debug_panel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# The exact lock window used to live only in the F3 panel. The gauge reads the
	# rail's hinge angle and paints the receiver's real capture band, so a human
	# can stop W by eye instead of by frame-perfect timing.
	alignment_gauge = (load("res://act23/scripts/alignment_gauge.gd") as Script).new() as Control
	alignment_gauge.set("stage", stage)
	alignment_gauge.visible = false
	root.add_child(alignment_gauge)

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

# F3 drives the air-wall inspector; the numeric panel follows it so a human never
# has to remember two separate debug keys.
func set_debug(value: bool) -> void:
	debug_visible = value
	debug_panel.visible = value
	if value:
		manual.modulate.a = 1.0
		_manual_timer = 0.0
	else:
		blocked_banner.visible = false

func set_link_text(text: String) -> void:
	link_text = text

func set_roster_text(roster: Dictionary) -> void:
	roster_cache = roster

func _coop_text() -> String:
	var parts: Array[String] = []
	var local_slot: int = int(stage.get("local_slot"))
	var keys: Array = roster_cache.keys()
	keys.sort()
	for slot: int in keys:
		var entry: Dictionary = roster_cache[slot] as Dictionary
		if not bool(entry.get("connected", true)):
			continue
		var tag: String = "玩家 %d" % slot
		if slot == local_slot:
			tag += "（你）"
		parts.append(tag)
	if parts.size() <= 1:
		return "单人 · %s" % link_text
	return "联机 %d 人 · %s · %s" % [parts.size(), link_text, " / ".join(parts)]

func _process(delta: float) -> void:
	_animate(delta)
	_refresh += delta
	if _refresh < 0.12: return
	_update_frame_times(delta)
	_refresh = 0.0
	var cart: Node3D = stage.get("cart") as Node3D
	var cargo: Node3D = stage.get("device") as Node3D
	var locked: int = int(cargo.call("locked_count"))
	# Compact: state, speed, progress, cargo. No repeated mission title.
	# MECHANICS-002B: 手制动档位是机构的真实状态，速度是真实积分速度。
	var brake_note: String = ""
	var brake: Dictionary = cart.call("brake_state") as Dictionary
	var notch: int = int(brake.get("notch", 0))
	if notch > 0:
		brake_note = " · 手制动 %s" % ("紧急" if notch > 1 else "常用")
	status.text = "%s · %.1f km/h · %.0f/106 m · 货物 %d/2%s" % [str(cart.get("state")),
		float(cart.get("speed")) * 3.6, float(cart.get("distance")), locked, brake_note]
	coop_line.text = _coop_text()
	_update_outcome()
	_update_objective(cart)
	_update_prompt()
	_update_hint()
	_update_blocked_banner()
	if debug_visible:
		debug_panel.text = _debug_text(cart, locked)

func _update_blocked_banner() -> void:
	var inspector: Node = stage.get("airwall")
	if inspector == null or not bool(inspector.get("enabled")):
		blocked_banner.visible = false
		return
	var text: String = str(inspector.call("summary"))
	blocked_banner.visible = text != ""
	blocked_banner.text = text

func _update_frame_times(delta: float) -> void:
	_frame_times.append(delta * 1000.0)
	if _frame_times.size() > 240:
		_frame_times.pop_front()

func _update_objective(cart: Node3D) -> void:
	var flow: Node = stage.get("flow") as Node
	var text: String = ""
	if flow != null:
		text = str(flow.get("objective_text"))
	if text == "":
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

# The end-of-run card is the visible form of the participation rule: it names
# the players who actually produced work, and it refuses to call an idle player
# a co-op completion.
func _update_outcome() -> void:
	var flow: Node = stage.get("flow") as Node
	var done: bool = flow != null and str(flow.get("phase")) == "done"
	outcome.visible = done
	if not done:
		return
	var part: Node = stage.get("participation") as Node
	if part == null:
		return
	outcome.text = "抵达 03 · 晶体矿区入口 · 同一辆矿车完成 02→03\n%s" % str(part.call("verdict_text"))

func _update_prompt() -> void:
	# One line, only while an interaction is actually available. The winch's
	# numeric state (tension, angle, end error) lives in the F3 panel.
	var flow: Node = stage.get("flow") as Node
	var text: String = ""
	if flow != null:
		text = str(flow.get("prompt_text"))
	if text == "" and stage != null and stage.has_method("explore_prompt"):
		text = str(stage.call("explore_prompt"))
	prompt.text = text
	prompt.visible = text != ""

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
	lines.append("F3 空气墙检查 · F4 扫描")
	lines.append("distance %.2f  speed %.3f" % [float(cart.get("distance")), float(cart.get("speed"))])
	lines.append("event %s  intensity %.2f" % [str(cart.get("event_active")), intensity])
	lines.append("player local %.2f %.2f %.2f" % [local.x, local.y, local.z])
	lines.append("on_floor %s  grip %d" % [str(player.is_on_floor()), int(player.get("grip_id"))])
	lines.append("locked %d  carrying %d" % [locked, int(player.get("carrying"))])
	var inspector: Node = stage.get("airwall")
	if inspector != null:
		lines.append("碰撞体叠加 %s · 记录 %d" % [
			str(bool(inspector.get("enabled"))), int(inspector.get("record_count"))])
		var recent: String = str(inspector.call("recent_text", 3))
		if recent != "":
			lines.append(recent)
	var flow: Node = stage.get("flow") as Node
	if flow != null:
		lines.append("phase %s  console %s" % [str(flow.get("phase")), str(flow.get("at_console"))])
		var yard: Node3D = stage.get("yard") as Node3D
		if yard != null:
			var rig: Node3D = yard.get("rig") as Node3D
			if rig != null:
				var tension: Dictionary = rig.call("tension_state") as Dictionary
				var rail: Dictionary = rig.call("alignment_state") as Dictionary
				lines.append("cable %.2f m  %.0f N  %.0f%%" % [
					float(tension.get("free_length", 0.0)), float(tension.get("tension", 0.0)),
					float(tension.get("tension_ratio", 0.0)) * 100.0])
				lines.append("rail %.2f°  end %.3f m  arm %.2f m" % [
					float(rail.get("angle_deg", 0.0)), float(rail.get("end_error", 0.0)),
					float(rail.get("moment_arm", 0.0))])
				lines.append("pin %s  jam %s  slip %s" % [
					str(rail.get("lock_pin", false)), str(rail.get("jammed", true)),
					str(tension.get("stalled", false))])
	var frame_text: String = ""
	if not _frame_times.is_empty():
		var sorted: Array[float] = _frame_times.duplicate()
		sorted.sort()
		var p50: float = sorted[int(float(sorted.size()) * 0.50)]
		var p95: float = sorted[mini(sorted.size() - 1, int(float(sorted.size()) * 0.95))]
		frame_text = "  ms %.1f/%.1f" % [p50, p95]
	lines.append("draw %d  fps %d%s" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), Engine.get_frames_per_second(), frame_text])
	return "\n".join(lines)
