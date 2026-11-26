extends SceneTree

## R2 · Act05 full-chapter two-process probe (real clock, real ENet, real input).
##
## Entry (legitimate): both processes boot the official Launcher with --host /
## --client. SessionHub boots the real ENet peer. Once the client is connected,
## the host replays Act 4's frozen completion contract exactly as
## ResonanceGame._on_exit_entered does:
##     SessionHub.chapter_progress = completion_payload()
##     SessionHub.complete_chapter("act04", payload, "act05",
##                                 "res://scenes/main.tscn", spawn)
## The client follows the host's reliable do_scene_switch RPC. Both therefore
## enter Act05 through the game's own Act04 -> Act05 handoff path.
##
## Everything after that is real input: WASD / E / W / S. This probe never
## teleports the player, never writes a machine state, and never writes a
## completion flag. It only reads state and asserts.
##
## Role split:
##   host   : west stabilizer (A) -> west counterweight (A) -> catwalk ladder
##            climb / cancel / climb -> rail brace through a real surge (B) ->
##            hydraulic claw (C) -> extraction damper (C) -> navigation data (C)
##            -> west exit
##   client : east stabilizer (A) -> emergency brake during a warning (B) ->
##            isolation safety pin (C) -> carriage push (C) -> west exit
##
## Geometry used below was read from the live scene (r2_geom_dump):
##   spawn (0,4.06,38) / shutter (0,4,24) / balcony (0,4,12.2)
##   west ramp foot (-5,0,2.4) / east ramp foot (5,0,2.4)
##   west stabilizer stand (-8.02,0,-6.18) / east stand (4.55,0,-10.13)
##   west counterweight anchor (-8.5,1.6,7.466)
##   ladder station (-7.55,0.55,-0.25) / deck (-14..-8.2, y=3.4, z=-4.95..-3.45)
##   grab points (-13.1/-11.1/-9.1, 4.46, -3.45)
##   lock console area (0,1.1,7.55) / damper anchor (6.4,0,-2.65)
##   isolation anchor (10.7,0,-5.4) / data area (-3,1,-9.1)
##   exit trigger (-25.5,1.3,-2.0)

const FINALE_NAME := "Finale"
const PORT_DEFAULT := 9877

var role: String = "host"
var out_dir: String = ""
var tag: String = "r2"
var port: int = PORT_DEFAULT
var started_msec: int = 0
var hub: Node = null
var game: Node = null
var player: Node = null
var level: Node = null
var story: Node = null
var session: Node = null
var net: Node = null
var surge: Node = null
var core: Node = null
var catwalk: Node = null

var checks: int = 0
var failures: Array[String] = []
var log_lines: Array[String] = []
var samples: Array[String] = []
var stage_name: String = "boot"
var live_log: FileAccess = null


func _initialize() -> void:
	_parse_args()
	started_msec = Time.get_ticks_msec()
	_watchdog.call_deferred()
	_run.call_deferred()


func _parse_args() -> void:
	var all: Array[String] = []
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	for a in all:
		var s := str(a)
		if s.begins_with("--role="):
			role = s.split("=")[1]
		elif s.begins_with("--out="):
			out_dir = s.split("=")[1]
		elif s.begins_with("--tag="):
			tag = s.split("=")[1]
		elif s.begins_with("--port="):
			port = int(s.split("=")[1])


func _watchdog() -> void:
	await create_timer(1500.0).timeout
	push_error("R2_WATCHDOG role=%s stage=%s" % [role, stage_name])
	_finish(false)


func log_line(text: String) -> void:
	var line: String = "[%s] %s" % [role, text]
	print(line)
	log_lines.append(text)
	if live_log != null:
		live_log.store_line(line)
		live_log.flush()


