extends Node

# -----------------------------------------------------------------------------
# LevelFlow - the mission brain for the continuous Resonance 02 -> 03 chapter.
#
# It owns NO physics and NO geometry. Everything it reports is derived from the
# cart governor, the winch rig and the player's position, so the displayed phase
# can never disagree with what the player can actually do:
#
#   board  -> ride -> fault -> repair -> locked -> reride -> done
#
# Interaction contract (single E key, chosen by proximity then context):
#   * off the deck, before the cable is hooked -> nearest lifting eye wins
#   * cable hooked                             -> nearest of lock socket / console
#   * on the deck                              -> handled by moving_stage (grip,
#                                                 departure console, cargo)
# That ordering is the fix for the prototype's "the lock socket steals the hook"
# bug, and it is why the two control sets can share one key without conflict.
#
# Held controls (W/S/Shift) are polled only while the console is taken over, and
# taking over the console locks the character's locomotion, so "W" can never
# mean both "walk" and "haul" in the same frame.
# -----------------------------------------------------------------------------

signal phase_changed(phase: String, previous: String)

const SFX: Dictionary = {
	"error": preload("res://act23/assets/audio/error.wav"),
	"latch": preload("res://act23/assets/audio/latch.wav"),
	"ready": preload("res://act23/assets/audio/ready.wav"),
	"segment": preload("res://act23/assets/audio/segment.wav"),
	"hum": preload("res://act23/assets/audio/hum.wav"),
}

const PHASE_BOARD: String = "board"
const PHASE_RIDE: String = "ride"
const PHASE_FAULT: String = "fault"
const PHASE_REPAIR: String = "repair"
const PHASE_LOCKED: String = "locked"
const PHASE_RERIDE: String = "reride"
const PHASE_DONE: String = "done"
# MECHANICS-003A: 矿车已到晶体门但还没完成真实停靠（夹钳压住 + 销子到位）
const PHASE_DOCK: String = "dock"

const HOOK_RANGE: float = 3.4
const DOCK_RANGE: float = 2.4
const CONSOLE_RANGE: float = 2.9
const LOCK_RANGE: float = 2.6
const DECK_SPAWN := Vector3(1.0, 0.38, -2.0)

var stage: Node3D
var cart: AnimatableBody3D
var player: CharacterBody3D
var yard: Node3D
var rig: Node3D

var phase: String = PHASE_BOARD
var at_console: bool = false
# Slot that currently owns the drum. `at_console` is kept as "somebody owns it"
# because the HUD and the regression tests read it that way; the owner id is what
# the network and the participation record need.
var console_actor: int = 0
var local_slot: int = 1
var paused: bool = false
var objective_text: String = ""
var prompt_text: String = ""
var near: Dictionary = {}
var history: Array[Dictionary] = []
var console_entries: int = 0
var wrong_eye_attempts: int = 0
var clock: float = 0.0
# Continuous drum input for THIS tick. It is written by whoever owns the console
# (the host player's keyboard, or CoopNet for a client) and read exactly once by
# _poll_winch, so two players can never both think they are hauling.
var winch_cmd: Dictionary = {"haul": false, "payout": false, "creep": false}
var _approach_warned: bool = false
var _alarm: AudioStreamPlayer3D
var _one_shot: AudioStreamPlayer
var _hum: AudioStreamPlayer3D
var _strain: AudioStreamPlayer3D
var _slip_timer: float = 0.0
var _last_phase: String = ""

func setup(stage_node: Node3D, cart_node: AnimatableBody3D, player_node: CharacterBody3D, yard_node: Node3D) -> void:
	stage = stage_node
	cart = cart_node
	player = player_node
	yard = yard_node
	rig = yard.get("rig") as Node3D
	_build_audio()
	if rig != null:
		rig.connect("feedback", _on_rig_feedback)
		rig.connect("mission_completed", _on_mission_completed)

