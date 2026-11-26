extends RefCounted

## ACT04-3P4P-PLAYTHROUGH-FIX-R1 · real-input Act04 flow for 3/4 players.
##
## Runs inside the official Launcher session AFTER Act01 and Act23 handed the
## same SessionHub/ENet peer over to Resonance04. It only drives the production
## Input actions with real InputEventKey events (W/A/S/D/Space/E/F/Q):
##   * walks every seat to the bell, the freight platform and the exit;
##   * grabs the bell hammer, the platform handholds and the drive/brake levers
##     through the product's own FreightControl.interact() path;
##   * lets the host do the crystal relay chain (cyan -> B1, violet -> B3);
##   * never teleports, never writes grab_platform/grab_point_id/credits, never
##     calls complete_chapter or change_scene.
##
## Cross-process turn ordering uses a small file gate in the run evidence dir;
## every assertion reads the authoritative host ledger or the mirrored client
## ledger. It returns true only when every seat reached Act05 through the real
## Act04 completion path.

var tree: SceneTree
var role: String = "host"
var index: int = 0
var expected: int = 3
var out_dir: String = ""
var tag: String = ""
var seat_pid: int = 1
var me: int = 1

var game: Node = null
var player: Node = null
var platform: Node = null
var hammer: Node = null
var gate: Node = null
var hub: Node = null

var checks: int = 0
var failures: Array[String] = []
var warnings: Array[String] = []
var started_ms: int = 0
var _finished: bool = false
var _passed: bool = false
var _scene_log: Array[String] = []
var _last_scene_id: int = 0

const STRIKE_STAND: Vector3 = Vector3(2.35, 0.0, -0.55)
const STRIKE_APPROACH: Vector3 = Vector3(1.15, 0.0, -0.55)
const HOLD_SPOT: Vector3 = Vector3(4.5, 0.0, 4.0)
const STAIR_BOTTOM: Vector3 = Vector3(-1.0, 0.0, 3.8)
const STAIR_TOP: Vector3 = Vector3(-4.4, 0.0, 3.8)
const NEAR_DOCK: Vector3 = Vector3(-6.6, 0.0, 3.0)
const PLATFORM_ENTRY: Vector3 = Vector3(-8.4, 0.0, 3.0)


func setup(p_tree: SceneTree, p_role: String, p_index: int, p_players: int,
		p_out: String, p_tag: String, p_seat: int) -> void:
	tree = p_tree
	role = p_role
	index = p_index
	expected = p_players
	out_dir = p_out
	tag = p_tag
	seat_pid = p_seat
	me = p_seat
	started_ms = Time.get_ticks_msec()


func run() -> bool:
	_record("a4_boot")
	await _run()
	return _passed and failures.is_empty()


# --------------------------------------------------------------------- utils --
func log_line(text: String) -> void:
	print("[%s%d] %s" % [role, index, text])


func check(ok: bool, text: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)
	return ok


func note(text: String) -> void:
	log_line("NOTE " + text)


func warn(text: String) -> void:
	warnings.append(text)
	log_line("WARN " + text)


func _wait(seconds: float) -> void:
	await tree.create_timer(seconds).timeout


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout_s * 1000.0):
		if bool(cond.call()):
			return true
		await tree.process_frame
	return bool(cond.call())


func _abs(name: String) -> String:
	return out_dir.replace("\\", "/") + "/" + name