func check(ok: bool, text: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append("[%s] %s" % [stage_name, text])
	return ok


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_until(cond: Callable, timeout_s: float, label: String) -> bool:
	var waited := 0.0
	while waited < timeout_s:
		if bool(cond.call()):
			return true
		await create_timer(0.1).timeout
		waited += 0.1
	var ok: bool = bool(cond.call())
	if not ok:
		log_line("WAIT_TIMEOUT %s (%.0fs)" % [label, timeout_s])
	return ok


func _v(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------------------
# Entry: Act04 -> Act05 handoff through the real SessionHub contract
# ---------------------------------------------------------------------------
func _run() -> void:
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		live_log = FileAccess.open(out_dir.path_join("r2_live_%s_%s.log" % [role, tag]), FileAccess.WRITE)
	await process_frame
	hub = root.get_node_or_null("/root/SessionHub")
	if hub == null:
		check(false, "SessionHub autoload is present")
		_finish(false)
		return
	net = hub.get("net") as Node
	session = hub.get("session") as Node
	if net == null or session == null:
		check(false, "SessionHub owns CoopNet + CoopSession")
		_finish(false)
		return
	stage_name = "entry"
	log_line("ENTRY role=%s pid_before=%s peers_before=%s scene=%s" % [
		role, str(session.get("local_pid")), str(int(net.call("peer_count"))),
		str(current_scene.name) if current_scene != null else "null"])

	if role == "host":
		var peers_ok: bool = await _wait_until(func() -> bool:
			return int(net.call("peer_count")) >= 2, 90.0, "client joins the ENet host")
		check(peers_ok, "two real ENet peers are connected before the Act05 handoff")
		if not peers_ok:
			_finish(false)
			return
		# Act 4's completion payload shape (scripts/act4/game.gd::completion_payload).
		var act4_payload: Dictionary = {
			"chapter": "resonance_04",
			"completed": true,
			"seconds": 214.0,
			"memories": {1: true, 2: true, 3: true},
			"strikes": 3,
			"gate_open": true,
			"player_exit_position": Vector3(-12.0, 0.0, -2.0),
			"freight_accident_fired": true,
			"freight_cargo_on_platform": false,
			"freight_cargo_clamped": false,
			"freight_platform_x": 2.0,
		}
		hub.set("chapter_progress", act4_payload)
		log_line("ENTRY host invokes SessionHub.complete_chapter(act04 -> act05) with the frozen Act04 spawn contract")
		hub.call("complete_chapter", "act04", act4_payload, "act05",
			"res://scenes/main.tscn",
			{"chapter": "resonance_04", "completed": true, "from_act4": true})

	var got: bool = await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == "Main", 120.0, "Act05 Main scene")
	check(got, "both peers entered Act05 Main through the Act04 handoff")
	if not got:
		_finish(false)
		return
	await _wait(1.5)
	game = current_scene
	player = game.get("player") as Node
	level = game.get("level") as Node
	story = game.get("story") as Node
	surge = game.get("surge") as Node
	session = hub.get("session") as Node
	net = hub.get("net") as Node
	if level != null:
		core = level.get("core") as Node
		catwalk = level.get("catwalk") as Node
	if player == null or level == null or story == null or core == null or catwalk == null or session == null:
		check(false, "Act05 world nodes (player/level/story/core/catwalk) exist")
		_finish(false)
		return
	var handoff_from_act04: bool = bool(game.get("handoff_from_act04"))
	var spawn: Vector3 = game.get("entry_spawn") as Vector3
	check(handoff_from_act04, "Act05 consumed a real from_act4 handoff payload")
	check(spawn.distance_to(Vector3(0, 4.06, 38.0)) < 0.01, "Act05 spawn came from the handoff contract (0,4.06,38)")
	check(int(net.call("peer_count")) >= 2, "both peers share the same Act05 session (peers=2)")
	check(int(session.get("local_pid")) == (1 if role == "host" else 2),
		"seat identity is real (pid=%d)" % int(session.get("local_pid")))
	_sample("act05_begin")
	log_line("ACT05_BEGIN pos=%s stage=%d stabs=%s" % [
		str(player.global_position), int(story.get("stage")), str(_latch_flags())])

	if role == "host":
		await _host_flow()
	else:
		await _client_flow()
	_finish(failures.is_empty())


# ---------------------------------------------------------------------------
# Shared movement / interaction helpers (real input only)
# ---------------------------------------------------------------------------
func _face(target: Vector3) -> void:
	if player == null or not is_instance_valid(player):
		return
	var d: Vector3 = target - (player.global_position as Vector3)
	var yaw: float = atan2(-d.x, -d.z)
	var flat: float = Vector2(d.x, d.z).length()
	var pitch: float = -atan2(d.y - 1.45, maxf(flat, 0.05))
	player.call("set_look", yaw, clampf(pitch, -1.1, 1.1))


func _walk_to(target: Vector3, max_seconds: float, tol: float, label: String) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if bool(player.get("operating")):
		await _press_e()
	if bool(player.get("grabbing")):
		await _press_e()
	var elapsed := 0.0
	var stuck := 0.0
	var last: Vector3 = player.global_position
	var nudges := 0
	_face(target)
	Input.action_press("move_forward")
	while elapsed < max_seconds:
		await physics_frame
		elapsed += 1.0 / 60.0
		if current_scene == null or str(current_scene.name) != "Main":
			break
		var current: Vector3 = player.global_position
		_face(Vector3(target.x, current.y, target.z))
		if _flat_dist(current, target) <= tol:
			break
		if current.distance_to(last) < 0.012:
			stuck += 1.0 / 60.0
		else:
			stuck = 0.0
			last = current
		if stuck > 1.0 and nudges < 8:
			nudges += 1
			Input.action_release("move_forward")
			var side := "move_right" if nudges % 2 == 1 else "move_left"
			Input.action_press(side)
			for _i in range(8):
				await physics_frame
			Input.action_release(side)
			Input.action_press("move_forward")
			stuck = 0.0
			last = player.global_position
	Input.action_release("move_forward")
	Input.action_release("move_left")
	Input.action_release("move_right")
	await physics_frame
	var pos: Vector3 = player.global_position
	var dist: float = _flat_dist(pos, target)
	log_line("WALK %s target=%s pos=%s dist=%.2f t=%.1f nudges=%d" % [
		label, str(target.snapped(Vector3(0.01, 0.01, 0.01))),
		str(pos.snapped(Vector3(0.01, 0.01, 0.01))), dist, elapsed, nudges])
	if dist > tol * 2.2:
		log_line("WALK_BLOCK %s block=%s prompt='%s' target_node=%s" % [
			label, str(player.call("get_block_text")), str(player.get("current_prompt")),
			str(player.get("current_target").name if player.get("current_target") is Node else "null")])
	return dist <= tol * 2.2


func _walk_path(points: Array, tol: float, label: String) -> bool:
	for i in range(points.size()):
		var p: Vector3 = points[i] as Vector3
		var ok: bool = await _walk_to(p, maxf(5.0, _flat_dist(player.global_position, p) / 3.2 + 4.0),
			tol, "%s[%d]" % [label, i])
		if not ok:
			log_line("WALK_PATH_STOPPED %s[%d] at %s" % [label, i, str(player.global_position)])
			return false
	return true


func _walk_off(direction: Vector3, seconds: float) -> void:
	_face(player.global_position + direction)
	Input.action_press("move_forward")
	await _wait(seconds)
	Input.action_release("move_forward")
	await _wait(1.2)


func _press_e(hold := 0.12) -> void:
	Input.action_press("interact")
	await _wait(hold)
	Input.action_release("interact")
	await _wait(0.4)


func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)
	await _wait(0.2)