func _build_audio() -> void:
	var at: Vector3 = yard.to_global(Vector3(0.0, 1.5, 0.0))
	_alarm = AudioStreamPlayer3D.new()
	_alarm.name = "FaultAlarm"
	_alarm.stream = SFX["error"] as AudioStream
	_alarm.volume_db = -26.0
	_alarm.unit_size = 8.0
	_alarm.max_distance = 34.0
	stage.add_child(_alarm)
	_alarm.global_position = at
	_one_shot = AudioStreamPlayer.new()
	_one_shot.name = "WinchLatch"
	_one_shot.stream = SFX["latch"] as AudioStream
	stage.add_child(_one_shot)
	_hum = AudioStreamPlayer3D.new()
	_hum.name = "WinchHum"
	_hum.stream = SFX["hum"] as AudioStream
	_hum.volume_db = -60.0
	_hum.unit_size = 6.0
	_hum.max_distance = 26.0
	stage.add_child(_hum)
	var station: Node3D = yard.get("station") as Node3D
	_hum.global_position = station.global_position if station != null else at
	_strain = AudioStreamPlayer3D.new()
	_strain.name = "WinchStrain"
	_strain.stream = SFX["hum"] as AudioStream
	_strain.volume_db = -60.0
	_strain.unit_size = 7.0
	_strain.max_distance = 26.0
	stage.add_child(_strain)
	_strain.global_position = _hum.global_position

# --- derived state ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	if cart == null or rig == null:
		return
	if paused:
		_apply_winch_cmd()
		return
	if bool(rig.get("network_client")):
		# A client never integrates the rig; the host snapshot is the truth.
		_refresh_prompt_only()
		return
	clock += delta
	_refresh_phase()
	near = _nearest_interaction(player)
	_poll_winch(delta)
	_update_prompt()
	_update_audio(delta)
	if phase != _last_phase:
		history.append({"from": _last_phase, "to": phase, "time": clock,
			"distance": float(cart.get("distance"))})
		_last_phase = phase
		phase_changed.emit(phase, str(history[-1]["from"]))

func _refresh_prompt_only() -> void:
	_refresh_phase()
	near = _nearest_interaction(player)
	_update_prompt()

func _refresh_phase() -> void:
	var distance: float = float(cart.get("distance"))
	var completed: bool = yard.call("completion") as bool
	if bool(cart.get("arrived")):
		var dock_node: Node = stage.get("dock") as Node
		var dock_ready: bool = dock_node == null or bool(dock_node.call("docked"))
		phase = PHASE_DONE if dock_ready else PHASE_DOCK
	elif completed and bool(cart.get("running")):
		phase = PHASE_RERIDE
	elif completed:
		phase = PHASE_LOCKED
	elif bool(cart.get("stopped_for_fault")) or (not bool(cart.get("running")) and distance > 80.0):
		phase = PHASE_REPAIR if _player_off_deck() else PHASE_FAULT
	elif bool(cart.get("running")):
		phase = PHASE_RIDE
	else:
		phase = PHASE_BOARD
	objective_text = _objective_for(phase)

func _player_off_deck(actor: CharacterBody3D = null) -> bool:
	var who: CharacterBody3D = actor if actor != null else player
	if who == null:
		return true
	return not bool(cart.call("contains_point", who.global_position, 0.35))

func _objective_for(which: String) -> String:
	var bend: Node3D = stage.get("bend_event") as Node3D
	var bend_phase: String = str(bend.get("phase")) if bend != null else "idle"
	match which:
		PHASE_BOARD:
			if bool(cart.get("stopped_for_fault")):
				return "矿车已因前方断轨停车 · 沿甲板走到前端，从黄色踏步下车"
			return "登上矿车，到前端控制器按 E 发车"
		PHASE_RIDE:
			if bend_phase == "approaching" or bend_phase == "entering" or bend_phase == "peak":
				return "共振弯道 · 按 E 抓扶稳住，或 B 制动"
			if float(cart.get("distance")) > 70.0:
				return "前方警示灯变红 · 轨道似乎有问题"
			return "行驶中 · 到站前处理松散货物"
		PHASE_FAULT:
			return "矿车停在断轨前 · 沿甲板走到前端下车查看"
		PHASE_REPAIR:
			return _repair_objective()
		PHASE_LOCKED:
			return "线路已机械锁定 · 回到矿车前端控制器按 E 重新发车"
		PHASE_RERIDE:
			return "驶过修复段 · 前往 03 · 晶体矿区入口"
		PHASE_DOCK:
			return "已到晶体门 · 停稳矿车后下到站台，按住 E 把停靠夹钳的闸臂拉到车体侧面，棘爪落位即锁定"
		PHASE_DONE:
			return "已抵达晶体矿区入口 · 停靠夹钳锁定 · 前方的矿道被晶体映亮"
	return ""