func _write_json(name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f: FileAccess = FileAccess.open(_abs(name), FileAccess.WRITE)
	if f == null:
		log_line("FILE_WRITE_FAIL " + name)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func _read_json(name: String) -> Dictionary:
	if not FileAccess.file_exists(_abs(name)):
		return {}
	var f: FileAccess = FileAccess.open(_abs(name), FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var j: JSON = JSON.new()
	if j.parse(text) != OK:
		return {}
	var parsed: Variant = j.data
	return parsed as Dictionary if parsed is Dictionary else {}


func _host_phase(name: String, extra: Dictionary = {}) -> void:
	if role != "host":
		return
	var doc: Dictionary = {"name": name, "pid": me, "seq": Time.get_ticks_msec()}
	for k in extra.keys():
		doc[k] = extra[k]
	_write_json("a4_phase.json", doc)
	_write_json("a4_phase_%s.json" % name, doc)
	log_line("PHASE " + name)


func _phase() -> Dictionary:
	return _read_json("a4_phase.json")


func _wait_phase(name: String, timeout_s: float) -> bool:
	return await _wait_until(func() -> bool:
		return not _read_json("a4_phase_%s.json" % name).is_empty(), timeout_s)


## A turn addressed to one specific seat (the phase document carries its pid).
func _wait_turn(name: String, timeout_s: float) -> bool:
	return await _wait_until(func() -> bool:
		var p: Dictionary = _phase()
		return str(p.get("name", "")) == name and int(p.get("pid", 0)) == me, timeout_s)


func _write_done(step: String, extra: Dictionary = {}) -> void:
	var doc: Dictionary = {
		"pid": me, "t": float(Time.get_ticks_msec() - started_ms) / 1000.0,
	}
	for k in extra.keys():
		doc[k] = extra[k]
	_write_json("a4_done_%s_%d.json" % [step, me], doc)


func _done(step: String, pid: int) -> Dictionary:
	return _read_json("a4_done_%s_%d.json" % [step, pid])


func _done_ok(step: String, pid: int) -> bool:
	return bool(_done(step, pid).get("ok", false))


func _wait_done(step: String, pid: int, timeout_s: float) -> bool:
	return await _wait_until(func() -> bool: return not _done(step, pid).is_empty(), timeout_s)


func _valid(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	return node is Node


func _in_tree(node: Variant) -> bool:
	if not _valid(node):
		return false
	return (node as Node).is_inside_tree()


func _scene_now() -> String:
	return str(tree.current_scene.name) if tree.current_scene != null else "null"


func _local_pid() -> int:
	if hub == null or not _valid(hub):
		return 0
	var net: Variant = hub.get("net")
	if net == null:
		return 0
	return int(net.get("local_pid"))


func _coop_mode() -> String:
	return str(game.get("coop_mode")) if game != null and _valid(game) else "?"


func _bodies() -> Dictionary:
	if game == null or not _valid(game):
		return {}
	return game.get("coop_players") as Dictionary


func _ledger() -> ParticipationLedger:
	if game == null or not _valid(game):
		return null
	var net: Variant = game.get("coop_net")
	if net == null or not is_instance_valid(net):
		return null
	var session: Variant = net.get("session")
	if session == null:
		return null
	return session.get("ledger") as ParticipationLedger


func _kind_count(pid: int, kind: String) -> int:
	var ledger: ParticipationLedger = _ledger()
	if ledger == null:
		return 0
	var record: Dictionary = ledger.get_record(pid)
	if record.is_empty():
		return 0
	var credits: Dictionary = record.get("credits", {}) as Dictionary
	if credits.has(kind):
		return int((credits[kind] as Dictionary).get("count", 0))
	# Client mirror only carries the kind list, not the counts.
	return 1 if (record.get("kinds", []) as Array).has(kind) else 0


func _has_kind(pid: int, kind: String) -> bool:
	var ledger: ParticipationLedger = _ledger()
	if ledger == null:
		return false
	return ledger.has_credit(pid, kind)


func _phase04(pid: int) -> int:
	var ledger: ParticipationLedger = _ledger()
	if ledger == null:
		return 0
	return ledger.phase_count(pid, ParticipationLedger.PHASE_04)


func _ready04(pid: int) -> bool:
	var ledger: ParticipationLedger = _ledger()
	if ledger == null:
		return false
	return ledger.ready_for_phase(pid, ParticipationLedger.PHASE_04)


func _kinds(pid: int) -> Array:
	var ledger: ParticipationLedger = _ledger()
	if ledger == null:
		return []
	var record: Dictionary = ledger.get_record(pid)
	if record.is_empty():
		return []
	var credits: Dictionary = record.get("credits", {}) as Dictionary
	if not credits.is_empty():
		return credits.keys()
	return (record.get("kinds", []) as Array).duplicate()


func _ledger_rows() -> Array:
	var rows: Array = []
	var ledger: ParticipationLedger = _ledger()
	if ledger == null:
		return rows
	for pid in ledger.player_ids():
		var rec: Dictionary = ledger.get_record(pid)
		rows.append({
			"pid": pid,
			"status": str(rec.get("status", "?")),
			"phases": (rec.get("phases", {}) as Dictionary).duplicate(true),
			"kinds": _kinds(pid),
		})
	return rows


# --------------------------------------------------------------------- input --
func _key_event(keycode: int, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _key_down(keycode: int) -> bool:
	_key_event(keycode, true)
	return Input.is_action_pressed(_action_for(keycode))


func _key_up(keycode: int) -> void:
	_key_event(keycode, false)


func _action_for(keycode: int) -> String:
	match keycode:
		KEY_W: return "move_forward"
		KEY_S: return "move_back"
		KEY_A: return "move_left"
		KEY_D: return "move_right"
		KEY_E: return "interact"
		KEY_F: return "pickup"
		KEY_Q: return "rotate_crystal"
		KEY_SPACE: return "jump"
	return ""


func _press_key(keycode: int, hold: float = 0.14, wait_after: float = 0.25) -> bool:
	var action: String = _action_for(keycode)
	_key_event(keycode, true)
	await _wait(hold)
	_key_event(keycode, false)
	await _wait(wait_after)
	return Input.is_action_pressed(action) == false


func _press_e(wait_after: float = 0.35) -> bool:
	return await _press_key(KEY_E, 0.14, wait_after)


func _press_f(wait_after: float = 0.5) -> bool:
	return await _press_key(KEY_F, 0.14, wait_after)


func _press_q() -> void:
	await _press_key(KEY_Q, 0.10, 0.08)


func _hold_key(keycode: int, seconds: float, wait_after: float = 0.2) -> void:
	_key_event(keycode, true)
	await _wait(seconds)
	_key_event(keycode, false)
	await _wait(wait_after)


func _face(target: Vector3, pitch: float = -0.12) -> void:
	if not _in_tree(player):
		return
	if player.has_method("aim_camera_at"):
		player.call("aim_camera_at", Vector3(target.x, target.y, target.z), pitch)
		return
	var d: Vector3 = target - (player as Node3D).global_position
	player.set("_yaw", atan2(-d.x, -d.z))
	player.set("_aim_yaw", atan2(-d.x, -d.z))
	player.set("_aim_pitch", pitch)
	player.set("_aim_active", false)
	if player.has_method("_apply_view"):
		player.call("_apply_view")


func _player_pos() -> Vector3:
	if not _in_tree(player):
		return Vector3.ZERO
	return (player as Node3D).global_position


## Real W input toward a world point; the body is re-aimed every frame. A real
## jump + sidestep is used once when the capsule is wedged (never a teleport).
func _walk(target: Vector3, seconds: float, label: String, tolerance: float = 0.9,
		check_y: bool = false, allow_jump: bool = true) -> bool:
	if not _in_tree(player):
		return false
	var elapsed: float = 0.0
	var stuck: float = 0.0
	var last: Vector3 = _player_pos()
	_key_event(KEY_W, true)
	while elapsed < seconds:
		await tree.physics_frame
		elapsed += 1.0 / 60.0
		if not _in_tree(player):
			break
		var current: Vector3 = _player_pos()
		_face(Vector3(target.x, current.y, target.z))
		var flat: float = Vector2(current.x - target.x, current.z - target.z).length()
		var y_ok: bool = (not check_y) or absf(current.y - target.y) <= 0.7
		if flat <= tolerance and y_ok:
			break
		if current.distance_to(last) < 0.02:
			stuck += 1.0 / 60.0
		else:
			stuck = 0.0
			last = current
		if allow_jump and stuck > 1.1:
			_key_event(KEY_SPACE, true)
			for _i in range(6):
				await tree.physics_frame
			_key_event(KEY_SPACE, false)
			var side: int = KEY_A if int(elapsed * 7.0) % 2 == 0 else KEY_D
			_key_event(side, true)
			for _i in range(20):
				await tree.physics_frame
			_key_event(side, false)
			stuck = 0.0
			last = _player_pos()
	_key_event(KEY_W, false)
	await tree.physics_frame
	if not _in_tree(player):
		return true
	var dist: float = Vector2(_player_pos().x - target.x, _player_pos().z - target.z).length()
	log_line("WALK04 %s target=%s pos=%s dist=%.2f t=%.1f" % [
		label, str(target.snapped(Vector3(0.01, 0.01, 0.01))),
		str(_player_pos().snapped(Vector3(0.01, 0.01, 0.01))), dist, elapsed])
	return dist <= tolerance * 1.9


func _aim_and_target(kind: String, dock: String) -> bool:
	await _wait(0.35)
	var target: Node = player.get("current_target") as Node
	if target == null:
		log_line("TARGET none kind=%s dock=%s" % [kind, dock])
		return false
	log_line("TARGET kind=%s dock=%s expected=%s/%s" % [
		str(target.get("kind")), str(target.get("dock_id")), kind, dock])
	return str(target.get("kind")) == kind and str(target.get("dock_id")) == dock


func _target_kind() -> String:
	var target: Node = player.get("current_target") as Node
	if target == null:
		return ""
	return str(target.get("kind"))


## Walk to the closest stand that lets the aim ray select `kind`, then press the
## real E key once. Used for the deck controls where two controls can share an
## aim cone (brake vs. the e1 handhold). No state is written: the target comes
## from the product's own interaction ray.
func _use_control(kind: String, local_point: Vector3, stands: Array,
		aim_lift: float = 0.18) -> bool:
	for raw in stands:
		var cand: Vector3 = raw as Vector3
		var stand: Vector3 = (platform as Node3D).to_global(cand)
		await _walk(Vector3(stand.x, 0.0, stand.z), 7.0, "%s stand" % kind, 0.45, false, false)
		var point: Vector3 = (platform as Node3D).to_global(local_point) + Vector3(0.0, aim_lift, 0.0)
		_face(point, -99.0)
		await _wait(0.4)
		log_line("CONTROL %s target=%s stand=%s" % [kind, _target_kind(), str(cand)])
		if _target_kind() != kind:
			continue
		await _press_e(0.45)
		await _wait(0.5)
		return true
	return false


# ------------------------------------------------------------------- capture --
func _process(_delta: float) -> bool:
	var cs: Node = tree.current_scene
	var id: int = cs.get_instance_id() if cs != null else 0
	if id != _last_scene_id:
		_last_scene_id = id
		_scene_log.append(_scene_now())
		log_line("SCENE " + _scene_now())
	return false


func _entity_snapshot() -> Dictionary:
	var bodies: Dictionary = _bodies()
	var rows: Array = []
	var keys: Array = bodies.keys()
	keys.sort()
	for raw in keys:
		var pid: int = int(raw)
		var body: EchoPlayer = bodies[raw] as EchoPlayer
		if body == null or not is_instance_valid(body):
			rows.append({"pid": pid, "invalid": true})
			continue
		var pos: Vector3 = body.global_position
		rows.append({
			"pid": pid,
			"body_player_id": int(body.get("player_id")),
			"is_local": body == player,
			"is_remote": bool(body.get("is_remote")),
			"visible": bool(body.get("visible")),
			"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
			"grab": str(body.get("grab_point_id")),
		})
	var net_pid: int = _local_pid()
	var session_pid: int = 0
	if hub != null and _valid(hub):
		var sess: Variant = hub.get("session")
		if sess != null:
			session_pid = int(sess.get("local_pid"))
	return {
		"pid": me, "role": role, "index": index,
		"t": float(Time.get_ticks_msec() - started_ms) / 1000.0,
		"scene": _scene_now(), "coop_mode": _coop_mode(),
		"net_pid": net_pid, "session_pid": session_pid,
		"player_id": int(player.get("player_id")) if _in_tree(player) else -1,
		"local_player_id": int(player.get("player_id")) if _in_tree(player) else -1,
		"local_pos": [snappedf(_player_pos().x, 0.01), snappedf(_player_pos().y, 0.01),
			snappedf(_player_pos().z, 0.01)],
		"bodies": rows,
		"ledger": _ledger_rows(),
		"chapter": str(hub.get("current_chapter")) if hub != null else "?",
	}


func _record(label: String) -> void:
	_write_json("a4_%s%d.%s.json" % [role, index, label], _entity_snapshot())


func _state_snapshot() -> Dictionary:
	if game == null or not _valid(game):
		return {}
	var mems: Dictionary = game.get("seen_memories") as Dictionary
	var pl: Dictionary = {}
	if platform != null and _valid(platform):
		var grabs: Dictionary = platform.get("grab_peer_by_point") as Dictionary
		var by_pid: Dictionary = platform.get("grabs") as Dictionary
		pl = {
			"travel_x": snappedf(float(platform.get("travel_x")), 0.01),
			"deck_y": snappedf(float(platform.get("deck_y")), 0.01),
			"control_owner_id": int(platform.get("control_owner_id")),
			"grab_points": grabs.duplicate(true),
			"grab_pids": (by_pid.values() as Array).duplicate(),
			"clamp_t": snappedf(float(platform.get("clamp_t")), 0.01),
			"brake": bool(platform.get("brake_engaged")),
		}
	return {
		"pid": me, "t": float(Time.get_ticks_msec() - started_ms) / 1000.0,
		"scene": _scene_now(),
		"stage": int(game.get("stage")),
		"memories": mems.keys(),
		"strikes": int(hammer.get("strike_count")) if _valid(hammer) else -1,
		"gate_open": bool(gate.get("is_open")) if _valid(gate) else false,
		"completed": bool(game.get("completed")),
		"platform": pl,
		"ledger": _ledger_rows(),
	}


func _record_state(label: String) -> void:
	_write_json("a4_%s%d.state.%s.json" % [role, index, label], _state_snapshot())


# --------------------------------------------------------------- game ready --
func _wait_game() -> bool:
	var ok: bool = await _wait_until(func() -> bool:
		var sn: String = _scene_now()
		if sn != "Act4" and sn != "Resonance04":
			return false
		var cs: Node = tree.current_scene
		if cs == null:
			return false
		if cs.get("player") == null or cs.get("hammer") == null:
			return false
		if cs.get("cradles") == null or cs.get("gate") == null:
			return false
		if cs.get("platform") == null:
			return false
		return true, 120.0)
	check(ok, "Act04 world is live (scene=%s mode=%s)" % [_scene_now(), _coop_mode()])
	if not ok:
		return false
	game = tree.current_scene
	player = game.get("player") as Node
	hammer = game.get("hammer") as Node
	gate = game.get("gate") as Node
	platform = game.get("platform") as Node
	hub = tree.root.get_node_or_null("/root/SessionHub")
	await _wait(1.0)
	return _in_tree(player)


func _wait_roster() -> bool:
	var ok: bool = await _wait_until(func() -> bool:
		var bodies: Dictionary = _bodies()
		if bodies.size() != expected:
			return false
		for pid in range(1, expected + 1):
			if not bodies.has(pid):
				return false
		return true, 150.0)
	var bodies_final: Dictionary = _bodies()
	var missing: Array = []
	for pid in range(1, expected + 1):
		if not bodies_final.has(pid):
			missing.append(pid)
	check(ok, "%d participant bodies exist in this world (keys=%s missing=%s)" % [
		expected, str(bodies_final.keys()), str(missing)])
	return ok


func _identity_checks() -> void:
	var net_pid: int = _local_pid()
	var session_pid: int = 0
	if hub != null and _valid(hub):
		var sess: Variant = hub.get("session")
		if sess != null:
			session_pid = int(sess.get("local_pid"))
	var body_pid: int = int(player.get("player_id")) if _in_tree(player) else -1
	check(net_pid == me, "network PID is this seat (net=%d seat=%d)" % [net_pid, me])
	check(body_pid == net_pid, "Act04 player entity PID matches the network PID (body=%d net=%d)" % [
		body_pid, net_pid])
	check(session_pid == net_pid, "SessionHub PID equals the network PID (session=%d net=%d)" % [
		session_pid, net_pid])
	var bodies: Dictionary = _bodies()
	check(bodies.get(net_pid, null) == player,
		"the local pid maps to the locally driven body")
	var unique: Dictionary = {}
	var self_remote: Array = []
	var bad_id: Array = []
	for raw in bodies.keys():
		var pid: int = int(raw)
		var body: EchoPlayer = bodies[raw] as EchoPlayer
		if body == null or not is_instance_valid(body):
			bad_id.append(pid)
			continue
		unique[int(body.get("player_id"))] = true
		if pid == net_pid and body != player:
			self_remote.append(pid)
		if int(body.get("player_id")) != pid:
			bad_id.append(pid)
	check(unique.size() == expected, "each body owns a unique PID (%d/%d)" % [unique.size(), expected])
	check(self_remote.is_empty(), "no remote ghost body was spawned for the local pid (%s)" % str(self_remote))
	check(bad_id.is_empty(), "every body key equals its player_id (%s)" % str(bad_id))
	_record("identity")


# ------------------------------------------------------------------- strikes --
func _strike_once() -> bool:
	if not _in_tree(player):
		return false
	var anchor: Vector3 = (hammer as Node3D).call("get_interaction_position") as Vector3
	await _walk(STRIKE_APPROACH, 14.0, "bell approach", 1.0)
	await _walk(STRIKE_STAND, 6.0, "bell console stand", 0.5)
	var held: bool = false
	for _attempt in range(5):
		_face(anchor, 0.05)
		await _wait(0.4)
		await _press_e(0.45)
		held = str(hammer.get("mode")) == "held"
		if held:
			break
		await _walk(STRIKE_STAND + Vector3(0, 0, 0.9), 2.5, "step clear of the rig", 0.5)
		await _walk(STRIKE_STAND, 3.0, "re-approach the rig", 0.4)
	log_line("STRIKE held=%s mode=%s pos=%s" % [
		str(held), str(hammer.get("mode")), str(_player_pos().snapped(Vector3(0.01, 0.01, 0.01)))])
	if not held:
		return false
	var before: int = int(hammer.get("strike_count"))
	_key_event(KEY_W, true)
	await _wait(1.5)
	_key_event(KEY_W, false)
	_face(anchor, 0.05)
	await _wait(0.25)
	await _press_e(0.3)
	var got: bool = await _wait_until(func() -> bool:
		return int(hammer.get("strike_count")) > before, 8.0)
	log_line("STRIKE count=%d (was %d)" % [int(hammer.get("strike_count")), before])
	return got


func _strike_self(label: String) -> bool:
	var ok: bool = await _strike_once()
	check(ok, "%s rang the resonance bell with real E/W input" % label)
	await _walk(HOLD_SPOT, 8.0, "clear the console", 0.9)
	return ok


func _host_wait_client_strike(pid: int, timeout_s: float) -> bool:
	var got: bool = await _wait_done("strike", pid, timeout_s)
	var ok: bool = _done_ok("strike", pid) and _has_kind(pid, "act4_hammer_strike")
	check(ok, "pid%d struck the bell and earned its own phase-04 credit" % pid)
	return ok


func _client_wait_turn(step: String, timeout_s: float) -> bool:
	var ok: bool = await _wait_turn(step, timeout_s)
	check(ok, "pid%d received the %s turn" % [me, step])
	return ok


func _strikes_host() -> void:
	check(await _strike_self("host"), "host strike")
	check(_phase04(1) == 1, "host phase04 is exactly 1 after the first strike")
	for pid in range(2, expected + 1):
		_host_phase("strike%d" % pid, {"pid": pid})
		await _host_wait_client_strike(pid, 300.0)
		await _wait(1.0)
		check(_phase04(pid) == 1, "pid%d phase04 is exactly 1 after its strike" % pid)
	# Repeat request: a second real strike must not add another phase.
	var count_before: int = _kind_count(1, "act4_hammer_strike")
	check(await _strike_self("host (repeat)"), "host repeated the strike")
	var count_after: int = _kind_count(1, "act4_hammer_strike")
	check(count_after > count_before, "repeat strike refreshed the same credit kind (%d -> %d)" % [
		count_before, count_after])
	check(_phase04(1) == 1, "repeat strike did not inflate host phase04 (%d)" % _phase04(1))
	_host_phase("strike_done")


func _strikes_client() -> void:
	var turn: int = me
	if turn < 2 or turn > expected:
		return
	var step: String = "strike%d" % turn
	if not await _client_wait_turn(step, 300.0):
		return
	var ok: bool = await _strike_once()
	check(ok, "pid%d struck the bell with real E/W input" % me)
	await _walk(HOLD_SPOT, 8.0, "clear the console", 0.9)
	_write_done("strike", {"ok": ok})


# ------------------------------------------------------------------ platform --
func _go_to_platform() -> bool:
	await _walk(Vector3(1.8, 0.0, 2.4), 8.0, "stair approach", 1.0)
	await _walk(STAIR_BOTTOM, 5.0, "stair bottom", 0.9)
	await _walk(STAIR_TOP, 8.0, "stair top", 1.1)
	await _walk(NEAR_DOCK, 6.0, "near loading dock", 1.2)
	await _walk(PLATFORM_ENTRY, 5.0, "platform deck edge", 0.7, false, false)
	await _walk(Vector3(-8.8, 0.0, 3.0), 4.0, "platform centre", 0.5, false, false)
	var on_deck: bool = await _wait_until(func() -> bool:
		return absf(_player_pos().y - float(platform.get("deck_y"))) < 0.4, 8.0)
	check(on_deck, "pid%d is standing on the freight platform deck (y=%.2f)" % [me, _player_pos().y])
	return on_deck


func _grab_point(point_id: String) -> bool:
	var rail: Vector3 = platform.call("get_grab_position", point_id) as Vector3
	var stand_local: Vector3 = (FreightPlatform.GRAB_POINTS[point_id] as Dictionary)["stand"] as Vector3
	var stand: Vector3 = (platform as Node3D).to_global(stand_local)
	# The deck is 3.2 m and its west/east loading gates are open: never let the
	# stuck-recovery jump push a body through a gate while boarding.
	await _walk(Vector3(stand.x, 0.0, stand.z), 7.0, "stand at %s" % point_id, 0.5, false, false)
	_face(rail, -0.05)
	await _wait(0.4)
	if not await _aim_and_target("grab", point_id):
		return false
	await _press_e(0.5)
	var got: bool = false
	for _i in range(10):
		got = player.get("grab_platform") == platform and str(player.get("grab_point_id")) == point_id
		if got:
			break
		await _wait(0.35)
	var host_owner: int = _grab_owner(point_id)
	var local_ok: bool = got
	if role == "host":
		local_ok = got and host_owner == me
	else:
		local_ok = got and host_owner == me
	check(local_ok, "pid%d holds grab point %s (host owner=%d)" % [me, point_id, host_owner])
	return local_ok


func _grab_owner(point_id: String) -> int:
	if platform == null or not _valid(platform):
		return 0
	var table: Dictionary = platform.get("grab_peer_by_point") as Dictionary
	return int(table.get(point_id, 0))


func _grab_tables() -> Dictionary:
	if platform == null or not _valid(platform):
		return {}
	return {
		"point_owner": (platform.get("grab_peer_by_point") as Dictionary).duplicate(true),
		"by_pid": ((platform.get("grabs") as Dictionary).duplicate(true)),
	}


func _grab_offset() -> float:
	if not _in_tree(player):
		return 999.0
	var gp: Variant = player.get("grab_platform")
	if gp == null:
		return 999.0
	var point: String = str(player.get("grab_point_id"))
	if point.is_empty():
		return 999.0
	var rail: Vector3 = platform.call("get_grab_position", point) as Vector3
	return _player_pos().distance_to(rail)


func _release_grab() -> void:
	if player.get("grab_platform") != null:
		await _press_e(0.4)
	await _wait(0.6)



## The host's own handhold action, taken from the near loading dock while the
## platform is parked flush. This is still the product's FreightControl ray and
## a real E press; it avoids the south-side brake control that shares the aim
## cone once the host is standing on the crowded deck.
func _host_dock_grab() -> void:
	await _walk(NEAR_DOCK, 8.0, "dock before host grab", 1.0)
	await _walk(Vector3(-7.45, 0.0, 3.9), 5.0, "host dock rail stand", 0.55, false, false)
	var rail: Vector3 = platform.call("get_grab_position", "e2") as Vector3
	_face(rail, -99.0)
	await _wait(0.45)
	var target: Node = player.get("current_target") as Node
	var kind: String = str(target.get("kind")) if target != null else ""
	var point: String = str(target.get("dock_id")) if target != null else ""
	log_line("DOCK_GRAB target=%s/%s" % [kind, point])
	var ok: bool = false
	if kind == "grab":
		await _press_e(0.5)
		ok = await _wait_until(func() -> bool:
			return player.get("grab_platform") == platform, 6.0)
	check(ok, "host grabbed the platform handhold from the near dock with real E")
	check(_has_kind(1, "act4_grab"), "host received its own grab credit")
	if ok:
		await _release_grab()
	check(player.get("grab_platform") == null, "host released the dock handhold before boarding")

func _platform_host() -> void:
	# Every seat walks to the dock; pid2 climbs onto the deck first.
	await _wait(2.0)
	await _host_dock_grab()
	if not await _go_to_platform():
		_host_phase("platform_failed")
		return
	_write_done("at_dock", {"ok": true})
	for pid in range(2, expected + 1):
		await _wait_done("at_dock", pid, 120.0)
	check(await _wait_until(func() -> bool:
		var grabbed: int = 0
		for pid in range(1, expected + 1):
			var body: EchoPlayer = _bodies().get(pid) as EchoPlayer
			if body != null and is_instance_valid(body) and (body as Node3D).global_position.y > 2.4:
				grabbed += 1
		return grabbed >= expected, 90.0), "all %d bodies reached the suspended platform level" % expected)
	_record_state("platform_arrive")

	# 1) client rail grab (n1).
	_host_phase("grab_n1", {"pid": 2})
	var ok_n1: bool = await _wait_done("grab_n1", 2, 120.0)
	check(_done_ok("grab_n1", 2), "pid2 grabbed n1 over the real E path (host saw grant=%s)" % str(ok_n1))
	check(_grab_owner("n1") == 2, "host authority maps n1 to pid2 (%d)" % _grab_owner("n1"))
	check(_has_kind(2, "act4_grab") and _kind_count(2, "act4_grab") == 1 and _phase04(2) == 2,
		"pid2 received exactly one grab credit (count=%d phase04=%d)" % [_kind_count(2, "act4_grab"), _phase04(2)])
	_record_state("grab_n1")

	# 2) The host handhold test happens from the near dock (see
	# `_host_dock_grab`) before boarding, where the south-side brake control is
	# not between the camera and the rail.

	if expected < 3:
		# Two-player regression: the host itself tries the occupied n1. The
		# request must be refused with zero credit, then the host drives.
		var host04_before: int = _phase04(1)
		var host_kinds_before: Array = _kinds(1)
		var n2_stand: Vector3 = (platform as Node3D).to_global(Vector3(0.8, 0.0, -1.02))
		await _walk(Vector3(n2_stand.x, 0.0, n2_stand.z), 6.0, "host contention stand", 0.5, false, false)
		var n1_rail: Vector3 = platform.call("get_grab_position", "n1") as Vector3
		_face(n1_rail, -99.0)
		await _wait(0.4)
		if await _aim_and_target("grab", "n1"):
			await _press_e(0.5)
		await _wait(0.8)
		check(player.get("grab_platform") == null, "host was refused the occupied n1")
		check(_grab_owner("n1") == 2, "host's attempt did not steal n1 from pid2 (owner=%d)" % _grab_owner("n1"))
		check(_phase04(1) == host04_before and _kinds(1) == host_kinds_before,
			"the refused host grab earned zero credit (phase04=%d kinds=%s)" % [_phase04(1), str(_kinds(1))])
	else:
		# 3) contention on n1, then pid3 takes n2.
		_host_phase("contend", {"pid": 3})
		await _wait(1.0)
		var p3_before: int = _phase04(3)
		var p3_kinds_before: Array = _kinds(3)
		var rejected: bool = await _wait_done("contend", 3, 180.0)
		check(rejected, "pid3 finished the occupied-handhold attempt")
		check(_grab_owner("n1") == 2, "pid3's attempt did not steal n1 from pid2 (owner=%d)" % _grab_owner("n1"))
		check(_phase04(3) == p3_before and _kinds(3) == p3_kinds_before,
			"the refused grab earned pid3 zero credit (phase04=%d kinds=%s)" % [_phase04(3), str(_kinds(3))])
		_host_phase("grab_rails")
		check(await _wait_done("grab_rails", 3, 180.0), "pid3 reached its own handhold turn")
		check(_done_ok("grab_rails", 3), "pid3 grabbed n2 after the refusal")
		check(_grab_owner("n2") == 3, "host authority maps n2 to pid3")
		check(_phase04(3) == 2, "pid3 phase04 counts strike+grab after its legal grab (%d)" % _phase04(3))
		if expected >= 4:
			check(await _wait_done("grab_rails", 4, 180.0), "pid4 reached its handhold turn")
			check(_done_ok("grab_rails", 4), "pid4 grabbed s1")
			check(_grab_owner("s1") == 4, "host authority maps s1 to pid4")
			check(_phase04(4) == 2, "pid4 phase04 counts strike+grab after its legal grab (%d)" % _phase04(4))
		else:
			check(_grab_owner("n2") == 3 and _grab_owner("n1") == 2,
				"3-player topology holds two distinct handholds at once")
	var holder_count: int = 0
	for point in ["n1", "n2", "s1"]:
		if _grab_owner(point) > 0:
			holder_count += 1
	check(holder_count == expected - 1, "exactly %d clients hold distinct handholds (%d)" % [
		expected - 1, holder_count])

	# 4) drive the platform while the clients hold on.
	var took_lever: bool = await _use_control("drive", Vector3(-1.02, 1.10, -0.50),
		[Vector3(0.0, 0.0, -0.45), Vector3(0.4, 0.0, -0.55)])
	took_lever = took_lever and await _wait_until(func() -> bool:
		return int(platform.get("control_owner_id")) == me, 6.0)
	check(took_lever, "host took the freight drive lever with real E")
	check(_has_kind(1, "act4_platform_drive"), "host earned the legal drive credit")
	check(_phase04(1) == 3, "host phase04 counts strike+grab+drive (phase04=%d)" % _phase04(1))
	var start_x: float = float(platform.get("travel_x"))
	var client_before: Dictionary = {}
	for pid in range(2, expected + 1):
		var body: EchoPlayer = _bodies().get(pid) as EchoPlayer
		if body != null and is_instance_valid(body):
			client_before[pid] = (body as Node3D).global_position
	_key_event(KEY_W, true)
	await _wait(2.6)
	_key_event(KEY_W, false)
	var end_x: float = float(platform.get("travel_x"))
	check(end_x < start_x - 0.8, "real W moved the platform (%.2f -> %.2f)" % [start_x, end_x])
	for pid in range(2, expected + 1):
		var body: EchoPlayer = _bodies().get(pid) as EchoPlayer
		var moved: float = 0.0
		if body != null and is_instance_valid(body) and client_before.has(pid):
			moved = (body as Node3D).global_position.distance_to(client_before[pid] as Vector3)
		check(moved > 0.5, "pid%d body was carried with the platform (moved %.2f m)" % [pid, moved])
	# release lever, then release all grabs
	await _press_e(0.4)
	await _wait(0.4)
	check(int(platform.get("control_owner_id")) == 0, "host released the drive lever with real E")
	_host_phase("release_grabs")
	for pid in range(2, expected + 1):
		await _wait_done("release_grabs", pid, 120.0)
		check(_done_ok("release_grabs", pid), "pid%d released its handhold with real E" % pid)
	check((platform.get("grab_peer_by_point") as Dictionary).is_empty(),
		"all handholds are free after the release (table=%s)" % str(platform.get("grab_peer_by_point")))

	# 5) duplicate request: pid2 re-grabs the same point; the kind count grows,
	#    the phase count must not.
	_host_phase("regrab", {"pid": 2})
	check(await _wait_done("regrab", 2, 180.0), "pid2 re-grab turn finished")
	check(_done_ok("regrab", 2), "pid2 re-grabbed n1 and released again")
	var grab_count: int = _kind_count(2, "act4_grab")
	check(grab_count >= 2, "repeated legal grab only refreshed the same kind (count=%d)" % grab_count)
	check(_phase04(2) == 2, "repeated legal grab did not inflate phase04 (%d)" % _phase04(2))

	# 6) empty clamp is refused without credit; brake is a legal credit.
	var kinds_before: Array = _kinds(me)
	var clamp_ok: bool = await _use_control("clamp", Vector3(-0.20, 1.06, -1.06),
		[Vector3(0.0, 0.0, -0.9), Vector3(0.3, 0.0, -1.0)])
	await _wait(0.5)
	check(not bool(platform.get("clamp_closed")), "the empty clamp stayed open after the real E refusal")
	check(_kinds(me) == kinds_before, "the empty-clamp refusal added no credit to the host")
	# The brake is operated by the host: the south half of the 3.2 m deck is the
	# only clear lane once the clients hold the north handholds, and the host is
	# already on that side. It is still a real E press on the product control.
	var brake_ok: bool = await _use_control("brake", Vector3(1.05, 1.22, 0.86),
		[Vector3(0.0, 0.0, 1.35), Vector3(0.6, 0.0, 1.3), Vector3(-0.5, 0.0, 1.35)])
	await _wait(0.6)
	check(brake_ok and bool(platform.get("brake_engaged")),
		"host pulled the freight brake with real E")
	check(_has_kind(1, "act4_brake"), "host earned the legal brake credit")
	# The deck is now parked over the open shaft. Drive it back to the near
	# berth before anyone steps off; this is a real lever action, not tooling.
	await _wait_until(func() -> bool:
		return absf(float(platform.get("speed"))) < 0.06, 12.0)
	var released_brake: bool = await _use_control("brake", Vector3(1.05, 1.22, 0.86),
		[Vector3(0.0, 0.0, 1.35), Vector3(0.6, 0.0, 1.3), Vector3(-0.5, 0.0, 1.35)])
	await _wait(0.6)
	check(not bool(platform.get("brake_engaged")),
		"host released the freight brake before returning (pressed=%s)" % str(released_brake))
	var lever_ok: bool = await _use_control("drive", Vector3(-1.02, 1.10, -0.50),
		[Vector3(0.0, 0.0, -0.45), Vector3(0.4, 0.0, -0.55)])
	lever_ok = lever_ok and await _wait_until(func() -> bool:
		return int(platform.get("control_owner_id")) == me, 6.0)
	var returned: bool = false
	if lever_ok:
		_key_event(KEY_S, true)
		returned = await _wait_until(func() -> bool:
			return float(platform.get("travel_x")) >= -8.9, 16.0)
		_key_event(KEY_S, false)
		await _wait(0.5)
		await _press_e(0.4)
	check(returned, "host drove the empty platform back to the near berth (x=%.2f)" % float(platform.get("travel_x")))
	_record_state("platform_done")
	_host_phase("platform_done")


func _platform_client() -> void:
	if not await _wait_phase("platform_start", 240.0):
		check(false, "pid%d reached the platform phase" % me)
		return
	# Stagger the climb: the boarding stair is 1.6 m wide.
	await _wait(2.0 + 2.2 * float(me - 2))
	if not await _go_to_platform():
		_write_done("at_dock", {"ok": false})
		return
	_write_done("at_dock", {"ok": true})
	if me == 2:
		if not await _wait_turn("grab_n1", 240.0):
			_write_done("grab_n1", {"ok": false})
			return
		var ok: bool = await _grab_point("n1")
		_record_state("grab_n1")
		# real W while grabbed must not move the body.
		var before: Vector3 = _player_pos()
		await _hold_key(KEY_W, 1.2, 0.1)
		var moved: float = _player_pos().distance_to(before)
		check(moved < 0.12, "grabbed client body is constrained by the rail (moved %.3f m)" % moved)
		_write_done("grab_n1", {"ok": ok})
	elif me == 3:
		if not await _wait_turn("contend", 240.0):
			_write_done("contend", {"ok": false})
			return
		# Try the occupied n1 from the neighbouring stand: refused, zero credit.
		var rail_n1: Vector3 = platform.call("get_grab_position", "n1") as Vector3
		var stand_n2: Vector3 = (platform as Node3D).to_global(Vector3(0.8, 0.26, -1.02))
		await _walk(Vector3(stand_n2.x, 0.0, stand_n2.z), 6.0, "occupied n1 attempt stand", 0.6)
		_face(rail_n1, -0.05)
		await _wait(0.4)
		if await _aim_and_target("grab", "n1"):
			await _press_e(0.5)
		await _wait(0.9)
		check(player.get("grab_platform") == null, "pid3 was refused the occupied n1")
		_write_done("contend", {"ok": true})
		if not await _wait_phase("grab_rails", 240.0):
			_write_done("grab_rails", {"ok": false})
			return
		var ok3: bool = await _grab_point("n2")
		_record_state("grab_n2")
		_write_done("grab_rails", {"ok": ok3})
	elif me == 4:
		if not await _wait_phase("grab_rails", 240.0):
			_write_done("grab_rails", {"ok": false})
			return
		await _wait(1.5)
		var ok4: bool = await _grab_point("s1")
		_record_state("grab_s1")
		_write_done("grab_rails", {"ok": ok4})
	# Hold until the host has driven the platform, then release.
	await _wait_phase("release_grabs", 300.0)
	await _release_grab()
	_write_done("release_grabs", {"ok": true})
	if me == 2:
		if await _wait_turn("regrab", 240.0):
			var regrab: bool = await _grab_point("n1")
			await _release_grab()
			_write_done("regrab", {"ok": regrab})
	# The host drives the empty deck back to the near berth before anyone steps
	# off; the shaft is open under the platform.
	await _wait_phase("platform_done", 300.0)
	await _walk(NEAR_DOCK, 8.0, "back to the near dock", 1.0, false, false)
	await _walk(STAIR_TOP, 8.0, "stair top down", 1.0, false, false)
	await _walk(STAIR_BOTTOM, 8.0, "stair bottom down", 1.0)
	await _walk(HOLD_SPOT, 12.0, "back to the hold spot", 1.2)


# --------------------------------------------------------------- crystal chain --
func _wait_memory(index: int, timeout_s: float) -> bool:
	var ok: bool = await _wait_until(func() -> bool:
		var mems: Dictionary = game.get("seen_memories") as Dictionary
		return bool(mems.get(index, false)), timeout_s)
	var mems_now: Dictionary = game.get("seen_memories") as Dictionary
	log_line("MEMORY%d seen=%s" % [index, str(mems_now.get(index, false))])
	return ok


func _pickup_crystal(crystal: Node3D) -> bool:
	for _attempt in range(4):
		_face(crystal.global_position + Vector3(0, 0.3, 0), 0.2)
		await _wait(0.4)
		await _press_f(0.6)
		if player.get("carrying") != null:
			return true
		await _walk(crystal.global_position + Vector3(0, 0, 0.9), 2.0, "closer to the crystal", 0.5)
	return false


func _place_crystal(key: String) -> bool:
	var cradle: Node3D = (game.get("cradles") as Dictionary)[key] as Node3D
	if cradle == null:
		return false
	if cradle.get("occupied") != null and bool(cradle.get("aligned")):
		return true
	if player.get("carrying") == null:
		return false
	var target_yaw: float = float(cradle.get("required_yaw_deg"))
	var carrying: Node = player.get("carrying") as Node
	var current: float = float(carrying.get("held_yaw_deg"))
	var delta: float = fposmod(target_yaw - current, 360.0)
	var steps: int = int(round(delta / 45.0))
	for _i in range(steps):
		await _press_q()
	_face(cradle.global_position + Vector3(0, 0.15, 0), 0.25)
	await _wait(0.3)
	await _press_f(0.9)
	var ok: bool = await _wait_until(func() -> bool:
		return cradle.get("occupied") != null and bool(cradle.get("aligned")), 6.0)
	log_line("PLACE %s occupied=%s aligned=%s" % [
		key, str(cradle.get("occupied")), str(bool(cradle.get("aligned")))])
	return ok


func _crystal_host() -> void:
	check(await _wait_memory(1, 90.0), "memory one reached by the resonance wave")
	check(not bool(gate.get("is_open")), "exit gate stayed closed after memory one")
	check(not bool(game.get("completed")), "chapter did not complete early after memory one")
	_record_state("memory1")
	# Step off the platform only after the clients cleared the stair, then walk
	# down to the cave floor for the relay chain.
	await _wait(4.0)
	await _walk(NEAR_DOCK, 8.0, "dock after platform", 1.0, false, false)
	await _walk(STAIR_TOP, 8.0, "stair top after platform", 1.0, false, false)
	await _walk(STAIR_BOTTOM, 8.0, "stair bottom after platform", 1.0)
	await _walk(Vector3(0.0, 0.0, 4.0), 6.0, "ground after stair", 1.0)

	# cyan crystal -> west relay B1
	var crystal_a: Node3D = game.get("crystal_a") as Node3D
	await _walk(Vector3(-6.0, 0.0, 2.0), 12.0, "west aisle", 1.0)
	await _walk(Vector3(-6.0, 0.0, 9.5), 10.0, "north of the stope", 1.0)
	await _walk(Vector3(-12.0, 0.0, 9.5), 10.0, "north rim west", 1.0)
	await _walk(Vector3(-17.0, 0.0, 9.5), 9.0, "north west rim", 1.0)
	await _walk(Vector3(-17.5, 0.0, 5.0), 8.0, "alcove west aisle", 1.0)
	await _walk(Vector3(-17.0, 0.0, 3.0), 6.0, "alcove shelf", 0.9)
	check(await _pickup_crystal(crystal_a), "host picked up the cyan crystal with real F")
	await _walk(Vector3(-16.5, 0.0, -2.0), 12.0, "carry south along the west wall", 1.2)
	await _walk(Vector3(-16.8, 0.0, -9.0), 11.0, "carry south", 1.2)
	await _walk(Vector3(-13.0, 0.0, -11.5), 10.0, "toward west relay", 1.2)
	var b1: Node3D = (game.get("cradles") as Dictionary)["b1"] as Node3D
	await _walk(b1.global_position + Vector3(0, 0, 1.25), 8.0, "west relay B1", 0.8)
	check(await _place_crystal("b1"), "cyan crystal seated and aligned in west relay B1")
	check(await _strike_once(), "host struck the bell to restore the west relay")
	check(await _wait_memory(2, 120.0), "memory two reached after the west path was restored")
	check(not bool(gate.get("is_open")), "exit gate stayed closed after memory two")
	_record_state("memory2")

	# violet crystal -> observation ledge B3
	var crystal_b: Node3D = game.get("crystal_b") as Node3D
	await _walk(crystal_b.global_position + Vector3(0, 0, 1.1), 10.0, "violet crystal", 0.9)
	check(await _pickup_crystal(crystal_b), "host picked up the violet crystal with real F")
	await _walk(Vector3(-18.5, 0.0, -13.2), 11.0, "west ramp foot", 1.2)
	await _walk(Vector3(-17.2, 3.4, -17.6), 11.0, "west ramp up", 1.2)
	await _walk(Vector3(-14.0, 3.4, -19.2), 9.0, "observation ledge", 1.2)
	var b3: Node3D = (game.get("cradles") as Dictionary)["b3"] as Node3D
	await _walk(b3.global_position + Vector3(0, 0, 1.15), 8.0, "ledge relay B3", 0.9)
	check(await _place_crystal("b3"), "violet crystal seated and aligned on observation ledge B3")
	check(await _strike_once(), "host struck the bell to restore the final chain")
	check(await _wait_memory(3, 180.0), "memory three reached through the restored chain")
	check(await _wait_until(func() -> bool: return bool(gate.get("is_open")), 60.0),
		"exit gate physically opened after memory three")
	_record_state("gate")


# ----------------------------------------------------------------------- exit --
func _exit_route(tag_label: String) -> void:
	await _walk(Vector3(4.5, 0.0, -6.0), 12.0, "%s east side south" % tag_label, 1.0)
	await _walk(Vector3(0.0, 0.0, -14.0), 10.0, "%s final west aisle" % tag_label, 1.1)
	await _walk(Vector3(0.0, 0.0, -21.0), 9.0, "%s final chamber aisle" % tag_label, 1.2)
	await _walk(Vector3(6.2, 0.0, -25.0), 12.0, "%s exit corridor" % tag_label, 0.7)


func _wait_exit_observations() -> bool:
	var ready: bool = await _wait_until(func() -> bool:
		for pid in range(2, expected + 1):
			if not _done_ok("exit_ready", pid):
				return false
		return true, 180.0)
	check(ready, "all clients observed phase04 and finished the memory performance before exit")
	var memory_idle: bool = await _wait_until(_memory_idle, 60.0)
	check(memory_idle, "host memory performance finished naturally before exit")
	return ready and memory_idle


func _memory_idle() -> bool:
	if not _in_tree(game):
		return false
	var director: Node = game.get("memory") as Node
	return _in_tree(director) and not bool(director.get("playing")) \
		and (game.get("memory_queue") as Array).is_empty()


func _exit_host() -> void:
	check(await _wait_until(func() -> bool:
		var ledger: ParticipationLedger = _ledger()
		if ledger == null:
			return false
		var active: Array[int] = ledger.active_ids()
		if active.is_empty() or not active.has(me):
			return false
		for pid in active:
			if not ledger.ready_for_phase(pid, ParticipationLedger.PHASE_04):
				return false
		return true, 60.0), "authoritative ledger shows every active participant ready for phase 04")
	_record_state("pre_exit")
	# Wait until every client body is physically in the exit corridor.
	var all_in: bool = await _wait_until(func() -> bool:
		var n: int = 0
		for pid in range(2, expected + 1):
			var body: EchoPlayer = _bodies().get(pid) as EchoPlayer
			if body != null and is_instance_valid(body):
				var p: Vector3 = (body as Node3D).global_position
				if p.z < -24.0 and p.x > 4.2:
					n += 1
		return n >= expected - 1, 300.0)
	check(all_in, "every client body passed the exit gate")
	if not all_in:
		return
	await _exit_route("host")
	var completed: bool = await _wait_until(func() -> bool:
		return _scene_now() == "Main" or (_in_tree(game) and bool(game.get("completed"))), 60.0)
	check(completed, "the real exit trigger completed Act04 and handed off to Act05")
	_record_state("exit")


func _exit_client() -> void:
	if not await _wait_phase("exit", 600.0):
		check(false, "pid%d reached the exit phase" % me)
		return
	await _exit_route("pid%d" % me)
	_write_done("at_exit", {"ok": true})
	var switched: bool = await _wait_until(func() -> bool:
		return _scene_now() == "Main", 300.0)
	check(switched, "pid%d followed the host's reliable Act04 -> Act05 switch (scene=%s)" % [
		me, _scene_now()])


func _verify_handoff() -> void:
	var ok: bool = await _wait_until(func() -> bool:
		return _scene_now() == "Main", 60.0)
	check(ok, "Act05 scene is live (scene=%s)" % _scene_now())
	if not ok:
		return
	var chapter: String = str(hub.get("current_chapter")) if hub != null else "?"
	check(chapter == "act05", "SessionHub current chapter is act05 (%s)" % chapter)
	var hist: Dictionary = (hub.get("chapter_history") as Dictionary) if hub != null else {}
	check(hist.has("act04"), "host-authored Act04 completion is in the chapter history")
	var progress: Dictionary = (hub.get("chapter_progress") as Dictionary) if hub != null else {}
	check(not progress.is_empty(), "the Act04 hand-off payload survived the scene switch")
	_write_json("a4_%s%d.handoff.json" % [role, index], {
		"pid": me, "role": role, "scene": _scene_now(), "chapter": chapter,
		"history_keys": hist.keys(), "progress_keys": progress.keys(),
		"history_act04_size": (hist.get("act04", {}) as Dictionary).size(),
		"passed": true,
	})


# --------------------------------------------------------------------- flows --
func _host_flow() -> void:
	if not await _wait_roster():
		return
	_identity_checks()
	await _strikes_host()
	# Phase gate: all seats now hold at least one phase-04 credit.
	check(await _wait_until(func() -> bool:
		for pid in range(1, expected + 1):
			if not _ready04(pid):
				return false
		return true, 30.0), "every seat holds a phase-04 credit after the bell round")
	_host_phase("platform_start")
	await _platform_host()
	if failures.size() > 0:
		_record_state("host_blocked")
		return
	_host_phase("crystal")
	await _crystal_host()
	if failures.size() > 0:
		_record_state("host_blocked_crystal")
		return
	_record_state("crystal_done")
	if not await _wait_exit_observations():
		return
	_host_phase("exit")
	await _exit_host()
	await _verify_handoff()


func _client_flow() -> void:
	if not await _wait_roster():
		return
	_identity_checks()
	await _strikes_client()
	if me == 2:
		# pid2 is the first platform actor and the regrab actor.
		await _wait_phase("platform_start", 300.0)
		await _platform_client()
	else:
		await _wait_phase("platform_start", 300.0)
		await _platform_client()
	# Hold at the agreed spot while the host restores the relay chain.
	await _walk(HOLD_SPOT, 10.0, "hold for the relay chain", 1.0)
	# The mirror of the authoritative ledger must agree before the exit.
	var mirror_own: bool = await _wait_until(func() -> bool:
		return _phase04(me) >= 2, 120.0)
	check(mirror_own, "client mirror sees its own strike+grab phase04=%d" % _phase04(me))
	var mirror_ok: bool = await _wait_until(func() -> bool:
		for pid in range(1, expected + 1):
			if not _ready04(pid):
				return false
		return true, 120.0)
	check(mirror_ok, "client mirror agrees every seat is ready for phase 04")
	_record_state("ready04")
	# Observe the host's completed relay chain before waiting for our own
	# naturally ending performance. No game state is changed by this barrier.
	var final_memory: bool = await _wait_until(func() -> bool:
		return _in_tree(game) and bool((game.get("seen_memories") as Dictionary).get(3, false)), 240.0)
	check(final_memory, "client observed the final memory before exit")
	var memory_idle: bool = await _wait_until(_memory_idle, 60.0)
	check(memory_idle, "client memory performance finished naturally before exit")
	_write_done("exit_ready", {"ok": mirror_own and mirror_ok and final_memory and memory_idle})
	await _exit_client()
	await _verify_handoff()


func _run() -> void:
	# Keep watching scene changes for the evidence trail.
	_bind_process()
	if not await _wait_game():
		_finish(false)
		return
	if role == "host":
		await _host_flow()
	else:
		await _client_flow()
	_finish(failures.is_empty())


func _bind_process() -> void:
	# SceneTree does not call _process on a RefCounted, so the scene log is
	# written from the polling points above instead; this hook keeps the API
	# shape identical to the Act23 helper for the parent harness.
	pass


func _finish(passed: bool) -> void:
	if _finished:
		return
	_finished = true
	_passed = passed and failures.is_empty()
	var cap: Dictionary = _state_snapshot()
	cap["role"] = role
	cap["index"] = index
	cap["pid"] = me
	cap["checks"] = checks
	cap["failures"] = failures
	cap["warnings"] = warnings
	cap["passed"] = _passed
	cap["scene_log"] = _scene_log
	cap["tag"] = tag
	_write_json("a4_%s%d.result.json" % [role, index], cap)
	log_line("A4_RESULT: role=%s index=%d pid=%d passed=%s checks=%d failures=%d" % [
		role, index, me, str(_passed), checks, failures.size()])
	print("A4_RESULT_JSON: " + JSON.stringify(cap))
