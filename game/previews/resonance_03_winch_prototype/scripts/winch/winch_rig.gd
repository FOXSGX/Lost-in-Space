extends Node3D

# -----------------------------------------------------------------------------
# WinchRig - the mission orchestrator and the only object the future Resonance
# scene has to talk to.
#
# Physics order inside one fixed tick (60 Hz, Jolt):
#   1. winch.tick(delta)             drum + cable length update
#   2. rail.solve_cable(...)         rail angle from the cable length error
#   3. winch.observe_tension(...)    clutch / overload bookkeeping
#   4. cable.update_cable(...)       visual only
# The length is integrated first, the structure follows it, and the machine only
# reacts to what actually happened. No step reads a value the same step wrote,
# which is what keeps the loop from oscillating.
#
# The rig never depends on a hard-coded node path: every part is resolved either
# from an exported NodePath or from its group.
#
# Public API (see README.md)
#   attach_cable(anchor_id) -> Dictionary      {ok, reason, anchor}
#   detach_cable() -> void
#   set_winch_input(action, pressed)           action: haul|payout|creep
#   toggle_brake() -> void
#   try_install_lock() -> Dictionary           {ok, reason}
#   reset_mission() -> void
#   tension_state() -> Dictionary
#   alignment_state() -> Dictionary
#   lock_state() -> Dictionary
#   rig_snapshot() -> Dictionary
# -----------------------------------------------------------------------------

signal mission_completed
signal feedback(text: String, tone: String)
signal state_changed

const STATE_INSPECT := "inspect"
const STATE_HAULING := "hauling"
const STATE_ALIGNED := "aligned"
const STATE_LOCKED := "locked"

const HOOK_RANGE: float = 3.4

@export var winch_path: NodePath
@export var rail_path: NodePath
@export var cable_path: NodePath
@export var sheave_path: NodePath
@export var player_path: NodePath

var winch: Node3D
var rail: Node3D
var cable: Node3D
var sheave: Node3D
var player: Node3D

var mission_state: String = STATE_INSPECT
var completed: bool = false
var completion_count: int = 0
var last_alignment: Dictionary = {}
var last_tension: Dictionary = {}
var last_lock: Dictionary = {}
var feedback_log: Array[Dictionary] = []
var stability_log: Array[Dictionary] = []
var _tick_index: int = 0
var _max_angular_speed: float = 0.0
var _max_tension: float = 0.0
var _max_angle_step: float = 0.0
var _previous_angle: float = 0.0
var _peak_frame_jitter: float = 0.0
var _last_clutch_report: int = -9999

func _ready() -> void:
	winch = _resolve(winch_path, "winch_machine")
	rail = _resolve(rail_path, "misaligned_rail")
	cable = _resolve(cable_path, "")
	sheave = _resolve(sheave_path, "")
	player = _resolve(player_path, "player")
	if winch == null or rail == null:
		push_error("WinchRig: winch or rail missing")
		return
	winch.connect("overload_started", _on_overload_started)
	winch.connect("overload_cleared", _on_overload_cleared)
	winch.connect("clutch_slipped", _on_clutch_slipped)
	winch.connect("limit_reached", _on_limit_reached)
	winch.connect("hook_connected", _on_hook_connected)
	winch.connect("brake_changed", _on_brake_changed)
	rail.connect("overshoot", _on_overshoot)
	rail.connect("lock_installed", _on_lock_installed)
	rail.connect("lock_refused", _on_lock_refused)
	rail.connect("angle_limited", _on_angle_limited)
	rail.connect("jam_broken", _on_jam_broken)
	rail.connect("jam_stalled", _on_jam_stalled)
	_previous_angle = float(rail.get("hinge_angle"))
	_refresh_states()

func _resolve(path: NodePath, group: String) -> Node3D:
	if path != NodePath() and has_node(path):
		return get_node(path) as Node3D
	if group.is_empty():
		return null
	var found: Array[Node] = get_tree().get_nodes_in_group(group)
	if found.is_empty():
		return null
	return found[0] as Node3D

# --- physics ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if winch == null or rail == null:
		return
	var attached: bool = bool(winch.get("attached"))
	if not attached:
		winch.call("tick", delta)
		if cable != null:
			cable.call("update_cable", sheave_position(), _idle_hook_position(), 0.0, 0.0, false)
		_refresh_states()
		return

	var anchor: Node3D = winch.get("anchor") as Node3D
	if anchor == null:
		return
	var anchor_local: Vector3 = rail.to_local(anchor.call("attach_point") as Vector3)
	var sheave_at: Vector3 = sheave_position()

	winch.call("tick", delta)
	var free_length: float = float(winch.get("free_length"))
	var max_force: float = float(winch.get("max_force"))
	var result: Dictionary = rail.call("solve_cable", delta, sheave_at, free_length, max_force, anchor_local) as Dictionary
	winch.call("observe_tension", float(result.get("tension", 0.0)), delta)

	if cable != null:
		var hook_world: Vector3 = rail.call("attach_world", anchor_local) as Vector3
		var distance: float = hook_world.distance_to(sheave_at)
		var slack: float = maxf(0.0, free_length - distance)
		var ratio: float = float(winch.call("tension_ratio"))
		cable.call("update_cable", sheave_at, hook_world, slack, ratio, true)

	_track_stability(delta)
	_refresh_states()