func _operate_at(stand: Vector3, face_point: Vector3, expected_machine: String, label: String) -> bool:
	for attempt in range(5):
		await _walk_to(stand, 12.0, 0.9, "%s stand %d" % [label, attempt])
		_face(face_point)
		await _wait(0.3)
		await _press_e()
		var machine: String = str(session.get("local_operating_machine"))
		var machine_ok: bool = machine == expected_machine
		if expected_machine == "brake*":
			machine_ok = machine == "brake" or machine == "brake_assist"
		if bool(player.get("operating")) and machine_ok:
			log_line("OPERATE %s machine=%s pos=%s" % [label, machine, str(player.global_position)])
			return true
		if bool(player.get("operating")):
			# Wrong station selected: cancel and retry from a tighter stand.
			await _press_e()
		await _wait(0.4)
	log_line("OPERATE_FAILED %s target_machine=%s operating=%s machine=%s prompt='%s' target=%s" % [
		label, expected_machine, str(bool(player.get("operating"))),
		str(session.get("local_operating_machine")), str(player.get("current_prompt")),
		str(player.get("current_target").name if player.get("current_target") is Node else "null")])
	return false


# ---------------------------------------------------------------------------
# Read-only state helpers
# ---------------------------------------------------------------------------
func _stabs() -> Array:
	return level.get("stabilizers") as Array


func _latched(i: int) -> bool:
	var stabs: Array = _stabs()
	if i < 0 or i >= stabs.size():
		return false
	return bool((stabs[i] as Object).get("latched"))


func _latch_flags() -> Array:
	var out: Array = []
	for s in _stabs():
		out.append(bool((s as Object).get("latched")))
	return out


func _core_locked() -> bool:
	return bool(core.call("is_locked"))


func _core_net() -> float:
	return float(core.call("get_net"))


func _capturable() -> bool:
	return bool(core.call("is_capturable"))


func _interlock() -> String:
	return str(core.call("lock_interlock_reason"))


func _damper_latched() -> bool:
	return bool((level.get("damper") as Object).get("latched_flag"))


func _iso_pin() -> bool:
	return bool((level.get("isolation") as Object).get("pin_out"))


func _iso_sep() -> bool:
	return bool((level.get("isolation") as Object).get("separated_flag"))


func _brake_both_claimed() -> bool:
	if session == null:
		return false
	return int(session.call("claim_owner", "brake")) != 0 \
		and int(session.call("claim_owner", "brake_assist")) != 0


func _has_credit(kind: String) -> bool:
	var led: Variant = session.get("ledger")
	if led == null:
		return false
	var pid: int = int(session.get("local_pid"))
	return bool((led as Object).call("has_credit", pid, kind))


func _has_credit_for(pid: int, kind: String) -> bool:
	var led: Variant = session.get("ledger")
	if led == null:
		return false
	return bool((led as Object).call("has_credit", pid, kind))


func _ledger_line() -> String:
	var led: Variant = session.get("ledger")
	if led == null:
		return "ledger=missing"
	var parts: Array[String] = []
	for pid in (led as Object).call("player_ids"):
		var rec: Dictionary = (led as Object).call("get_record", int(pid))
		parts.append("P%d phases=%s ready=%s" % [
			int(pid), str(rec.get("phases", {})), str(bool((led as Object).call("is_ready", int(pid))))])
	return " | ".join(parts)


func _sample(tag: String) -> void:
	var d: Dictionary = {
		"tag": tag,
		"t": float(Time.get_ticks_msec() - started_msec) / 1000.0,
		"role": role,
		"scene": str(current_scene.name) if current_scene != null else "null",
		"pid": int(session.get("local_pid")) if session != null else 0,
		"stage": int(story.get("stage")) if story != null else -1,
		"checkpoint": int(story.get("checkpoint")) if story != null else -1,
		"pos": str((player.global_position as Vector3).snapped(Vector3(0.01, 0.01, 0.01))) if player != null else "n/a",
		"stabs": _latch_flags(),
		"interlock": _interlock(),
		"core_locked": _core_locked(),
		"core_net": _core_net(),
		"capturable": _capturable(),
		"damper": _damper_latched(),
		"iso_pin": _iso_pin(),
		"iso_sep": _iso_sep(),
		"data_taken": bool(story.get("data_taken")),
		"completed": bool(story.call("completed_flag")),
		"can_finish": bool(session.call("can_finish")) if role == "host" and session != null else false,
		"ledger": _ledger_line(),
	}
	samples.append(JSON.stringify(d))
	log_line("SAMPLE " + JSON.stringify(d))