func _repair_objective() -> String:
	var winch: Dictionary = rig.call("tension_state") as Dictionary
	var rail: Dictionary = rig.call("alignment_state") as Dictionary
	var attached: bool = bool(winch.get("attached", false))
	if not attached:
		if int(wrong_eye_attempts) > 0:
			return "绞盘拉不动中段吊耳 · 换前端吊耳，或先按 Q 拆缆重挂"
		return "走到断裂处 · 把绞盘缆绳挂上一个吊耳（E）"
	if bool(rail.get("guiding", false)):
		return "锁定销已咬进导向槽 · 定位机构正在把轨道拉回线路…"
	if bool(rail.get("captureable", false)):
		return "轨道进入导向槽 ±5° · 到接收架旁的锁定座按 E 插入锁定销"
	if bool(rail.get("jammed", false)) and bool(winch.get("stalled", false)):
		return "离合器打滑：这个吊耳力臂不够 · 按 Q 拆缆，换到前端吊耳"
	if bool(winch.get("stalled", false)):
		return "绞盘打滑 · 换吊耳（Q 拆缆）或按 S 放线减载"
	return "回到绞盘按 E 接管 · W 收缆 / S 放线 · 空格刹车"

func _update_prompt() -> void:
	var text: String = ""
	if at_console:
		if int(console_actor) == int(local_slot):
			text = "W 收缆 · S 放线 · Shift 微调 · 空格鼓刹 · E 离开绞盘"
		else:
			text = "玩家 %d 正在操作绞盘 · 去导向轮（E）或锁定座" % console_actor
	else:
		match str(near.get("kind", "")):
			"anchor":
				var anchor: Node3D = near.get("anchor") as Node3D
				text = "E 连接缆绳 · %s" % str(anchor.get("display_name"))
			"lock":
				var rail: Dictionary = rig.call("alignment_state") as Dictionary
				if bool(rail.get("guiding", false)):
					text = "导向槽正在把轨道拉回线路…"
				elif bool(rail.get("captureable", false)):
					text = "E 插入锁定销 · 导向槽咬合"
				else:
					text = "E 检查锁定机构 · 还差 %.1f°" % absf(float(rail.get("angle_deg", 0.0)))
			"console":
				if at_console:
					text = "玩家 %d 正在操作绞盘" % console_actor
				else:
					text = "E 接管绞盘"
			"guide":
				if int(rig.get("guide_holder")) == int(local_slot):
					text = "已握住导向轮 · E 松开"
				else:
					text = "E 握住导向轮 · 把轨道头带正（另一人去收缆）"
			"bracket":
				if int(rig.get("bracket_holder")) == int(local_slot):
					text = "安全支架已撑住 · E 收起"
				else:
					text = "E 撑起安全支架 · 顶住摆动轨，别人可以放心收缆"
			"dock":
				var dock_node: Node = stage.get("dock") as Node
				var dock_state: Dictionary = dock_node.call("state") as Dictionary
				if bool(dock_state.get("latched", false)):
					text = "E 抬起棘爪 · 停靠已锁定（解除可重试）"
				elif bool(dock_state.get("pulling", false)):
					text = "继续按住 E · 把闸臂压到车体侧面"
				else:
					text = "按住 E 拉住闸臂，压到车体侧面（棘爪会自己落位）"
			"release":
				text = "Q 松开缆绳"
			_:
				text = ""
	prompt_text = text