func _track_stability(_delta: float) -> void:
	_tick_index += 1
	var speed: float = absf(float(rail.get("angular_velocity")))
	var tension: float = float(rail.get("tension_estimate"))
	_max_angular_speed = maxf(_max_angular_speed, speed)
	_max_tension = maxf(_max_tension, tension)
	var angle: float = float(rail.get("hinge_angle"))
	_max_angle_step = maxf(_max_angle_step, absf(angle - _previous_angle))
	_previous_angle = angle
	if _tick_index % 10 == 0:
		stability_log.append({
			"tick": _tick_index,
			"angle_deg": rad_to_deg(angle),
			"angular_speed": speed,
			"tension": tension,
			"stretch": float(rail.get("stretch")),
			"free_length": float(winch.get("free_length")),
		})
		if stability_log.size() > 240:
			stability_log.pop_front()

func _idle_hook_position() -> Vector3:
	return sheave_position() + Vector3.DOWN * 1.1

func sheave_position() -> Vector3:
	if sheave != null:
		return sheave.global_position
	if winch != null:
		return winch.global_position + Vector3.UP * 1.45
	return global_position

# --- public API ------------------------------------------------------------

func attach_cable(anchor_id: String) -> Dictionary:
	if completed:
		return {"ok": false, "reason": "轨道已经修好，缆绳已回收", "anchor": anchor_id}
	var anchor: Node3D = find_anchor(anchor_id)
	if anchor == null:
		return {"ok": false, "reason": "没有找到这个锚点", "anchor": anchor_id}
	if player != null:
		var reach: float = (player as Node3D).global_position.distance_to(anchor.call("attach_point") as Vector3)
		if reach > HOOK_RANGE:
			_report("离锚点太远，走近再挂缆绳", "warn")
			return {"ok": false, "reason": "too_far", "anchor": anchor_id}
	var refusal: String = str(anchor.call("refusal_reason"))
	if not refusal.is_empty():
		_report(refusal, "error")
		return {"ok": false, "reason": refusal, "anchor": anchor_id}
	if not bool(anchor.call("can_attach")):
		_report("这个锚点不能挂缆绳", "error")
		return {"ok": false, "reason": "not_attachable", "anchor": anchor_id}
	winch.call("attach_hook", anchor)
	anchor.call("mark_attached")
	# The hook has to reach the eye: feeding out on connect means the player
	# starts from a slack cable instead of an instant 105% tension spike.
	var reach: float = (anchor.call("attach_point") as Vector3).distance_to(sheave_position())
	winch.call("feed_to", reach + 0.45)
	mission_state = STATE_HAULING
	_report("缆绳已挂上 %s，回到绞盘按 W 收缆" % str(anchor.call("describe")), "ok")
	state_changed.emit()
	return {"ok": true, "reason": "", "anchor": anchor_id}

func detach_cable() -> void:
	if winch == null:
		return
	var anchor: Node3D = winch.get("anchor") as Node3D
	if anchor != null:
		anchor.call("mark_detached")
	winch.call("detach_hook")
	if not completed:
		mission_state = STATE_INSPECT
	_report("缆绳已松开，轨道会停在当前位置", "info")
	state_changed.emit()