# ---------------------------------------------------------------------------
# Host flow
# ---------------------------------------------------------------------------
func _host_flow() -> void:
	stage_name = "act05_entry"
	# --- entrance: real E on the jammed shutter ---------------------------
	await _walk_path([_v(0, 4.0, 30.0), _v(0, 4.0, 26.2)], 1.2, "host tunnel")
	await _walk_to(_v(0, 4.0, 24.7), 8.0, 0.8, "host shutter stand")
	_face(_v(0, 5.1, 24.2))
	await _wait(0.3)
	await _press_e()
	check(bool(player.get("operating")), "host grabbed the jammed shutter with real E")
	if bool(player.get("operating")):
		await _hold("move_forward", 4.2)
		await _press_e()
	check(bool((level.get("push_door") as Object).get("is_opened")), "host opened the jammed shutter by holding W")
	await _walk_path([_v(0, 4.0, 22.5), _v(0, 4.0, 12.4)], 1.3, "host through shutter")
	check(await _wait_until(func() -> bool: return int(story.get("stage")) >= 2, 30.0, "hall trigger"), 
		"host entering the hall advanced the story to the instability stage")

	# --- descend the west ramp -------------------------------------------
	await _walk_path([
		_v(-4.2, 4.0, 10.4), _v(-4.2, 1.4, 4.4), _v(-4.2, 0.0, 1.5)
	], 1.2, "host west ramp")
	check((player.global_position as Vector3).y < 0.6, "host reached the hall floor by walking the west ramp")

	# --- A: west stabilizer (real E + W) ---------------------------------
	stage_name = "act05_west_leg"
	var west_stand := _v(-8.02, 0.0, -6.18)
	var west_area := _v(-7.82, 1.3, -6.41)
	var opw: bool = await _operate_at(west_stand, west_area, "stabilizer_w", "host west leg")
	check(opw, "host operates the west stabilizer with real E")
	var latched_w := false
	if opw:
		Input.action_press("move_forward")
		var t := 0.0
		while t < 30.0:
			await _wait(0.25)
			t += 0.25
			if _latched(0):
				latched_w = true
				break
		Input.action_release("move_forward")
		log_line("PUMP west t=%.1f latched=%s pos=%s" % [t, str(latched_w), str(player.global_position)])
		await _press_e()
	check(_latched(0), "west stabilizer latched by the host's real pumping")
	check(_has_credit("stabilizer_lock"), "host earned stabilizer_lock credit")
	_sample("host_after_west_leg")
	check(_interlock().contains("1/2"), "only the west leg is locked: the claw interlock reports 1/2")
	if role == "host":
		log_line("HOST_INTERLOCK_1OF2 reason='%s'" % _interlock())

	# --- A: west counterweight (move the left cart outward) --------------
	stage_name = "act05_counterweight"
	await _walk_path([
		_v(-5.6, 0.0, -6.18), _v(-5.6, 0.0, -0.5), _v(-6.6, 0.0, -0.5),
		_v(-6.6, 0.0, 1.2), _v(-6.6, 0.0, 2.4), _v(-8.0, 0.0, 2.4)
	], 1.0, "host to west station")
	await _walk_path([_v(-8.0, 1.6, 4.7), _v(-8.6, 1.6, 6.6), _v(-8.5, 1.6, 7.47)], 1.0, "host west station ramp")
	var station_anchor := _v(-8.5, 1.6, 7.466)
	var station_area := _v(-8.375, 2.8, 7.25)
	var opcw: bool = await _operate_at(station_anchor, station_area, "cart_left", "host west counterweight")
	check(opcw, "host operates the west counterweight console with real E")
	if opcw:
		Input.action_press("move_forward")
		var t2 := 0.0
		while t2 < 12.0:
			await _wait(0.25)
			t2 += 0.25
			if _core_net() <= 0.20:
				break
		Input.action_release("move_forward")
		log_line("COUNTERWEIGHT t=%.1f net=%.3f left=%.2f right=%.2f" % [
			t2, _core_net(), float((level.get("left_cart") as Object).call("get_p")),
			float((level.get("right_cart") as Object).call("get_p"))])
		await _press_e()
	check(_has_credit("counterweight_effect"), "host earned counterweight_effect by really reducing the core bias")
	_sample("host_after_counterweight")
	check(_interlock().contains("1/2"), "after the counterweight only 1/2 legs are locked (client has not pumped yet)")

	# --- B: both players man the two emergency-brake pumps during a warning
	stage_name = "act05_brake"
	# Leave the west station down its ramp, then walk west around the end of the
	# counterweight track so the brake is reached on the south side.
	await _walk_to(_v(-8.0, 0.0, 4.6), 12.0, 0.9, "host station to ramp")
	await _walk_to(_v(-8.0, 0.0, 2.4), 10.0, 0.9, "host station ramp to floor")
	check((player.global_position as Vector3).y < 0.6, "host walked off the west station down its ramp")
	await _walk_path([
		_v(-14.0, 0.0, 2.8), _v(-14.0, 0.0, -2.9), _v(-13.12, 0.0, -2.9)
	], 1.0, "host to brake")
	var opb: bool = await _operate_at(_v(-13.12, 0.0, -2.9), _v(-13.12, 1.3, -3.05), "brake*", "host brake")
	check(opb, "host operates one of the two emergency-brake pumps with real E")
	if opb:
		var both_pumps: bool = await _wait_until(func() -> bool: return _brake_both_claimed(), 300.0,
			"both brake pumps claimed")
		check(both_pumps, "both players are manning the two brake pumps")
		if both_pumps:
			var warn: bool = await _wait_until(func() -> bool:
				return float(surge.get("warning_left")) > 2.0, 240.0, "surge warning for the brake")
			if warn:
				log_line("BRAKE_WARNING warning_left=%.1f state=%s" % [
					float(surge.get("warning_left")), str(surge.get("state"))])
				Input.action_press("move_forward")
				var bt := 0.0
				while bt < 4.0 and not bool((level.get("brake") as Object).get("latched")):
					await _wait(0.2)
					bt += 0.2
				Input.action_release("move_forward")
				await _wait(0.3)
			check(_has_credit("surge_response"),
				"host earned surge_response by pumping the brake during a real warning")
		await _press_e()
	_sample("host_after_brake")

	# --- climb / cancel / climb on the real maintenance ladder -----------
	stage_name = "act05_catwalk"
	await _walk_path([
		_v(-9.5, 0.0, -2.5), _v(-9.5, 0.0, 0.4), _v(-8.0, 0.0, 0.4),
		_v(-7.55, 0.0, 0.65)
	], 1.0, "host to ladder")
	var ladder_face := _v(-7.55, 1.3, -1.45)
	var at_ladder := (player.global_position as Vector3).y < 0.6
	check(at_ladder, "host reached the maintenance ladder at floor level")
	# --- first climb: real E, hold W, then cancel with E -----------------
	var y_start: float = (player.global_position as Vector3).y
	_face(ladder_face)
	await _wait(0.3)
	await _press_e()
	var climb_started: bool = bool(player.get("operating")) and bool(player.get("external_hold")) \
		and str(session.get("local_operating_machine")) == ""
	check(climb_started, "host started climbing the maintenance ladder with real E")
	if climb_started:
		Input.action_press("move_forward")
		await _wait(1.1)
		Input.action_release("move_forward")
		var y_mid: float = (player.global_position as Vector3).y
		await _press_e()
		var canceled: bool = not bool(player.get("operating")) and not bool(player.get("external_hold"))
		var y_after_cancel: float = (player.global_position as Vector3).y
		await _wait(0.8)
		var y_landed: float = (player.global_position as Vector3).y
		log_line("CLIMB_CANCEL y_start=%.2f y_mid=%.2f canceled=%s y_cancel=%.2f y_landed=%.2f" % [
			y_start, y_mid, str(canceled), y_after_cancel, y_landed])
		check(y_mid > y_start + 0.3, "the host really moved up the ladder before cancelling")
		check(canceled, "E cancels the ladder climb (operating=false, external_hold=false)")
		check(y_landed < y_mid - 0.2, "the body falls back down after the climb is cancelled")
	# --- second climb: hold W all the way to the deck --------------------
	var climbed := false
	for attempt in range(3):
		await _walk_to(_v(-7.55, 0.0, 0.65), 8.0, 0.8, "host ladder stand %d" % attempt)
		_face(ladder_face)
		await _wait(0.35)
		await _press_e()
		var ok_start: bool = bool(player.get("operating")) and bool(player.get("external_hold")) \
			and str(session.get("local_operating_machine")) == ""
		if not ok_start:
			log_line("CLIMB_RETRY attempt=%d operating=%s external_hold=%s machine=%s prompt='%s'" % [
				attempt, str(bool(player.get("operating"))), str(bool(player.get("external_hold"))),
				str(session.get("local_operating_machine")), str(player.get("current_prompt"))])
			continue
		Input.action_press("move_forward")
		var climbed_t := 0.0
		while climbed_t < 12.0 and bool(player.get("external_hold")):
			await _wait(0.2)
			climbed_t += 0.2
		Input.action_release("move_forward")
		await _wait(0.5)
		log_line("CLIMB_END attempt=%d t=%.1f y=%.2f pos=%s" % [
			attempt, climbed_t, (player.global_position as Vector3).y, str(player.global_position)])
		if (player.global_position as Vector3).y > 3.0:
			climbed = true
			break
	check(climbed, "host climbed onto the catwalk (y=%.2f)" % (player.global_position as Vector3).y)
	if not climbed:
		_sample("host_catwalk_failed")
		return
	_sample("host_on_catwalk")
	# The catwalk free end is blocked at chest height by the cantilever/pin
	# bracket; the ladder tops out on the rescue landing. The landing's west edge
	# is open above the hall floor, so a real player steps off it to get down.
	await _walk_to(_v(-9.6, 3.4, -2.9), 6.0, 0.5, "host landing west edge")
	await _wait(1.2)
	if (player.global_position as Vector3).y > 1.0:
		await _walk_to(_v(-10.2, 0.0, -2.9), 4.0, 0.6, "host landing drop")
		await _wait(1.0)
	log_line("CATWALK_DROP pos=%s impaired=%.1f" % [
		str(player.global_position), float(player.get("impaired_timer"))])
	check((player.global_position as Vector3).y < 1.0,
		"host got down from the ladder landing onto the hall floor (y=%.2f)" % (player.global_position as Vector3).y)

	# --- C: hydraulic claw at the real console (0,1.1,7.55) --------------
	stage_name = "act05_claw"
	# The landing is on the west wall and the direct north aisles are closed by
	# the crystal host / station platform, so walk the open south loop to the
	# east aisle, then north under the balcony to the console.
	await _walk_path([
		_v(-6.6, 0.0, -4.2), _v(-4.9, 0.0, -4.2), _v(-4.9, 0.0, -7.6),
		_v(5.0, 0.0, -7.6), _v(5.0, 0.0, -6.0),
		_v(10.6, 0.0, -6.0), _v(11.1, 0.0, -6.0), _v(11.1, 0.0, -2.0),
		_v(11.1, 0.0, 2.0), _v(11.1, 0.0, 10.5), _v(0.0, 0.0, 10.5),
		_v(0.0, 0.0, 7.85)
	], 0.8, "host to lock console")
	check(_flat_dist(player.global_position, _v(0, 0, 7.85)) < 2.0,
		"host stands at the real claw console (pos=%s)" % str(player.global_position))
	var both: bool = await _wait_until(func() -> bool: return _latched(0) and _latched(1), 300.0, "both legs latched")
	check(both, "both hydraulic legs are latched by the two players")
	if both:
		_sample("host_both_legs")
		check(_interlock() == "", "with 2/2 legs the claw interlock is open")
		var capt: bool = await _wait_until(func() -> bool: return _capturable(), 120.0, "core capturable")
		check(capt, "core entered the capture band (cap net=%.3f limit=%.3f omega=%.3f)" % [
			_core_net(), float(core.call("capture_net_limit")), float(core.call("get_omega"))])
		_face(_v(0, 1.2, 6.9))
		await _wait(0.3)
		await _press_e()
		var locked: bool = await _wait_until(func() -> bool: return _core_locked(), 60.0, "hydraulic claw closes")
		check(locked, "hydraulic claw locked the core through the real console E")
		check(_has_credit("lock_assist"), "host earned lock_assist credit")
		_sample("host_core_locked")

	# --- C: extraction damper --------------------------------------------
	stage_name = "act05_damper"
	await _walk_path([
		_v(0.0, 0.0, 10.5), _v(11.1, 0.0, 10.5), _v(11.1, 0.0, 2.0),
		_v(11.1, 0.0, -2.0), _v(8.0, 0.0, -2.3), _v(6.4, 0.0, -2.65)
	], 0.8, "host to damper")
	var opd: bool = await _operate_at(_v(6.4, 0.0, -2.65), _v(6.4, 1.2, -4.4), "damper", "host damper")
	check(opd, "host operates the extraction damper with real E")
	if opd:
		Input.action_press("move_forward")
		var t3 := 0.0
		while t3 < 12.0 and not _damper_latched():
			await _wait(0.25)
			t3 += 0.25
		Input.action_release("move_forward")
		log_line("DAMPER t=%.1f latched=%s" % [t3, str(_damper_latched())])
		await _press_e()
	check(_damper_latched(), "extraction damper latched by real input")
	check(_has_credit("damper_latch"), "host earned damper_latch credit")

	# --- C: wait for the client's carriage push, then take the data ------
	stage_name = "act05_isolation"
	var sep: bool = await _wait_until(func() -> bool: return _iso_sep(), 300.0, "client separates the extraction coupling")
	check(sep, "extraction coupling separated by the client's real carriage push")
	await _wait_until(func() -> bool: return bool((level.get("data_plinth") as Object).get("revealed_flag")), 60.0, "navigation data revealed")
	stage_name = "act05_data"
	await _walk_path([
		_v(8.2, 0.0, -2.65), _v(8.2, 0.0, -6.5), _v(5.0, 0.0, -6.5),
		_v(4.8, 0.0, -9.6), _v(-3.0, 0.0, -9.6), _v(-3.0, 0.0, -8.3)
	], 1.0, "host to data plinth")
	_face(_v(-3.0, 1.0, -9.1))
	await _wait(0.3)
	await _press_e()
	var data_ok: bool = await _wait_until(func() -> bool: return bool(story.get("data_taken")), 40.0, "navigation data taken")
	check(data_ok, "navigation data taken through the plinth with real E")
	check(_has_credit("data_take"), "host earned data_take credit")
	check(bool((level.get("exit_door") as Object).get("should_open")), "navigation data unlocked the west exit blast door")
	_sample("host_data_taken")

	# --- participation gate: every active player has A/B/C --------------
	stage_name = "act05_gate"
	var gate_ok: bool = await _wait_until(func() -> bool: return bool(session.call("can_finish")), 90.0, "participation gate")
	check(gate_ok, "participation gate satisfied by real credits on both sides")
	if not gate_ok:
		log_line("GATE_TEXT %s" % str(session.call("gate_text")))
		log_line("LEDGER %s" % _ledger_line())
	_sample("host_gate")
	_sample("host_pre_exit")

	# --- evacuation: walk the real corridor into the exit trigger --------
	stage_name = "act05_evacuate"
	await _walk_path([
		_v(-4.9, 0.0, -8.3), _v(-4.9, 0.0, -9.6), _v(-8.0, 0.0, -9.6),
		_v(-9.5, 0.0, -6.0), _v(-9.5, 0.0, -2.5),
		_v(-13.4, 0.0, -2.0), _v(-17.5, 0.0, -2.0), _v(-25.5, 0.0, -2.0)
	], 1.3, "host exit corridor")
	var to_finale: bool = await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == FINALE_NAME, 60.0, "Finale scene")
	check(to_finale, "host reached the real exit, settled Act05 and entered the Finale")
	await _wait(1.2)
	_check_finale()