# --- interactions ----------------------------------------------------------

# One E key, resolved by distance then by context FOR THIS ACTOR. Two players
# standing at different machines get different answers in the same frame, and a
# machine behind a wall is rejected by line-of-sight before distance is even
# considered.
func _nearest_interaction(actor: CharacterBody3D = null) -> Dictionary:
	var best: Dictionary = {"kind": "", "distance": 1.0e9, "anchor": null}
	var who: CharacterBody3D = actor if actor != null else player
	if who == null or rig == null:
		return best
	var winch: Dictionary = rig.call("tension_state") as Dictionary
	var attached: bool = bool(winch.get("attached", false))
	var completed: bool = yard.call("completion") as bool
	# Co-op workstations first: the guide wheel only exists while the line is
	# broken, and it is a different physical object from the drum and the pin.
	for entry: Dictionary in _workstations():
		var at: Vector3 = entry["position"] as Vector3
		var distance: float = who.global_position.distance_to(at)
		if distance <= float(entry["range"]) and distance < float(best["distance"]):
			if _visible_from(who, at):
				best = {"kind": str(entry["kind"]), "distance": distance, "anchor": null}
	if str(best["kind"]) != "":
		return best
	if not attached and not completed:
		for node: Node in get_tree().get_nodes_in_group("winch_anchor"):
			var anchor: Node3D = node as Node3D
			if anchor == null or bool(anchor.get("occupied")):
				continue
			var at: Vector3 = anchor.call("attach_point") as Vector3
			var distance: float = who.global_position.distance_to(at)
			if distance <= HOOK_RANGE and distance < float(best["distance"]) and _visible_from(who, at):
				best = {"kind": "anchor", "distance": distance, "anchor": anchor}
		if str(best["kind"]) == "anchor":
			return best
	var lock_at: Vector3 = yard.call("lock_station_position") as Vector3
	var lock_distance: float = who.global_position.distance_to(lock_at)
	if lock_distance <= LOCK_RANGE and lock_distance < float(best["distance"]) and _visible_from(who, lock_at):
		best = {"kind": "lock", "distance": lock_distance, "anchor": null}
	var console_at: Vector3 = (rig.get("winch") as Node3D).global_position
	var console_distance: float = who.global_position.distance_to(console_at)
	if console_distance <= CONSOLE_RANGE and console_distance < float(best["distance"]) and _visible_from(who, console_at):
		best = {"kind": "console", "distance": console_distance, "anchor": null}
	# Once the cable is hooked, the eye is still the thing you stand at to
	# release it; Q is offered as a prompt, not a competing E target.
	var dock_node: Node = stage.get("dock") as Node
	if dock_node != null:
		var dock_at: Vector3 = dock_node.call("handle_world") as Vector3
		var dock_distance: float = who.global_position.distance_to(dock_at)
		if dock_distance <= DOCK_RANGE and dock_distance < float(best["distance"]) and _visible_from(who, dock_at):
			best = {"kind": "dock", "distance": dock_distance, "anchor": null}
	if attached and str(best["kind"]) == "":
		var machine: Node3D = rig.get("winch") as Node3D
		var anchor: Node3D = machine.get("anchor") as Node3D
		if anchor != null:
			var at: Vector3 = anchor.call("attach_point") as Vector3
			if who.global_position.distance_to(at) <= HOOK_RANGE:
				best = {"kind": "release", "distance": 0.0, "anchor": anchor}
	return best

# Physical co-op workstations built by the repair yard. They are queried from the
# yard itself so this file never hard-codes their coordinates.
func _workstations() -> Array:
	if yard == null or not yard.has_method("workstations"):
		return []
	return yard.call("workstations") as Array