func find_anchor(anchor_id: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("winch_anchor"):
		var anchor: Node3D = node as Node3D
		if anchor != null and str(anchor.get("anchor_id")) == anchor_id:
			return anchor
	return null

func anchor_ids() -> Array[String]:
	var ids: Array[String] = []
	for node: Node in get_tree().get_nodes_in_group("winch_anchor"):
		var anchor: Node3D = node as Node3D
		if anchor != null:
			ids.append(str(anchor.get("anchor_id")))
	return ids

func set_winch_input(action: String, pressed: bool) -> void:
	if winch == null:
		return
	match action:
		"haul":
			winch.call("set_haul", pressed)
		"payout":
			winch.call("set_payout", pressed)
		"creep":
			winch.call("set_creep", pressed)
		_:
			push_warning("WinchRig: unknown winch input " + action)

func toggle_brake() -> void:
	if winch != null:
		winch.call("toggle_brake")

func try_install_lock() -> Dictionary:
	if completed:
		return {"ok": false, "reason": "已经修好了"}
	var result: Dictionary = rail.call("install_lock") as Dictionary
	last_lock = result
	if bool(result.get("ok")):
		completed = true
		completion_count += 1
		mission_state = STATE_LOCKED
		_report("锁定销已插入，轨道复位。通路恢复。", "success")
		mission_completed.emit()
		state_changed.emit()
	return result

func reset_mission() -> void:
	if winch != null:
		var anchor: Node3D = winch.get("anchor") as Node3D
		if anchor != null:
			anchor.call("mark_detached")
		winch.call("reset")
	if rail != null:
		rail.call("reset")
	completed = false
	mission_state = STATE_INSPECT
	_tick_index = 0
	_max_angular_speed = 0.0
	_max_tension = 0.0
	_max_angle_step = 0.0
	_peak_frame_jitter = 0.0
	_last_clutch_report = -9999
	_previous_angle = float(rail.get("hinge_angle")) if rail != null else 0.0
	stability_log.clear()
	last_lock = {}
	_report("任务已重置：轨道回到错位位置，缆绳已收回", "info")
	state_changed.emit()

func tension_state() -> Dictionary:
	if winch == null:
		return {}
	last_tension = winch.call("snapshot") as Dictionary
	return last_tension

func alignment_state() -> Dictionary:
	if rail == null:
		return {}
	last_alignment = rail.call("snapshot") as Dictionary
	return last_alignment

func lock_state() -> Dictionary:
	return {
		"locked": completed,
		"lock_pin": rail.get("lock_pin") if rail != null else false,
		"state": mission_state,
		"completions": completion_count,
	}

func rig_snapshot() -> Dictionary:
	return {
		"state": mission_state,
		"completed": completed,
		"completions": completion_count,
		"winch": tension_state(),
		"rail": alignment_state(),
		"lock": lock_state(),
		"stability": {
			"max_angular_speed": _max_angular_speed,
			"max_tension": _max_tension,
			"max_angle_step": _max_angle_step,
			"ticks": _tick_index,
		},
	}

func _refresh_states() -> void:
	if completed:
		mission_state = STATE_LOCKED
		return
	var info: Dictionary = rail.call("alignment") as Dictionary
	last_alignment = info
	if bool(info.get("in_band")):
		mission_state = STATE_ALIGNED
	elif bool(winch.get("attached")):
		mission_state = STATE_HAULING
	else:
		mission_state = STATE_INSPECT

func _report(text: String, tone: String) -> void:
	feedback_log.append({"text": text, "tone": tone, "time": Time.get_ticks_msec()})
	if feedback_log.size() > 24:
		feedback_log.pop_front()
	feedback.emit(text, tone)

# --- signal handlers -------------------------------------------------------

func _on_overload_started() -> void:
	_report("张力接近上限，继续硬拉会让离合器打滑", "warn")

func _on_overload_cleared() -> void:
	_report("张力回到安全范围", "info")

func _on_clutch_slipped() -> void:
	# The clutch slips once per tick while the machine sits at its rating. Report
	# the state, not every slip, or the player gets a wall of identical errors.
	var now: int = Time.get_ticks_msec()
	if now - _last_clutch_report < 2500:
		return
	_last_clutch_report = now
	var jammed: bool = rail != null and bool(rail.get("jammed"))
	if jammed:
		_report("离合器打滑：轨道还卡在碎石里，这个吊耳拉不动", "error")
	else:
		_report("离合器到极限：绞盘打滑，收缆变慢", "warn")

func _on_limit_reached(limit_name: String) -> void:
	if limit_name == "drum_full":
		_report("卷线轮已经收到底", "warn")
	elif limit_name == "drum_empty":
		_report("缆绳已经放到头", "warn")

func _on_hook_connected(anchor_name: String) -> void:
	_report("缆绳张紧装置咬合：%s" % anchor_name, "info")

func _on_brake_changed(engaged: bool) -> void:
	_report("鼓式刹车已锁死" if engaged else "鼓式刹车已释放", "info")

func _on_overshoot() -> void:
	_report("拉过头了！轨道越过复位线，按 S 反向放线", "error")

func _on_lock_installed() -> void:
	pass

func _on_lock_refused(reason: String) -> void:
	_report(reason, "error")

func _on_angle_limited(limit_name: String) -> void:
	if limit_name == "far_stop":
		_report("轨道顶到行程限位", "warn")
	elif limit_name == "near_stop":
		_report("轨道顶到反向限位", "warn")

func _on_jam_broken() -> void:
	_report("轨道脱开碎石，开始转动", "ok")

func _on_jam_stalled() -> void:
	_report("绞盘拉不动：这个连接点力臂不够，轨道几乎没动", "error")