# ---------------------------------------------------------------------------
# Client flow
# ---------------------------------------------------------------------------
func _client_flow() -> void:
	stage_name = "act05_entry"
	await _walk_path([_v(0, 4.0, 30.0), _v(0, 4.0, 26.2)], 1.2, "client tunnel")
	await _walk_to(_v(0, 4.0, 24.7), 8.0, 0.8, "client shutter stand")
	_face(_v(0, 5.1, 24.2))
	await _wait(0.3)
	await _press_e()
	check(bool(player.get("operating")), "client grabbed the jammed shutter with real E")
	if bool(player.get("operating")):
		await _hold("move_forward", 4.2)
		await _press_e()
	check(bool((level.get("push_door") as Object).get("is_opened")), "client opened the jammed shutter by holding W")
	await _walk_path([_v(0, 4.0, 22.5), _v(0, 4.0, 12.4)], 1.3, "client through shutter")
	check(await _wait_until(func() -> bool: return int(story.get("stage")) >= 2, 30.0, "hall trigger"),
		"client entering the hall advanced the story to the instability stage")

	# --- descend the west ramp (the east ramp is blocked by the duty board) ---
	await _walk_path([
		_v(-4.2, 4.0, 10.4), _v(-4.2, 1.4, 4.4), _v(-4.2, 0.0, 1.5)
	], 1.2, "client west ramp")
	check((player.global_position as Vector3).y < 0.6, "client reached the hall floor by walking the west ramp")

	# --- A: east stabilizer, but wait for the host's west leg + counterweight
	stage_name = "act05_east_leg"
	var east_stand := _v(4.55, 0.0, -10.13)
	var east_area := _v(5.38, 1.3, -9.19)
	await _walk_path([
		_v(-4.9, 0.0, 1.5), _v(-4.9, 0.0, 0.4), _v(-5.6, 0.0, 0.4),
		_v(-5.6, 0.0, -5.0), _v(-4.9, 0.0, -6.0), _v(-4.9, 0.0, -9.6),
		_v(6.8, 0.0, -9.6), _v(4.55, 0.0, -9.8)
	], 1.2, "client to east leg")
	var ope: bool = await _operate_at(east_stand, east_area, "stabilizer_e", "client east leg")
	check(ope, "client operates the east stabilizer with real E")
	if ope:
		var ready: bool = await _wait_until(func() -> bool:
			return _latched(0) and abs(_core_net()) <= 0.25, 180.0, "host locked the west leg and rebalanced")
		check(ready, "client waited until the host's west leg + counterweight were real")
		_sample("client_before_east_pump")
		check(_interlock().contains("1/2"), "client mirror sees the 1/2 leg interlock before it pumps")
		Input.action_press("move_forward")
		var t := 0.0
		while t < 30.0:
			await _wait(0.25)
			t += 0.25
			if _latched(1):
				break
		Input.action_release("move_forward")
		log_line("PUMP east t=%.1f latched=%s pos=%s" % [t, str(_latched(1)), str(player.global_position)])
		await _press_e()
	check(_latched(1), "east stabilizer latched by the client's real pumping")
	check(_has_credit("stabilizer_lock"), "client earned stabilizer_lock credit")
	_sample("client_after_east_leg")

	# --- B: emergency brake during a real warning -----------------------
	stage_name = "act05_brake"
	await _walk_path([
		_v(4.55, 0.0, -9.8), _v(6.8, 0.0, -9.6), _v(-4.9, 0.0, -9.6),
		_v(-4.9, 0.0, -4.2), _v(-6.6, 0.0, -4.2), _v(-9.5, 0.0, -2.5),
		_v(-11.8, 0.0, -2.2), _v(-13.12, 0.0, -2.9)
	], 1.2, "client to brake")
	var opb: bool = await _operate_at(_v(-13.12, 0.0, -2.9), _v(-13.12, 1.3, -3.05), "brake*", "client brake")
	check(opb, "client operates an emergency brake pump with real E")
	if opb:
		var both_pumps: bool = await _wait_until(func() -> bool: return _brake_both_claimed(), 300.0,
			"both brake pumps claimed")
		check(both_pumps, "client sees both players manning the two brake pumps")
		var caught := false
		for _warning in range(4):
			var warn: bool = await _wait_until(func() -> bool:
				return float(surge.get("warning_left")) > 2.0, 240.0, "surge warning")
			if not warn:
				break
			log_line("BRAKE_WARNING warning_left=%.1f state=%s" % [
				float(surge.get("warning_left")), str(surge.get("state"))])
			Input.action_press("move_forward")
			var bt := 0.0
			while bt < 4.0 and not bool((level.get("brake") as Object).get("latched")):
				await _wait(0.2)
				bt += 0.2
			Input.action_release("move_forward")
			await _wait(0.3)
			if _has_credit("surge_response"):
				caught = true
			if bool((level.get("brake") as Object).get("latched")):
				break
		log_line("BRAKE_END latched=%s press=%.2f credits=%s" % [
			str(bool((level.get("brake") as Object).get("latched"))),
			float((level.get("brake") as Object).get("pressure")), str(caught)])
		await _press_e()
	check(_has_credit("surge_response"), "client earned surge_response by pumping the brake during a real warning")
	check(bool((level.get("brake") as Object).get("latched")), "emergency brake latched by the client's real pumping")
	check(_has_credit("brake_charge") or _has_credit_for(1, "brake_charge"),
		"the brake latch credit was earned by one of the two real pump operators")
	_sample("client_after_brake")

	# --- C: isolation safety pin (after the host really locks the core) --
	stage_name = "act05_isolation_pin"
	await _walk_path([
		_v(-11.8, 0.0, -2.2), _v(-9.5, 0.0, -2.5), _v(-6.6, 0.0, -4.2),
		_v(-4.9, 0.0, -4.2), _v(-4.9, 0.0, -7.6), _v(5.0, 0.0, -7.6),
		_v(5.0, 0.0, -6.0), _v(10.6, 0.0, -6.0), _v(10.7, 0.0, -6.0)
	], 1.2, "client to isolation bay")
	var locked_seen: bool = await _wait_until(func() -> bool: return _core_locked(), 300.0, "host locks the core")
	check(locked_seen, "client mirror sees the core locked by the host")
	var pin_ok := false
	for _attempt in range(6):
		_face(_v(10.5, 1.9, -9.0))
		await _wait(0.3)
		await _press_e()
		pin_ok = await _wait_until(func() -> bool: return _iso_pin(), 6.0, "pin_out")
		if pin_ok:
			break
		await _walk_to(_v(10.7, 0.0, -6.0), 4.0, 0.8, "client pin stand")
	check(pin_ok, "client pulled the isolation safety pin with real E")
	check(_has_credit("isolation_pin"), "client earned isolation_pin credit")
	_sample("client_pin_out")

	# --- C: push the carriage after the host loads the damper -----------
	stage_name = "act05_carriage"
	var damped: bool = await _wait_until(func() -> bool:
		return float((level.get("damper") as Object).call("damper_effect")) >= 0.35, 240.0, "host loads the damper")
	check(damped, "client sees the damper loaded by the host")
	var opc := false
	for _attempt in range(8):
		await _walk_to(_v(10.7, 0.0, -5.4), 4.0, 0.7, "client carriage stand")
		_face(_v(10.5, 1.2, -7.2))
		await _wait(0.3)
		await _press_e()
		if bool(player.get("operating")):
			opc = true
			break
		await _wait(0.5)
	check(opc, "client operates the isolation carriage with real E")
	if opc:
		Input.action_press("move_forward")
		var ct := 0.0
		while ct < 12.0 and not _iso_sep():
			await _wait(0.25)
			ct += 0.25
		Input.action_release("move_forward")
		log_line("CARRIAGE t=%.1f separated=%s progress=%.2f" % [
			ct, str(_iso_sep()), float((level.get("isolation") as Object).get("progress"))])
		await _press_e()
	check(_iso_sep(), "extraction coupling separated by the client's real carriage push")
	check(_has_credit("carriage_push"), "client earned carriage_push credit")
	_sample("client_isolation_done")

	# --- data + evacuation ----------------------------------------------
	stage_name = "act05_data_mirror"
	var data_seen: bool = await _wait_until(func() -> bool:
		return bool(story.get("data_taken")) and bool((level.get("data_plinth") as Object).get("revealed_flag")),
		240.0, "host takes the navigation data")
	check(data_seen, "client mirror sees the navigation data taken by the host")
	check(bool((level.get("exit_door") as Object).get("should_open")), "client mirror sees the exit blast door unlocked")
	_sample("client_data_taken")

	# The client mirror is compared while both peers are still in the real Act05
	# scene (before the scene switch frees the world nodes).
	stage_name = "act05_mirror"
	_sample("client_pre_exit")
	check(_core_locked(), "client mirror: core locked by the host")
	check(_latched(0) and _latched(1), "client mirror: both stabilizer legs latched")
	check(_damper_latched(), "client mirror: extraction damper latched")
	check(_iso_pin() and _iso_sep(), "client mirror: isolation pin pulled and coupling separated")
	check(bool(story.get("data_taken")), "client mirror: navigation data taken")
	check(int(story.get("stage")) >= 8, "client mirror: story stage reached EVACUATE")
	check(bool((session.get("ledger") as Object).call("is_ready", 1)) \
		and bool((session.get("ledger") as Object).call("is_ready", 2)),
		"client mirror: both participation records are ready")
	var completion_seen: bool = await _wait_until(func() -> bool:
		return bool(story.call("completed_flag")), 120.0, "host completion mirrored to the client")
	check(completion_seen, "client mirror received the host's completed state before the scene switch")
	if completion_seen:
		var text: String = str(story.call("completion_text"))
		var final_stage: int = int(story.get("stage"))
		check(text.length() > 20, "client mirrored the host's completion text instead of inventing one")
		check(final_stage == 9, "client story stage mirror is COMPLETED")

	stage_name = "act05_evacuate"
	await _walk_path([
		_v(5.0, 0.0, -6.0), _v(5.0, 0.0, -7.6), _v(-4.9, 0.0, -7.6),
		_v(-4.9, 0.0, -4.2), _v(-6.6, 0.0, -4.2), _v(-9.5, 0.0, -2.5),
		_v(-13.4, 0.0, -2.0), _v(-17.5, 0.0, -2.0), _v(-25.5, 0.0, -2.0)
	], 1.3, "client exit corridor")
	var to_finale: bool = await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == FINALE_NAME, 120.0, "Finale scene")
	check(to_finale, "client followed the host's reliable Act05 -> Finale scene switch")
	await _wait(1.2)
	_check_finale()