func _visible_from(actor: CharacterBody3D, target: Vector3) -> bool:
	# Eye-line test against the solid world only (layer 1 + 6). A machine cannot
	# be operated through a wall, a floor or the cart hull. The last 0.45 m are
	# excluded because the target itself is a solid prop: hitting the winch's own
	# housing is not an obstruction, hitting the wall behind it is.
	var from: Vector3 = actor.global_position + Vector3.UP * 1.25
	var to: Vector3 = target
	var span: float = from.distance_to(to)
	if span < 3.0:
		# Inside interaction reach the prop's own collider is what a ray would hit
		# first, and there is no room for a wall to be in between. The eye-line
		# test only guards the long hook reach.
		return true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 7, [actor.get_rid()])
	var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var hit_distance: float = from.distance_to(hit["position"] as Vector3)
	return hit_distance >= span - 0.45

func try_interact(actor: CharacterBody3D = null) -> bool:
	var who: CharacterBody3D = actor if actor != null else player
	if who == null:
		return false
	var actor_id: int = int(who.get("peer_id"))
	if at_console and int(console_actor) == actor_id:
		_leave_console()
		return true
	near = _nearest_interaction(who)
	match str(near.get("kind", "")):
		"anchor":
			var anchor: Node3D = near.get("anchor") as Node3D
			var result: Dictionary = rig.call("attach_cable", str(anchor.get("anchor_id")), who) as Dictionary
			if bool(result.get("ok", false)):
				_play(_one_shot, -6.0)
				stage.call("record", "hook", actor_id)
				return true
			_play_one_shot("error", -12.0)
			return true
		"lock":
			var lock_result: Dictionary = rig.call("try_install_lock") as Dictionary
			if bool(lock_result.get("ok", false)):
				_play_one_shot("ready", -5.0)
				stage.call("record", "lock", actor_id)
			else:
				_play_one_shot("error", -12.0)
			return true
		"console":
			_enter_console(who)
			return true
		"release":
			release_cable(actor_id)
			return true
		"guide":
			return _toggle_guide(who)
		"bracket":
			return _toggle_bracket(who)
		"dock":
			var dock_node: Node = stage.get("dock") as Node
			var dock_result: Dictionary = dock_node.call("operate") as Dictionary
			if bool(dock_result.get("ok", false)):
				stage.call("record", "dock", actor_id)
				match str(dock_result.get("action", "")):
					"released":
						stage.set("feedback", "棘爪抬起 · 配重把闸臂抬回竖起位，停靠解除")
						_play_one_shot("segment", -8.0)
					"pulling":
						stage.set("feedback", "拉住闸臂了 · 按住 E 继续往下压，到车侧棘爪会自己落位")
					_:
						stage.set("feedback", "闸臂已压到车侧 · 棘爪正在落位")
						_play_one_shot("ready", -6.0)
			else:
				stage.set("feedback", str(dock_result.get("reason", "现在还够不到停靠夹钳")))
				_play_one_shot("error", -12.0)
			return true
	return false

# The guide wheel: a real hand wheel on the receiver that steers the swing nose.
# While held it adds a bounded corrective torque (see WinchRig) and widens the
# pin's capture window by 2 degrees. One player can leave it and run round to the
# drum; two players can steer and haul at the same time.
func _toggle_guide(actor: CharacterBody3D) -> bool:
	var actor_id: int = int(actor.get("peer_id"))
	if int(rig.get("guide_holder")) == actor_id:
		rig.call("release_guide")
		# Letting go has to give the body back. Taking the wheel locks
		# locomotion (the worm gear owns the stance), and nothing else cleared
		# that lock: on the host / in a solo run the operator stayed frozen on
		# the spot after "E 松开" and could never walk back to the cart. A
		# client only looked healthy because _mirror_local_ownership rewrites
		# this flag from every snapshot.
		actor.set("interaction_locked", false)
		actor.set("fp_console", false)
		stage.set("feedback", "已松开导向轮 · 轨道保持当前位置")
		return true
	var result: Dictionary = rig.call("hold_guide", actor_id, actor) as Dictionary
	if bool(result.get("ok", false)):
		actor.set("interaction_locked", true)
		actor.set("fp_console", true)
		stage.call("record", "guide", actor_id)
		stage.set("feedback", "已握住导向轮 · 轨道会被导向槽带正 · E 松开")
		return true
	print("GUIDE_REFUSED actor=", actor_id, " reason=", result.get("reason"))
	stage.set("feedback", str(result.get("reason", "无法握住导向轮")))
	_play_one_shot("error", -14.0)
	return false