# ---------------------------------------------------------------------------
# Finale assertions
# ---------------------------------------------------------------------------
func _check_finale() -> void:
	var hist: Dictionary = hub.get("chapter_history") as Dictionary
	var act5: Dictionary = hist.get("act05", {}) as Dictionary
	check(str(current_scene.name) == FINALE_NAME, "settlement scene is the official Finale")
	check(bool(act5.get("completed", false)), "SessionHub act05 record is completed")
	check(str(hub.get("current_chapter")) == "finale", "SessionHub current_chapter advanced to finale")
	var participants: Dictionary = act5.get("participants", {}) as Dictionary
	var ready: Array = participants.get("ready", []) as Array
	check(ready.size() == 2, "both participants are recorded as ready in the Act05 completion payload (ready=%d)" % ready.size())
	log_line("FINALE act05=%s" % JSON.stringify(act5))


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
func _finish(passed: bool) -> void:
	var report: Dictionary = {
		"probe": "r2_act05_full_probe.gd",
		"role": role,
		"tag": tag,
		"passed": passed and failures.is_empty(),
		"checks": checks,
		"failures": failures,
		"elapsed_seconds": float(Time.get_ticks_msec() - started_msec) / 1000.0,
		"samples": samples,
		"log": log_lines,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var path: String = out_dir.path_join("r2_act05_%s_%s.json" % [role, tag])
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
			log_line("REPORT %s" % path)
	log_line("RESULT role=%s checks=%d failures=%d passed=%s" % [
		role, checks, failures.size(), str(passed and failures.is_empty())])
	if passed and failures.is_empty():
		print("R2_OK role=%s" % role)
	else:
		print("R2_FAIL role=%s %s" % [role, str(failures)])
	if live_log != null:
		live_log.flush()
		live_log.close()
		live_log = null
	quit(0 if (passed and failures.is_empty()) else 1)