# The safety bracket: a hinged steel prop that pins the swing section against
# the receiver while somebody else works the drum. It is not a second lock: it
# only holds the section, so it must be folded away before the pin can land.
func _toggle_bracket(actor: CharacterBody3D) -> bool:
	var actor_id: int = int(actor.get("peer_id"))
	if int(rig.get("bracket_holder")) == actor_id:
		rig.call("release_bracket")
		stage.set("feedback", "已收起安全支架 · 轨道仍可继续调整")
		return true
	var result: Dictionary = rig.call("set_bracket", actor_id, actor) as Dictionary
	if bool(result.get("ok", false)):
		stage.call("record", "bracket", actor_id)
		stage.set("feedback", "安全支架已撑住轨道 · 别人可以放心收缆 · E 收起")
		return true
	stage.set("feedback", str(result.get("reason", "这里还撑不住支架")))
	_play_one_shot("error", -14.0)
	return false

func _enter_console(actor: CharacterBody3D = null) -> void:
	var who: CharacterBody3D = actor if actor != null else player
	if who == null:
		return
	if yard.call("completion") as bool:
		stage.set("feedback", "线路已经修好并锁定，绞盘已卸荷。回到矿车前端控制器按 E 重新发车。")
		return
	# One drum, one operator. The second player is told who has it instead of
	# silently taking over, and can take over the moment it is free.
	if at_console and int(console_actor) != int(who.get("peer_id")):
		stage.set("feedback", "玩家 %d 正在操作绞盘 · 你可以去导向轮或锁定座" % console_actor)
		return
	at_console = true
	console_actor = int(who.get("peer_id"))
	console_entries += 1
	who.set("interaction_locked", true)
	# Read only by first_person_rig: the hands rest on the drum while the
	# console is taken over. It has no gameplay authority.
	who.set("fp_console", true)
	_play_one_shot("segment", -12.0)
	stage.call("record", "console", console_actor)
	stage.set("feedback", "已接管绞盘 · W 收缆 / S 放线 / 空格鼓刹 / E 离开")

func _leave_console() -> void:
	if console_actor != 0:
		var holder: Node = (stage.get("actors") as Dictionary).get(console_actor)
		if holder != null:
			holder.set("interaction_locked", false)
			holder.set("fp_console", false)
	at_console = false
	console_actor = 0
	winch_cmd = {"haul": false, "payout": false, "creep": false}
	if rig != null:
		rig.call("set_winch_input", "haul", false)
		rig.call("set_winch_input", "payout", false)
		rig.call("set_winch_input", "creep", false)
	stage.set("feedback", "已离开绞盘 · 缆绳保持当前长度")

func release_cable(actor_id: int = 1) -> void:
	if rig == null:
		return
	rig.call("detach_cable")
	_play(_one_shot, -10.0)
	if at_console:
		_leave_console()
	stage.call("record", "winch_release", actor_id)
	stage.set("feedback", "缆绳已松开 · 轨道停在当前位置，可以换吊耳或重新挂缆")

func leave_console(actor_id: int = 0) -> void:
	if at_console and (actor_id == 0 or int(actor_id) == int(console_actor)):
		_leave_console()

func release_slot(slot: int) -> void:
	if console_actor == slot:
		_leave_console()
	if rig != null:
		rig.call("release_slot", slot)

func console_owned_by(slot: int) -> bool:
	return at_console and int(console_actor) == int(slot)

func set_local_slot(slot: int) -> void:
	local_slot = slot

func set_local_winch_input(haul: bool, payout: bool, creep: bool) -> void:
	if not console_owned_by(local_slot):
		return
	winch_cmd = {"haul": haul, "payout": payout, "creep": creep}

func set_remote_winch_input(slot: int, haul: bool, payout: bool, creep: bool) -> void:
	if not console_owned_by(slot):
		return
	winch_cmd = {"haul": haul, "payout": payout, "creep": creep}

# --- winch polling ---------------------------------------------------------

func _poll_winch(delta: float) -> void:
	if rig == null:
		return
	if at_console:
		var machine: Node3D = rig.get("winch") as Node3D
		var holder: Node = (stage.get("actors") as Dictionary).get(console_actor)
		if machine != null and holder != null:
			var distance: float = (holder as Node3D).global_position.distance_to(machine.global_position)
			if distance > CONSOLE_RANGE + 1.1:
				_leave_console()
	if not at_console:
		_apply_winch_cmd()
		return
	_apply_winch_cmd()
	# Working the drum is real work, recorded by the slot that owns it.
	if bool(winch_cmd.get("haul", false)) or bool(winch_cmd.get("payout", false)):
		stage.call("record", "winch", console_actor)

func _apply_winch_cmd() -> void:
	if rig == null:
		return
	var active: bool = at_console
	rig.call("set_winch_input", "haul", bool(winch_cmd.get("haul", false)) if active else false)
	rig.call("set_winch_input", "payout", bool(winch_cmd.get("payout", false)) if active else false)
	rig.call("set_winch_input", "creep", bool(winch_cmd.get("creep", false)) if active else false)

# --- audio -----------------------------------------------------------------

func _update_audio(delta: float) -> void:
	if _alarm != null:
		# Approach claxon only: it warns the rider before the governor stops the
		# cart, then falls silent so the yard's own beacons carry the state.
		var distance: float = float(cart.get("distance"))
		var speed: float = float(cart.get("speed"))
		var near_fault: bool = distance > 70.0 and distance < 88.6 and speed > 0.08
		if near_fault and not _alarm.playing:
			_alarm.play()
		_alarm.volume_db = lerpf(_alarm.volume_db, -22.0 if near_fault else -60.0, 0.08)
		if _alarm.volume_db < -55.0 and _alarm.playing:
			_alarm.stop()
	if _hum == null:
		return
	var winch: Dictionary = rig.call("tension_state") as Dictionary
	var mode: String = str(winch.get("mode", "idle"))
	var ratio: float = float(winch.get("tension_ratio", 0.0))
	var active: bool = (mode == "haul" or mode == "payout" or mode == "stall") and at_console
	var hum_target: float = -13.0 if active else -60.0
	if active and not _hum.playing:
		_hum.play()
	_hum.pitch_scale = 0.85 + ratio * 0.55
	_hum.volume_db = lerpf(_hum.volume_db, hum_target, 0.12)
	if _hum.volume_db < -55.0 and _hum.playing:
		_hum.stop()
	var strain_target: float = -60.0
	if bool(winch.get("attached", false)) and (ratio > 0.45 or bool(winch.get("stalled", false))):
		strain_target = -25.0 + ratio * 9.0
		if not _strain.playing:
			_strain.play()
	_strain.pitch_scale = 0.58 + ratio * 0.18
	_strain.volume_db = lerpf(_strain.volume_db, strain_target, 0.08)
	if _strain.volume_db < -55.0 and _strain.playing:
		_strain.stop()
	if bool(winch.get("stalled", false)) and at_console:
		_slip_timer -= delta
		if _slip_timer <= 0.0:
			_slip_timer = 1.2
			_play_one_shot("error", -20.0)
	else:
		_slip_timer = 0.0

func _play(player_node: AudioStreamPlayer, volume_db: float) -> void:
	if player_node == null:
		return
	player_node.volume_db = volume_db
	player_node.play()

func _play_one_shot(sound: String, volume_db: float) -> void:
	if _one_shot == null:
		return
	var stream: AudioStream = SFX.get(sound) as AudioStream
	if stream == null:
		return
	_one_shot.stream = stream
	_one_shot.volume_db = volume_db
	_one_shot.play()

# --- signals ---------------------------------------------------------------

func _on_rig_feedback(text: String, tone: String) -> void:
	stage.set("feedback", text)
	if tone == "error":
		_play_one_shot("error", -16.0)
		var winch: Dictionary = rig.call("tension_state") as Dictionary
		if bool(winch.get("stalled", false)):
			wrong_eye_attempts += 1

func _on_mission_completed() -> void:
	if cart != null and multiplayer.is_server():
		cart.call("release_route")
	_release_workstations()
	_leave_console()
	_play_one_shot("ready", -4.0)
	stage.set("feedback", "轨道已锁定复位 · 线路恢复。回到矿车前端控制器按 E 重新发车。")

# The hand wheel and the safety prop only exist while the line is broken:
# RepairYard.workstations() stops reporting them the moment the yard reports
# completion. A seat that is still registered as a holder could then neither let
# go (the same E key now falls through to "release cable") nor walk again on the
# authoritative side, and net_state kept publishing a holder for a device that is
# no longer offered. Clear every holder - and its locomotion lock - together
# with the console so the crew can walk back to the cart and re-board.
func _release_workstations() -> void:
	if rig == null:
		return
	var slots: Array = []
	var guide: int = int(rig.get("guide_holder"))
	if guide != 0:
		slots.append(guide)
		rig.call("release_guide")
	var bracket: int = int(rig.get("bracket_holder"))
	if bracket != 0:
		slots.append(bracket)
		rig.call("release_bracket")
	for slot: int in slots:
		var actor: Node = (stage.get("actors") as Dictionary).get(slot)
		if actor != null and is_instance_valid(actor):
			actor.set("interaction_locked", false)
			actor.set("fp_console", false)

func _release_locomotion() -> void:
	if player != null:
		player.set("interaction_locked", false)

# --- reset -----------------------------------------------------------------

func reset_all() -> void:
	if rig != null:
		rig.call("set_winch_input", "haul", false)
		rig.call("set_winch_input", "payout", false)
		rig.call("set_winch_input", "creep", false)
		rig.call("reset_mission")
	winch_cmd = {"haul": false, "payout": false, "creep": false}
	at_console = false
	console_actor = 0
	wrong_eye_attempts = 0
	phase = PHASE_BOARD
	_last_phase = PHASE_BOARD
	_approach_warned = false
	if cart != null:
		cart.call("reset_run")
	for slot: int in (stage.get("actors") as Dictionary):
		var actor: Node = (stage.get("actors") as Dictionary)[slot] as Node
		actor.set("fp_console", false)
		actor.set("interaction_locked", false)
	if player != null:
		player.call("restore_at", DECK_SPAWN)
	if _alarm != null:
		_alarm.stop()

# --- network mirror (client side) ------------------------------------------

func apply_net_state(snapshot: Dictionary) -> void:
	phase = str(snapshot.get("phase", phase))
	objective_text = str(snapshot.get("objective", objective_text))
	prompt_text = str(snapshot.get("prompt", prompt_text))
	var console: int = int(snapshot.get("console", 0))
	if console != console_actor:
		# The client never owns the drum state machine; it only mirrors who does.
		console_actor = console
		at_console = console != 0
	var rig_state: Dictionary = snapshot.get("rig", {}) as Dictionary
	if rig != null and not rig_state.is_empty():
		rig.call("apply_net_state", rig_state)

func net_ui_state() -> Dictionary:
	return {"phase": phase, "objective": objective_text, "prompt": prompt_text,
		"at_console": at_console, "console_actor": console_actor}

func snapshot() -> Dictionary:
	var out: Dictionary = {
		"phase": phase,
		"objective": objective_text,
		"prompt": prompt_text,
		"at_console": at_console,
		"console_actor": console_actor,
		"console_entries": console_entries,
		"wrong_eye_attempts": wrong_eye_attempts,
		"near": str(near.get("kind", "")),
		"history": history,
	}
	if yard != null:
		out["yard"] = yard.call("snapshot")
	return out




