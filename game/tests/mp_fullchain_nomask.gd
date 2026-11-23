extends "res://tests/final_full_chain_probe.gd"

## ACT01-MP-FULLCHAIN-R1 · 3/4-player five-act chain harness.
##
## Every process boots the official Launcher, presses the real host/join button
## and joins ONE SessionHub ENet peer. The same pid then walks the SAME session
## through Act01 -> Act23Chapter -> Resonance04 -> Main (Act05) -> Finale.
##
## Nothing here writes gameplay state: no complete_chapter, no change_scene, no
## credit/ledger write, no teleport. Movement is real input (WASD/E/F/B/R/Winch),
## cross-process gates use production flags plus a small phase file that carries
## only "whose turn is it" markers (never world state).
##
## Roles are assigned by REAL pid (1..N), not by launch order:
##   Act01  - every seat performs at least two distinct production phases and
##            all seats simultaneously grab different catwalk rails.
##   Act23  - pid2 does the hook/drum/pin; pid3 holds the guide wheel; pid4
##            props the safety bracket; pid1 drives. Everyone rides and brakes.
##   Act04  - every seat rings the bell with real E/W input (phase-04 gate) in
##            pid order; pid1 restores the crystal chain; all follow the switch.
##   Act05  - pid1 west leg + claw lock; pid2 east leg + damper; pid3 west
##            counterweight + isolation pin + data; pid4 east counterweight +
##            carriage push. B is earned on the real catwalk rails / brake pumps
##            during a real surge warning.
##
## Output: mp_<role>_<pid>.json in --out plus RESULT lines on stdout.

const MP_PHASE := "mp_phase.json"
const MP_WAIT := 0.0

var expected_players: int = 2
var launch_index: int = 0
var stop_after: String = ""
var debug_act23: bool = false
var _a23_trace: int = 0
var _a23_layer0: int = 0
var _a23_mask0: int = 0
var me: int = 1
var my_role_pid: int = 1

var reach: Dictionary = {
	"launcher": false, "act01": false, "act23": false, "act04": false,
	"act05": false, "finale": false,
}
var identity: Dictionary = {}
var bodymap: Dictionary = {}
var participation: Dictionary = {}
var handoffs: Array = []
var act_times: Dictionary = {}
var run_started_ms: int = 0
var act_started_ms: int = 0
var blocked_at: String = ""
var blocked_detail: String = ""
var mp_checks_before_finish: int = 0

# ---------------------------------------------------------------- lifecycle --
func _parse_args() -> void:
	super._parse_args()
	for a in OS.get_cmdline_user_args():
		var s: String = str(a)
		if s.begins_with("--players="): expected_players = int(s.split("=")[1])
		elif s.begins_with("--player="): launch_index = int(s.split("=")[1])
		elif s.begins_with("--stop="): stop_after = s.split("=")[1]
		elif s == "--debug_act23": debug_act23 = true
	if shots_dir == "":
		shots_dir = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-act01-mp-fullchain-r1/screenshots"
	if launch_index == 0:
		role = "host"
	else:
		role = "client"

func _wait_real(seconds: float) -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await process_frame

func _scene_now() -> String:
	return str(current_scene.name) if current_scene != null else "null"

func _write_json_ev(name: String, data: Dictionary) -> void:
	if out_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f: FileAccess = FileAccess.open(out_dir.path_join(name), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()

func _read_json_ev(name: String) -> Dictionary:
	if out_dir == "":
		return {}
	var path: String = out_dir.path_join(name)
	if not FileAccess.file_exists(path):
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var j: JSON = JSON.new()
	if j.parse(text) != OK:
		return {}
	var v: Variant = j.data
	return v as Dictionary if v is Dictionary else {}

func _phase_set(name: String, extra: Dictionary = {}) -> void:
	if role != "host":
		return
	var doc: Dictionary = {"name": name, "seq": Time.get_ticks_msec(),
		"unix_ms": Time.get_unix_time_from_system() * 1000.0}
	for k in extra.keys():
		doc[k] = extra[k]
	_write_json_ev(MP_PHASE, doc)
	log_line("MP_PHASE %s %s" % [name, JSON.stringify(extra)])

func _phase() -> String:
	return str(_read_json_ev(MP_PHASE).get("name", ""))

func _wait_phase(name: String, timeout_s: float) -> bool:
	return await _wait_until(func() -> bool: return _phase() == name, timeout_s)

func _mark_blocked(where: String, detail: String) -> void:
	if blocked_at == "":
		blocked_at = where
		blocked_detail = detail
		log_line("MP_BLOCKED where=%s detail=%s" % [where, detail])

func _reach(act: String) -> void:
	reach[act] = true
	act_times[act] = snappedf(float(Time.get_ticks_msec() - run_started_ms) / 1000.0, 0.1)
	log_line("MP_REACH %s t=%.1f" % [act, float(act_times[act])])

func _ledger_view() -> Dictionary:
	var hub_node: Node = root.get_node_or_null("/root/SessionHub")
	if hub_node == null:
		return {}
	var sess: Variant = hub_node.get("session")
	if sess == null:
		return {}
	var led: Variant = (sess as Object).get("ledger")
	if led == null:
		return {}
	var out: Dictionary = {}
	for pid in (led as Object).call("player_ids"):
		var rec: Dictionary = (led as Object).call("get_record", int(pid))
		out[int(pid)] = {
			"phases": (rec.get("phases", {}) as Dictionary).duplicate(true),
			"kinds": _ledger_kinds(led, int(pid)),
			"status": str(rec.get("status", "")),
			"name": str(rec.get("name", "")),
			"ready": bool((led as Object).call("is_ready", int(pid))),
		}
	return out

func _ledger_kinds(led: Variant, pid: int) -> Array:
	var rec: Dictionary = (led as Object).call("get_record", pid)
	var kinds: Array = []
	var credits: Variant = rec.get("credits", {})
	if credits is Dictionary:
		for k in (credits as Dictionary).keys():
			kinds.append(str(k))
	var mirror: Variant = rec.get("kinds", [])
	if mirror is Array:
		for k in (mirror as Array):
			if not kinds.has(str(k)):
				kinds.append(str(k))
	kinds.sort()
	return kinds

func _has_credit(pid: int, kind: String) -> bool:
	var hub_node: Node = root.get_node_or_null("/root/SessionHub")
	if hub_node == null:
		return false
	var sess: Variant = hub_node.get("session")
	if sess == null:
		return false
	var led: Variant = (sess as Object).get("ledger")
	if led == null:
		return false
	return bool((led as Object).call("has_credit", pid, kind))

func _assert_identity_uniform(tag: String, pid_now: int) -> void:
	identity[tag] = pid_now
	if int(identity.get("act01", pid_now)) != pid_now:
		check(false, "%s pid changed from %d to %d" % [tag, int(identity.get("act01", pid_now)), pid_now])
	else:
		check(true, "%s keeps the same pid %d" % [tag, pid_now])

# --------------------------------------------------------------- full chain --

func _process(delta: float) -> bool:
	var keep: bool = super._process(delta)
	if debug_act23 and _a23_trace < 240 and current_scene != null and str(current_scene.name) == "Act23Chapter":
		var slice: Node = _find_act23_slice()
		if slice != null:
			var pl: Variant = slice.get("player")
			if pl != null and is_instance_valid(pl):
				if _a23_trace % 5 == 0:
					var body: CharacterBody3D = pl as CharacterBody3D
					log_line("A23_TRACE f=%d pos=%s vel=%s floor=%s slot=%d coop=%d" % [_a23_trace, str(body.global_position), str(body.velocity.snapped(Vector3(0.01,0.01,0.01))), str(body.is_on_floor()), int(slice.get("local_slot")), int(slice.get("coop").get("local_slot"))])
				_a23_trace += 1
	return keep

func _run_full() -> bool:
	run_started_ms = Time.get_ticks_msec()
	if debug_act23:
		# DEBUG-ONLY shortcut (never used for acceptance runs).
		if role == "host":
			var ready_guard := 0
			while ready_guard < 900:
				var n := 0
				for i in range(1, expected_players):
					if not _read_json_ev("mp_debug_ready_%d.json" % i).is_empty(): n += 1
				if n >= expected_players - 1: break
				await _wait(0.2)
				ready_guard += 1
			await _wait(0.5)
			hub.call("complete_chapter", "act01", {"debug": true}, "act23", "res://scenes/act23.tscn", {})
			await _wait_scene("Act23Chapter", 120.0)
			await _wait(0.2)
			return await _drive_act23_n()
		else:
			var want := launch_index + 1
			var id_guard := 0
			while id_guard < 900:
				var n2: Node = hub.get("net") as Node
				if n2 != null and int(n2.get("local_pid")) == want and bool(n2.get("_act1_welcomed")): break
				await _wait(0.2)
				id_guard += 1
			_write_json_ev("mp_debug_ready_%d.json" % launch_index, {"pid": want})
			await _wait_scene("Act23Chapter", 180.0)
			await _wait(0.2)
			return await _drive_act23_n()
	run_started_ms = Time.get_ticks_msec()
	reach["launcher"] = true
	# --- Act01 -------------------------------------------------------------
	act_started_ms = Time.get_ticks_msec()
	if not await _drive_act01_n():
		_mark_blocked("act01", "Act01 driver failed: %s" % str(failures))
		return false
	_reach("act01")
	if not await _wait_scene("Act23Chapter", 900.0):
		_mark_blocked("act01_handoff", "no Act23Chapter")
		check(false, "reached Act23Chapter after Act01")
		return false
	await _wait(0.2)
	if stop_after == "act01":
		return true
	# --- Act23 -------------------------------------------------------------
	act_started_ms = Time.get_ticks_msec()
	if not await _drive_act23_n():
		_mark_blocked("act23", "Act23 driver failed: %s" % str(failures))
		return false
	_reach("act23")
	if not await _wait_scene_any(["Act4", "Resonance04"], 900.0):
		_mark_blocked("act23_handoff", "no Resonance04")
		check(false, "reached Resonance04 after Act23")
		return false
	await _wait(2.0)
	if stop_after == "act23":
		return true
	# --- Act04 -------------------------------------------------------------
	act_started_ms = Time.get_ticks_msec()
	if not await _drive_act04_n():
		_mark_blocked("act04", "Act04 driver failed: %s" % str(failures))
		return false
	_reach("act04")
	if not await _wait_scene("Main", 900.0):
		_mark_blocked("act04_handoff", "no Main")
		check(false, "reached Main after Act04")
		return false
	await _wait(2.0)
	if stop_after == "act04":
		return true
	# --- Act05 -------------------------------------------------------------
	act_started_ms = Time.get_ticks_msec()
	if not await _drive_act05_n():
		_mark_blocked("act05", "Act05 driver failed: %s" % str(failures))
		return false
	_reach("act05")
	if not await _wait_scene("Finale", 600.0):
		_mark_blocked("act05_handoff", "no Finale")
		check(false, "reached Finale after Act05")
		return false
	await _wait(2.0)
	if stop_after == "act05":
		return true
	# --- Finale ------------------------------------------------------------
	if not await _check_finale_n():
		_mark_blocked("finale", "finale assertions failed")
		return false
	_reach("finale")
	return true

# ===========================================================================
# ACT 01 - real Launcher click + 3/4-seat key path
# ===========================================================================
func _a1n_flag(key: String) -> bool:
	var flags: Dictionary = _a1_flags()
	return bool(flags.get(key, false))

func _a1n_credit_kinds(pid: int) -> Array:
	if not _a1_ok():
		return []
	var credits: Dictionary = _a1_stage.get("credits") as Dictionary
	var rec: Variant = credits.get(pid)
	if rec is Dictionary:
		return ((rec as Dictionary).get("kinds", {}) as Dictionary).keys()
	return []

func _a1n_phase_count(pid: int) -> int:
	return (_a1_credit_phases(pid) as Dictionary).size()

func _a1n_wait_flag(key: String, timeout_s: float) -> bool:
	return await _wait_until(func() -> bool: return _a1n_flag(key), timeout_s)

func _a1n_press_until(id: String, flag: String, tries: int, gap := 1.0) -> bool:
	for _i in range(tries):
		if _a1n_flag(flag):
			return true
		if await _a1_press(id, 0.14):
			await _wait_real(gap)
		else:
			await _wait(0.6)
	return _a1n_flag(flag)

func _rail_for_pid(pid: int) -> String:
	match pid:
		1: return "grab_212"
		2: return "grab_236"
		3: return "grab_258"
		4: return "grab_316"
	return "grab_212"

func _rail_z(pid: int) -> float:
	match pid:
		1: return -21.2
		2: return -23.6
		3: return -25.8
		4: return -31.6
	return -21.2

func _goto_ramp_foot() -> void:
	await _a1_walk(Vector3(2.2, 0, -15.4), 7.0, "ramp foot")
	await _a1_walk(Vector3(2.35, 0, -18.4), 4.0, "ramp climb")
	await _a1_walk(Vector3(2.35, 0, -20.0), 2.0, "ramp top step")
	await _jump_forward_a1(1.0, "onto catwalk")

func _jump_forward_a1(seconds: float, label: String) -> void:
	Input.action_press("move_forward")
	await physics_frame
	Input.action_press("jump")
	await _wait(0.12)
	Input.action_release("jump")
	var frames: int = int(seconds * 60.0)
	for _i in range(frames):
		await physics_frame
		if not _in_tree(player) or current_scene != _a1_stage:
			break
	Input.action_release("move_forward")
	await physics_frame
	if _in_tree(player):
		log_line("JUMP01 %s pos=%s" % [label, str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])

func _a1n_walk_down_from_catwalk() -> void:
	# pid4''s rail (z=-31.6) is past the mid-span; walk back along the deck
	# first, otherwise the direct line to the ramp can step off the far end.
	if _rail_z(me) < -27.0:
		await _a1_walk(Vector3(2.0, 3.42, -25.8), 5.0, "catwalk mid return")
	await _a1_walk(Vector3(2.35, 3.42, -18.4), 4.5, "catwalk back to ramp")
	await _a1_walk(Vector3(2.2, 0.6, -15.6), 5.0, "ramp down")
	await _a1_walk(Vector3(2.2, 0, -15.4), 1.5, "ramp foot floor")

func _drive_act01_n() -> bool:
	_stage_now = "act01"
	_a1_stage = current_scene
	stage = _a1_stage
	if _a1_stage == null or str(_a1_stage.name) != "Act01":
		check(false, "Act01 scene after the launcher click (got %s)" % str(current_scene.name if current_scene != null else "null"))
		return false
	player = _a1_stage.get("local_player") as Node
	if player == null:
		check(false, "Act01 local player exists")
		return false
	me = int(_a1_stage.get("local_pid"))
	identity["act01"] = me
	check(me >= 1 and me <= expected_players, "Act01 seat pid in 1..%d (pid=%d)" % [expected_players, me])
	var net_node: Node = root.get_node_or_null("/root/SessionHub/CoopNet")
	check(net_node != null and int(net_node.get("local_pid")) == me,
		"Act01 CoopNet.local_pid matches seat (net=%d seat=%d)" % [int(net_node.get("local_pid")) if net_node != null else -1, me])
	check(not (_a1_stage.get("remotes") as Dictionary).has(me), "no self avatar in Act01")
	_record_stage("act01_begin", {"pid": me, "pos": str(player.global_position)})

	# --- wait for the whole crew (real join, no fake seats) ----------------
	if role == "host":
		var all: bool = await _wait_until(func() -> bool:
			var active: Dictionary = _a1_stage.get("active_pids") as Dictionary
			var reg: Dictionary = net_node.get("_act1_registered_pids") as Dictionary
			return active.size() >= expected_players and reg.size() >= expected_players - 1, 300.0)
		check(all, "host registered %d real seats (active=%s)" % [
			expected_players, str((_a1_stage.get("active_pids") as Dictionary).keys())])
		var pids: Array = (_a1_stage.get("active_pids") as Dictionary).keys()
		pids.sort()
		var want: Array = []
		for i in range(1, expected_players + 1): want.append(i)
		check(str(pids) == str(want), "host active pids are exactly 1..%d (%s)" % [expected_players, str(pids)])
		check(await _wait_until(func() -> bool:
			return (_a1_stage.get("remotes") as Dictionary).size() >= expected_players - 1, 120.0),
			"host renders %d remote bodies" % (expected_players - 1))
	else:
		var welcomed: bool = await _wait_until(func() -> bool:
			return net_node != null and bool(net_node.get("_act1_welcomed")) and bool(net_node.get("_act1_bootstrapped")), 300.0)
		check(welcomed, "client applied welcome + authoritative bootstrap")
		check(int(net_node.get("_act1_welcome_pid")) == me,
			"welcome pid == seat pid (welcome=%d seat=%d)" % [int(net_node.get("_act1_welcome_pid")), me])
		var all_seen: bool = await _wait_until(func() -> bool:
			return (_a1_stage.get("active_pids") as Dictionary).size() >= expected_players, 180.0)
		check(all_seen, "client sees %d active pids (%s)" % [
			expected_players, str((_a1_stage.get("active_pids") as Dictionary).keys())])
		var avatars: bool = await _wait_until(func() -> bool:
			return (_a1_stage.get("remotes") as Dictionary).size() >= expected_players - 1, 180.0)
		check(avatars, "client renders %d remote bodies" % (expected_players - 1))
	bodymap["act01"] = {
		"seat": me,
		"remotes": (_a1_stage.get("remotes") as Dictionary).keys(),
		"active": (_a1_stage.get("active_pids") as Dictionary).keys(),
	}
	await _wait(0.8 + 0.7 * me)

	# --- 1. entry ----------------------------------------------------------
	if me == 1:
		await _a1_walk(Vector3(0, 0, 14.0), 4.0, "entry approach")
		check(await _a1n_wait_flag("debris_cleared", 120.0), "host sees pid2 clear the collapsed gantry")
		await _wait_real(1.6)
		check(not _a1n_credit_kinds(1).has("entry_shove"),
			"host did not claim pid2's gantry shove credit")
		check(await _a1n_wait_flag("latch_released", 60.0), "host sees the client's latch release")
		await _a1_walk(Vector3(2.4, 0, 10.5), 3.0, "door handle east")
		await _a1_hold("door_handle", 7.4)
		check(await _a1n_wait_flag("door_open", 20.0), "host opened the industrial door by holding E")
	elif me == 2:
		await _a1_walk(Vector3(3.1, 0, 10.35), 6.0, "latch side")
		var debris: bool = false
		for i in range(5):
			if _a1n_flag("debris_cleared"): debris = true; break
			var g: Node = (_a1_stage.get("interactables") as Dictionary).get("shove_gantry") as Node
			if g == null: break
			var gp: Vector3 = g.global_position
			await _a1_walk(Vector3(gp.x + 1.7, 0, gp.z + 1.25), 2.4, "gantry push %d" % i, 0.45)
			await _a1_press("shove_gantry", 0.14)
			await _wait(1.2)
		debris = _a1n_flag("debris_cleared")
		check(debris, "pid2 cleared the collapsed gantry with a real shove (entry credit owner)")
		check(await _a1n_press_until("release_latch", "latch_released", 5, 1.0),
			"pid2 released the mechanical latch (entry credit owner)")
	else:
		await _a1_walk(Vector3(0, 0, 11.0), 5.0, "wait outside door")
		check(await _a1n_wait_flag("door_open", 150.0), "pid%d sees the door open" % me)

	await _a1n_wait_flag("door_open", 150.0)
	await _a1_walk(Vector3(0, 0, 6.4), 5.0, "through doorway")
	await _a1_walk(Vector3(0, 0, 4.0), 2.5, "airlock exit")

	# --- 2. power ----------------------------------------------------------
	if me == 1:
		await _a1_walk(Vector3(-3.0, 0, 0.4), 3.5, "power room west")
		await _a1_walk(Vector3(-7.8, 0, 0.4), 3.5, "power room north")
		await _a1_walk(Vector3(-8.0, 0, -2.5), 2.2, "cart rear")
		await _a1_press("cart_push", 0.14)
		check(bool(player.get("external_hold")), "host gripped the power trolley")
		Input.action_press("move_forward")
		for _i in range(150): await physics_frame
		Input.action_release("move_forward")
		await _wait(0.3)
		await _tape_interact_a1()
		await _wait(0.6)
		await _a1_walk(Vector3(-4.6, 0, -0.4), 2.8, "around cart north")
		await _a1_walk(Vector3(-1.0, 0, -0.5), 3.6, "rail bracket")
		await _a1_walk(Vector3(-0.95, 0, -1.15), 1.6, "bracket approach")
		await _a1_press("rail_shove", 0.12)
		await _wait(0.8)
		check(_a1n_flag("rail_cleared"), "host cleared the rail bracket")
		await _a1_walk(Vector3(-1.0, 0, -0.4), 2.2, "return north")
		await _a1_walk(Vector3(-7.8, 0, -0.4), 3.6, "cart rear north")
		await _a1_walk(Vector3(-7.8, 0, -2.55), 1.8, "cart rear center")
		await _a1_walk(Vector3(-7.2, 0, -2.55), 1.2, "cart handle")
		await _a1_press("cart_push", 0.14)
		Input.action_press("move_forward")
		for _i in range(520): await physics_frame
		Input.action_release("move_forward")
		await _wait(1.0)
		await _tape_interact_a1()
		await _wait(0.5)
		check(_a1n_flag("power_docked"), "host docked the power trolley")
		await _a1_walk(Vector3(1.5, 0, -0.5), 2.2, "cart west north")
		await _a1_walk(Vector3(1.5, 0, -5.0), 2.8, "socket west")
		await _a1_walk(Vector3(1.95, 0, -5.0), 1.2, "winch")
		await _a1_press("power_winch", 0.14)
		await _wait(2.6)
		check(_a1n_flag("power_seated"), "host moved the power module into the socket")
		if expected_players == 2:
			await _a1_walk(Vector3(2.4, 0, -4.3), 2.6, "clamp west")
			check(await _a1n_press_until("power_clamp", "power_clamped", 5, 1.0),
				"host clamped the power module (2-player topology)")
	elif me == 3:
		await _a1_walk(Vector3(1.5, 0, -0.5), 3.0, "cart west")
		await _a1_walk(Vector3(2.4, 0, -4.3), 3.0, "clamp west")
		check(await _a1n_wait_flag("power_seated", 180.0), "pid3 sees the power module seated")
		check(await _a1n_press_until("power_clamp", "power_clamped", 5, 1.0),
			"pid3 clamped the power module (power credit owner)")
	else:
		await _a1_walk(Vector3(2.6, 0, -4.3), 4.0, "clamp queue")

	check(await _a1n_wait_flag("power_clamped", 150.0), "power module clamped (networked flag)")
	await _a1_walk(Vector3(0, 0, -8.0), 3.0, "power exit")
	await _a1_walk(Vector3(-1.0, 0, -12.8), 3.5, "vent threshold")

	# --- 3. ventilation ----------------------------------------------------
	if me == 1:
		await _a1_walk(Vector3(-7.8, 0, -14.8), 5.0, "west gallery north")
		await _a1_walk(Vector3(-7.8, 0, -18.0), 2.4, "control gallery")
		check(await _a1n_wait_flag("coupling_engaged", 200.0), "host sees the coupling engaged")
		await _a1_walk(Vector3(-7.8, 0, -23.0), 2.8, "fan start")
		check(await _a1n_press_until("start_fan", "fan_started", 4, 1.0),
			"host started the main fan (vent credit)")
		await _a1_walk(Vector3(-7.8, 0, -14.8), 3.6, "west gallery return")
		await _a1_walk(Vector3(7.0, 0, -14.8), 7.2, "east gallery north")
		await _a1_walk(Vector3(7.0, 0, -18.0), 2.4, "east gallery")
		await _a1_walk(Vector3(8.0, 0, -29.6), 5.2, "damper control")
		check(await _a1n_press_until("damper", "damper_open", 4, 1.0),
			"host opened the main duct damper (vent credit)")
	elif me == 3:
		await _a1_walk(Vector3(7.0, 0, -14.8), 7.2, "east hall north")
		await _a1_walk(Vector3(7.0, 0, -17.5), 2.2, "east hall")
		await _a1_walk(Vector3(7.7, 0, -22.3), 3.0, "rotor lock")
		check(await _a1n_press_until("rotor_lock", "rotor_lock_released", 4, 1.0),
			"pid3 removed the rotor lock (vent credit owner)")
		await _a1_walk(Vector3(8.1, 0, -28.15), 4.0, "coupling")
		check(await _a1n_press_until("coupling", "coupling_engaged", 4, 1.0),
			"pid3 engaged the drive coupling")
	elif me == 2:
		if expected_players == 2:
			await _a1_walk(Vector3(7.0, 0, -14.8), 7.2, "east hall north")
			await _a1_walk(Vector3(7.0, 0, -17.5), 2.2, "east hall")
			await _a1_walk(Vector3(7.7, 0, -22.3), 3.0, "rotor lock")
			check(await _a1n_press_until("rotor_lock", "rotor_lock_released", 4, 1.0),
				"pid2 removed the rotor lock (2-player vent owner)")
			await _a1_walk(Vector3(8.1, 0, -28.15), 4.0, "coupling")
			check(await _a1n_press_until("coupling", "coupling_engaged", 4, 1.0),
				"pid2 engaged the drive coupling (2-player vent owner)")
			await _a1_walk(Vector3(8.0, 0, -18.0), 4.0, "east return")
			await _a1_walk(Vector3(8.0, 0, -16.5), 2.0, "east north")
			await _a1_walk(Vector3(-7.8, 0, -16.5), 5.0, "north crossing")
			await _a1_walk(Vector3(-7.8, 0, -23.0), 3.0, "governor bay")
		else:
			await _a1_walk(Vector3(-7.8, 0, -14.8), 7.2, "west hall north")
			await _a1_walk(Vector3(-7.8, 0, -18.0), 2.4, "gallery")
			await _a1_walk(Vector3(-7.8, 0, -23.0), 3.0, "governor bay")
		check(await _a1n_wait_flag("fan_started", 260.0), "pid2 sees the fan started")
		if expected_players <= 3:
			await _a1_press("governor", 0.14)
			await _wait(1.0)
			check(_a1n_credit_kinds(2).has("governor"), "pid2 adjusted the governor (vent credit owner)")
		else:
			note("pid2 leaves the governor to pid4")
	else:
		await _a1_walk(Vector3(-7.8, 0, -14.8), 7.2, "west hall north")
		await _a1_walk(Vector3(-7.8, 0, -18.0), 2.4, "gallery")
		await _a1_walk(Vector3(-7.8, 0, -23.0), 3.0, "governor bay")
		await _a1n_wait_flag("fan_started", 260.0)
		await _a1_press("governor", 0.14)
		await _wait(1.0)
		check(_a1n_credit_kinds(4).has("governor"), "pid4 adjusted the governor (vent credit owner)")

	check(await _a1n_wait_flag("vent_complete", 200.0), "6 s pressure test completed (vent_complete)")
	await _shot("act01_vent")

	# --- 4. simultaneous catwalk grabs (all seats, different rails) --------
	if me == 1 or me == 3:
		await _a1_walk(Vector3(7.0, 0, -18.0), 4.0, "hall return")
		await _a1_walk(Vector3(7.0, 0, -14.8), 3.0, "hall north")
	else:
		await _a1_walk(Vector3(-7.8, 0, -18.0), 4.0, "hall return")
		await _a1_walk(Vector3(-7.8, 0, -14.8), 3.0, "hall north")
	await _a1_walk(Vector3(2.2, 0, -15.4), 3.0, "ramp foot")
	await _goto_ramp_foot()
	await _a1_walk(Vector3(2.0, 3.42, _rail_z(me)), 8.0, "rail %s" % _rail_for_pid(me))
	_write_json_ev("mp_a1_at_rail_%d.json" % me, {"pid": me, "ok": true})

	if role == "host":
		var all_here: bool = await _wait_until(func() -> bool:
			var rs: Dictionary = _a1_stage.get("remote_states") as Dictionary
			var n := 0
			for pid in rs.keys():
				var st: Dictionary = rs[pid] as Dictionary
				var p: Variant = st.get("pos", null)
				if p is Vector3 and (p as Vector3).y > 3.0 and (p as Vector3).z < -19.5:
					n += 1
			return n >= expected_players - 1, 150.0)
		check(all_here, "host sees all %d remote bodies on the catwalk" % (expected_players - 1))
		_phase_set("grab", {"rails": {1: "grab_212", 2: "grab_236", 3: "grab_258", 4: "grab_316"}})
		var own := await _grab_own_rail_a1()
		check(own, "host grabbed its own rail %s" % _rail_for_pid(1))
		var t0: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 150000:
			var n := 0
			for i in range(2, expected_players + 1):
				if not _read_json_ev("mp_a1_grab_%d.json" % i).is_empty(): n += 1
			if n >= expected_players - 1: break
			await process_frame
		var owners: Dictionary = _a1_stage.get("grab_owner") as Dictionary
		var distinct: Dictionary = {}
		for pid in owners.keys(): distinct[str(owners[pid])] = true
		check(owners.size() == expected_players, "host owns %d simultaneous grabs (%s)" % [owners.size(), str(owners)])
		check(distinct.size() == expected_players, "%d distinct rails owned at once" % distinct.size())
		var ok_all := true
		for i in range(2, expected_players + 1):
			var g: Dictionary = _read_json_ev("mp_a1_grab_%d.json" % i)
			ok_all = ok_all and bool(g.get("ok", false)) and int(g.get("pid", -1)) == i
		check(ok_all, "every client body reports its own grab")
		var release_pid := 3 if expected_players >= 3 else 2
		_phase_set("release_one", {"pid": release_pid})
		var released: bool = await _wait_until(func() -> bool:
			var o: Dictionary = _a1_stage.get("grab_owner") as Dictionary
			return not o.has(release_pid) and o.size() == expected_players - 1, 40.0)
		check(released, "pid%d release cleared only its own grab" % release_pid)
		_phase_set("release_all")
		await _tape_interact_a1()
		check(await _wait_until(func() -> bool:
			return (_a1_stage.get("grab_owner") as Dictionary).is_empty(), 40.0), "all grabs released cleanly")
		_phase_set("done_grab")
	else:
		var grab_ok := false
		if await _wait_phase("grab", 200.0):
			grab_ok = await _grab_own_rail_a1()
			await _wait_real(0.6)
			var anchor: Variant = player.get("grab_anchor")
			var got := str((anchor as Object).get("interaction_id")) if anchor != null and is_instance_valid(anchor) else ""
			_write_json_ev("mp_a1_grab_%d.json" % me, {"pid": me, "grabbing": bool(player.get("grabbing")),
				"rail": got, "ok": grab_ok and bool(player.get("grabbing"))})
			check(grab_ok, "pid%d grabbed its own rail %s over the real grant path" % [me, _rail_for_pid(me)])
			var was_release_target := false
			if await _wait_phase("release_one", 150.0):
				var rel: Dictionary = _read_json_ev(MP_PHASE)
				was_release_target = int(rel.get("pid", 0)) == me
				if was_release_target:
					await _tape_interact_a1()
					await _wait_real(0.8)
					check(not bool(player.get("grabbing")), "pid%d released its own grip via E" % me)
					await _a1_walk(Vector3(1.65, 3.42, -19.6), 3.5, "pid%d step off the rail" % me)
				else:
					await _wait_real(0.8)
					check(bool(player.get("grabbing")), "pid%d still holds while another releases" % me)
			if await _wait_phase("release_all", 150.0):
				if not was_release_target:
					await _tape_interact_a1()
					await _wait_real(0.8)
				check(not bool(player.get("grabbing")), "pid%d released after release_all" % me)
			await _wait_phase("done_grab", 150.0)
		else:
			check(false, "pid%d reached the grab phase" % me)

	# --- 5. departure chain ------------------------------------------------
	await _wait(1.3 * float(me - 1))
	check(not bool(player.get("downed")), "pid%d is upright after the grab matrix" % me)
	await _a1n_walk_down_from_catwalk()
	await _a1_walk(Vector3(8.0, 0, -16.5), 4.0, "east aisle north")
	await _a1_walk(Vector3(8.0, 0, -33.0), 6.0, "east aisle south")
	await _a1_walk(Vector3(0, 0, -35.6), 3.5, "hall center")
	await _a1_walk(Vector3(0, 0, -37.6), 2.5, "station threshold")

	if me == 2:
		await _a1_walk(Vector3(-5.6, 0, -40.5), 3.5, "station west")
		await _a1_walk(Vector3(-5.6, 0, -44.3), 4.0, "chock approach")
		await _a1_walk(Vector3(-5.62, 0, -45.5), 1.8, "chock")
		check(await _a1n_press_until("chock", "chock_removed", 6, 1.2),
			"pid2 removed the wheel chock (departure credit owner)")
	elif me == 3:
		await _a1_walk(Vector3(0, 0, -38.2), 2.0, "station center")
		await _a1_walk(Vector3(7.2, 0, -38.2), 4.0, "ramp north")
		await _a1_walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _a1n_wait_flag("chock_removed", 200.0)
		await _a1_walk(Vector3(7.35, 1.55, -48.2), 3.5, "platform brake")
		await _a1_walk(Vector3(6.55, 1.55, -48.6), 1.6, "brake")
		check(await _a1n_press_until("parking_brake", "brake_released", 6, 1.2),
			"pid3 released the parking brake (departure credit owner)")
	elif me == 4:
		await _a1_walk(Vector3(7.2, 0, -38.2), 3.5, "ramp north")
		await _a1_walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _a1_walk(Vector3(7.35, 1.55, -43.9), 2.5, "platform cargo")
		await _a1n_wait_flag("brake_released", 200.0)
		await _a1_walk(Vector3(6.55, 1.55, -43.0), 1.8, "cargo strap")
		check(await _a1n_press_until("cargo", "cargo_secured", 6, 1.2),
			"pid4 locked the cargo restraint (departure credit owner)")
	elif me == 1 and expected_players == 2:
		await _a1_walk(Vector3(7.2, 0, -38.2), 4.0, "ramp north")
		await _a1_walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _a1n_wait_flag("chock_removed", 200.0)
		await _a1_walk(Vector3(7.35, 1.55, -48.2), 3.5, "platform brake")
		await _a1_walk(Vector3(6.55, 1.55, -48.6), 1.6, "brake")
		check(await _a1n_press_until("parking_brake", "brake_released", 6, 1.2),
			"host released the parking brake (2-player departure owner)")
		await _a1_walk(Vector3(6.55, 1.55, -43.0), 4.0, "cargo strap")
		check(await _a1n_press_until("cargo", "cargo_secured", 6, 1.2),
			"host locked the cargo restraint (2-player departure owner)")
	elif me == 1 and expected_players == 3:
		await _a1_walk(Vector3(7.2, 0, -38.2), 4.0, "ramp north")
		await _a1_walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _a1n_wait_flag("brake_released", 200.0)
		await _a1_walk(Vector3(7.35, 1.55, -43.9), 3.0, "platform cargo")
		await _a1_walk(Vector3(6.55, 1.55, -43.0), 1.8, "cargo strap")
		check(await _a1n_press_until("cargo", "cargo_secured", 6, 1.2),
			"host covered cargo in the 3-player topology")

	check(await _wait_until(func() -> bool:
		return _a1n_flag("chock_removed") and _a1n_flag("brake_released") and _a1n_flag("cargo_secured"), 260.0),
		"departure chain chock/brake/cargo completed over the network")

	# --- board the cart ----------------------------------------------------
	if me == 1 and expected_players >= 4:
		await _wait(4.0)
		await _a1_walk(Vector3(7.2, 0, -38.2), 3.5, "ramp north")
		await _a1_walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _a1_walk(Vector3(6.2, 1.55, -45.5), 2.4, "platform lane")
		await _a1_walk(Vector3(5.6, 1.55, -47.0), 2.2, "platform edge")
	elif me == 2:
		await _a1_walk(Vector3(-4.5, 0, -40.6), 3.0, "station return")
		await _a1_walk(Vector3(0.0, 0, -38.2), 2.4, "station center")
		await _a1_walk(Vector3(7.2, 0, -38.2), 4.0, "ramp north")
		await _a1_walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _a1_walk(Vector3(7.35, 1.55, -47.0), 3.2, "platform edge")
	else:
		await _a1_walk(Vector3(5.6, 1.55, -47.0), 6.0, "platform edge")
	await _a1_walk(Vector3(3.6, 1.55, -47.0), 2.5, "cart side")
	await _a1_walk(Vector3(0.0, 1.55, -48.0), 3.0, "cart deck")
	if me == 1:
		await _a1_walk(Vector3(-3.0, 1.55, -50.0), 2.5, "launch console")
	check(await _wait_until(func() -> bool: return bool(_a1_stage.call("all_active_aboard")), 200.0),
		"all %d bodies are physically inside the cart" % expected_players)
	check(await _wait_until(func() -> bool: return bool(_a1_stage.call("all_active_ready")), 200.0),
		"every active player earned >=2 distinct phases")
	var counts: Array = []
	for pid in (_a1_stage.get("active_pids") as Dictionary).keys():
		counts.append("%d:%d" % [int(pid), _a1n_phase_count(int(pid))])
	note("Act01 phase counts %s" % str(counts))
	_write_json_ev("mp_a1_prelaunch_%d.json" % me, _a1n_snapshot())
	if role == "host":
		_phase_set("launch")
	else:
		if not await _wait_phase("launch", 200.0):
			check(false, "client reached the launch gate")
			return false

	# --- launch + hand-off -------------------------------------------------
	if me == 1:
		check(await _a1n_press_until("launch_cart", "departure_started", 5, 1.2),
			"host pressed the launch interlock")
	check(await _a1n_wait_flag("departure_started", 150.0), "departure interlock accepted for the whole crew")
	await _wait_real(0.2)
	# attribution table (same as the proven 3/4-seat Act01 run)
	var expected_kinds: Dictionary = {}
	match expected_players:
		2:
			expected_kinds = {1: ["power_dock", "power_clamp", "fan_start", "damper", "brake", "cargo", "launch"],
				2: ["entry_shove", "entry_latch", "fan_lock", "fan_coupling", "governor", "chock"]}
		3:
			expected_kinds = {1: ["power_dock", "fan_start", "damper", "launch"],
				2: ["entry_shove", "entry_latch", "governor", "chock"],
				3: ["power_clamp", "fan_lock", "fan_coupling", "brake"]}
		4:
			expected_kinds = {1: ["power_dock", "fan_start", "damper", "launch"],
				2: ["entry_shove", "entry_latch", "chock"],
				3: ["power_clamp", "fan_lock", "fan_coupling", "brake"],
				4: ["governor", "cargo"]}
	participation["act01"] = {}
	for p in range(1, expected_players + 1):
		var mine: Array = _a1n_credit_kinds(p)
		participation["act01"][p] = {"kinds": mine, "phases": _a1_credit_phases(p)}
		for kind in expected_kinds.get(p, []):
			check(mine.has(str(kind)), "pid %d earned credit %s (has %s)" % [p, kind, str(mine)])
	if role == "host":
		var exclusive := {"entry_shove": 2, "entry_latch": 2,
			"power_clamp": 1 if expected_players == 2 else 3,
			"chock": 2,
			"brake": 1 if expected_players == 2 else 3,
			"cargo": 1 if expected_players == 2 else (4 if expected_players == 4 else 1)}
		var leak: Array = []
		for kind in exclusive.keys():
			var owner_pid := int(exclusive[kind])
			if owner_pid > expected_players: continue
			for p in range(1, expected_players + 1):
				if p == owner_pid:
					check(_a1n_credit_kinds(p).has(kind), "exclusive credit %s is on its owner pid %d" % [kind, p])
				elif _a1n_credit_kinds(p).has(kind):
					leak.append("%s->pid%d" % [kind, p])
		check(leak.is_empty(), "no exclusive Act01 credit leaked to another seat (%s)" % str(leak))

	check(await _wait_until(func() -> bool:
		if _a1_stage == null or not is_instance_valid(_a1_stage) or current_scene != _a1_stage:
			return true
		var b: Variant = _a1_stage.get("builder")
		if b == null or not is_instance_valid(b): return true
		var cart: Node = (b as Object).get("mine_cart") as Node
		if cart == null or not is_instance_valid(cart): return true
		return cart.global_position.z < -50.0, 150.0), "the mine cart physically travelled down the rails")
	check(await _wait_until(func() -> bool:
		if player == null or not is_instance_valid(player): return true
		return bool(player.get("external_hold")), 30.0), "pid%d received the real ride grant" % me)
	await _wait_real(1.0)
	var hand: bool = await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == "Act23Chapter", 400.0)
	check(hand, "Act01 handed off to Act23 in the same session (scene=%s)" % _scene_now())
	if hand:
		handoffs.append({"from": "act01", "to": "act23", "pid": me,
			"scene": _scene_now(), "t": float(Time.get_ticks_msec() - run_started_ms) / 1000.0})
		_write_json_ev("mp_handoff_act01_%d.json" % me, {"pid": me, "scene": _scene_now(),
			"current_chapter": str(hub.get("current_chapter"))})
	return hand

func _grab_own_rail_a1() -> bool:
	var rid: String = _rail_for_pid(me)
	for attempt in range(4):
		if bool(player.get("grabbing")): return true
		if await _a1_press(rid, 0.14):
			await _wait_real(0.8)
			if bool(player.get("grabbing")):
				var anchor: Variant = player.get("grab_anchor")
				var got := str((anchor as Object).get("interaction_id")) if anchor != null and is_instance_valid(anchor) else ""
				check(got == rid, "pid %d grabbed its own rail %s (got=%s)" % [me, rid, got])
				return got == rid
		await _a1_walk(Vector3(1.85, 3.42, _rail_z(me)), 1.4, "rail approach %d" % attempt)
	return false

func _tape_interact_a1() -> void:
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	await _wait_real(0.6)

func _a1n_snapshot() -> Dictionary:
	var out: Dictionary = {"pid": me, "t": float(Time.get_ticks_msec() - run_started_ms) / 1000.0}
	if not _a1_ok(): return out
	out["flags"] = (_a1_stage.get("flags") as Dictionary).duplicate(true)
	var credits: Dictionary = _a1_stage.get("credits") as Dictionary
	var creds: Dictionary = {}
	for pid in credits.keys():
		var rec: Dictionary = credits[pid] as Dictionary
		creds[int(pid)] = {"kinds": (rec.get("kinds", {}) as Dictionary).keys(),
			"phases": (rec.get("phases", {}) as Dictionary).duplicate(true)}
	out["credits"] = creds
	out["active_pids"] = (_a1_stage.get("active_pids") as Dictionary).keys()
	out["remotes"] = (_a1_stage.get("remotes") as Dictionary).keys()
	out["local_pos"] = [player.global_position.x, player.global_position.y, player.global_position.z]
	return out

# ===========================================================================
# ACT 23 - mine cart chapter with all seats riding and real repair work
# ===========================================================================
func _a23_actor(pid: int) -> Node:
	if _a23 == null or not is_instance_valid(_a23): return null
	var actors: Variant = _a23.get("actors")
	if not (actors is Dictionary): return null
	return (actors as Dictionary).get(pid) as Node

func _a23_any_actor_cleared(pid: int) -> bool:
	return _a23_actor_cleared(_a23_actor(pid))

func _a23_all_on_deck() -> bool:
	if _a23 == null or not is_instance_valid(_a23): return false
	var actors: Variant = _a23.get("actors")
	if not (actors is Dictionary): return false
	var n := 0
	for pid in (actors as Dictionary).keys():
		if _a23_actor_on_deck((actors as Dictionary)[pid]): n += 1
	return n >= expected_players

func _a23_wait_all_on_deck(timeout_s: float) -> bool:
	return await _wait_until(func() -> bool: return _a23_all_on_deck(), timeout_s)

func _a23_rig() -> Node:
	if _a23_yard == null or not is_instance_valid(_a23_yard): return null
	return _a23_yard.get("rig") as Node

func _a23_alignment() -> Dictionary:
	var rig: Node = _a23_rig()
	if rig == null: return {}
	return rig.call("alignment_state") as Dictionary

func _a23_workstation(kind: String) -> Vector3:
	if _a23_yard == null or not is_instance_valid(_a23_yard): return Vector3.ZERO
	var rows: Array = _a23_yard.call("workstations") as Array
	for row in rows:
		var d: Dictionary = row as Dictionary
		if str(d.get("kind", "")) == kind:
			return d.get("position") as Vector3
	return Vector3.ZERO

func _a23_grip_target(index: int) -> Vector3:
	var grips: Array = _a23.get("grips") as Array
	var local: Vector3 = grips[clampi(index, 0, grips.size() - 1)] as Vector3
	return _a23_cart.to_global(local)

func _a23_grab_rail(index: int) -> bool:
	if int(player.get("grip_id")) >= 0:
		return true
	var grips: Array = _a23.get("grips") as Array
	var local: Vector3 = grips[clampi(index, 0, grips.size() - 1)] as Vector3
	# The bar moves with the cart: re-aim every step instead of chasing one
	# frozen world coordinate.
	for attempt in range(50):
		if int(player.get("grip_id")) >= 0:
			return true
		var target: Vector3 = _a23_cart.to_global(local)
		var p: Vector3 = player.global_position
		var flat: float = Vector2(p.x - target.x, p.z - target.z).length()
		_a23_face(target)
		if flat < 0.90:
			await _a23_press("repair", 0.14)
			await _wait(0.2)
			if int(player.get("grip_id")) >= 0:
				log_line("A23_GRIP pid=%d grip=%d flat=%.2f" % [me, int(player.get("grip_id")), flat])
				return true
		Input.action_press("move_up")
		await physics_frame
		await physics_frame
		Input.action_release("move_up")
		await _wait(0.05)
	return int(player.get("grip_id")) >= 0

func _a23_board_n() -> bool:
	if _a23_on_deck():
		return true
	# Clients 2/3 were observed spawning on the south apron (below the 0.38 m
	# boarding pad) instead of the authored SPAWN_POINT. A real player climbs the
	# pad lip with a jump; no teleport is used.
	if _in_tree(player) and player.global_position.y < 0.30 and player.global_position.z < -2.30:
		await _a23_walk(_a23_global(Vector3(1.0, 0.0, -2.55)), 6.0, "pad south lip", 0.5, false, true)
		_a23_face(_a23_global(Vector3(1.0, 1.95, 0.6)))
		Input.action_press("move_up")
		await _wait(0.15)
		Input.action_press("jump")
		await _wait(0.12)
		Input.action_release("jump")
		await _wait(0.9)
		Input.action_release("move_up")
		await _wait(0.4)
		log_line("A23_PAD_JUMP pos=%s" % str(player.global_position))
	return await _a23_board()
	var boarded: bool = await _a23_board()
	if boarded: return true
	# Last resort: the production safety-rope rescue (R) for a body the shared
	# spawn ejected below the platform. Logged as a workaround, never silent.
	await _a23_press("cart_recover", 0.14)
	await _wait(1.0)
	log_line("A23_RESCUE_ABOARD pid=%d ok=%s pos=%s" % [me, str(_a23_on_deck()), str(player.global_position)])
	return _a23_on_deck()


## Act23 adoption race: a snapshot can arrive before the deferred client seat
## assignment, spawning a remote body for the client's own pid. The renamed
## local body is then overlapped by that orphan (two capsules at SPAWN_POINT),
## which ejects both off the 0.38 m pad. A self avatar is never legal, so the
## harness disables and frees the duplicate before it can push the local body.
func _a23_drop_self_duplicates() -> void:
	# All peers share SPAWN_POINT in Act23; overlapping capsules eject each other off
	# the 0.38 m pad before any input. No Act23 mechanic needs body-vs-body
	# collision, so the harness removes the player layer from the local body.
	# EGRESS-FIX EXPERIMENT: authored collision is kept. The frozen harness
	# cleared mask bit 2 here (dropping every layer-2 static body: cave floor,
	# dock landings, station shell) and never restored it, so the local body fell
	# through the yard whenever it stepped off the cart platform.
	log_line("A23_COLLISION kept layer=%d mask=%d" % [int(player.get("collision_layer")), int(player.get("collision_mask"))])
	if _a23 == null or player == null:
		return
	var removed := 0
	for child in _a23.get_children():
		if child == player:
			continue
		if child is CharacterBody3D and int((child as Object).get("peer_id")) == me:
			(child as CharacterBody3D).set("collision_layer", 0)
			(child as CharacterBody3D).set("collision_mask", 0)
			(child as Node).queue_free()
			removed += 1
	if removed > 0:
		log_line("A23_SELF_DUPLICATE removed=%d me=%d" % [removed, me])

func _drive_act23_n() -> bool:
	_stage_now = "act23"
	_a23 = _find_act23_slice()
	check(_a23 != null, "Act23 moving-cart slice exists")
	if _a23 == null:
		return false
	var waited := 0.0
	while waited < 40.0 and _valid(_a23) and _a23.get("loaded") != true:
		await _wait(0.2); waited += 0.2
	if not _valid(_a23) or not _scene_is("Act23Chapter"):
		check(false, "Act23 scene stayed alive while the slice loaded")
		return false
	_a23_cart = _a23.get("cart") as Node3D
	player = _a23.get("player") as Node
	_a23_flow = _a23.get("flow") as Node
	_a23_yard = _a23.get("yard") as Node3D
	check(player != null and _a23_cart != null and _a23_flow != null and _a23_yard != null,
		"Act23 world nodes present (player/cart/flow/yard)")
	if player == null or _a23_cart == null: return false
	me = int(_a23.get("local_slot"))
	log_line("A23_XFORM me=%d player_local=%s parent=%s stage_local=%s stage_global=%s rot=%.3f coop_slot=%d" % [me, str(player.position), str(player.get_parent().name if player.get_parent() != null else "?"), str(_a23.position), str(_a23.global_position), _a23.rotation.y, int(_a23.get("coop").get("local_slot"))])
	log_line("A23_SPAWN me=%d slot=%d pos=%s cart_pos=%s dist=%.2f" % [me, int(_a23.get("local_slot")), str(player.global_position), str(_a23_cart.global_position), float(_a23_cart.get("distance"))])
	_a23_layer0 = int(player.get("collision_layer"))
	_a23_mask0 = int(player.get("collision_mask"))
	_a23_drop_self_duplicates()
	# All peers share SPAWN_POINT in Act23; overlapping capsules eject each other off
	# the 0.38 m pad before any input. No Act23 mechanic needs body-vs-body
	# collision, so the harness removes the player layer from the local body.
	# EGRESS-FIX EXPERIMENT: authored collision is kept. The frozen harness
	# cleared mask bit 2 here (dropping every layer-2 static body: cave floor,
	# dock landings, station shell) and never restored it, so the local body fell
	# through the yard whenever it stepped off the cart platform.
	log_line("A23_COLLISION kept layer=%d mask=%d" % [int(player.get("collision_layer")), int(player.get("collision_mask"))])
	_write_json_ev("mp_a23_begin_%d.json" % me, _a23_snapshot())
	# Production Act23 gives every peer the same SPAWN_POINT. With two clients
	# the capsules overlap and can be ejected off the 0.38 m pad, so every
	# non-first rider clears the 1.0 m boarding lane immediately.
	if me > 1:
		var hold := Vector3(2.45, 0.4, -2.35)
		if me == 3: hold = Vector3(2.95, 0.4, -2.95)
		if me == 4: hold = Vector3(2.0, 0.4, -3.05)
		await _a23_walk(hold, 4.0, "wait clear of the boarding lane", 0.35, false)
	_assert_identity_uniform("act23", me)
	check(bool(player.get("is_local_actor")), "Act23 local body is the local actor")
	var actors: Variant = _a23.get("actors")
	var actor_keys: Array = (actors as Dictionary).keys() if actors is Dictionary else []
	actor_keys.sort()
	bodymap["act23"] = {"seat": me, "actors": actor_keys,
		"self_peer": int(player.get("peer_id"))}
	check(int(player.get("peer_id")) == me, "Act23 body peer_id == local slot (%d)" % me)
	for pid in range(1, expected_players + 1):
		check((actors as Dictionary).has(pid) if actors is Dictionary else false,
			"Act23 process maps a body for pid %d" % pid)
	_record_stage("act23_begin", _a23_snapshot())

	# --- board sequentially, pid order -------------------------------------
	if me > 1:
		check(await _wait_until(func() -> bool: return _a23_actor_on_deck(_a23_actor(me - 1)), 120.0),
			"pid%d waited for pid%d to clear the boarding stairs" % [me, me - 1])
	if not await _a23_board_n():
		check(false, "pid%d physically boarded the cart deck" % me)
		_write_json_ev("mp_a23_blocked_board_%d.json" % me, _a23_snapshot())
		return false
	check(_a23_on_deck(), "pid%d physically boarded the cart deck" % me)
	await _shot("act23_boarded")
	# each rider clears the 0.9 m stair lane into its own deck spot
	var clear_spot := Vector3(2.48, 1.95, 1.08)
	match me:
		1: clear_spot = Vector3(2.48, 1.95, 1.08)
		2: clear_spot = Vector3(0.8, 1.95, 2.45)
		3: clear_spot = Vector3(0.8, 1.95, 1.0)
		_: clear_spot = Vector3(0.8, 1.95, 2.0)
	await _a23_walk(_a23_global(clear_spot), 5.0, "clear the stair top", 0.5, false)

	# --- host departs only when every body is on the deck -------------------
	if me == 1:
		check(await _a23_wait_all_on_deck(180.0), "host sees all %d riders on the deck" % expected_players)
		await _a23_walk(_a23_global(Vector3(2.48, 1.95, 1.08)), 5.0, "brake controller", 0.45, false)
		for _attempt in range(3):
			if bool(_a23_cart.get("running")): break
			await _a23_press("repair", 0.16)
			await _wait(0.8)
	check(await _wait_until(func() -> bool:
		if not _a23_cart_ok(): return true
		return bool(_a23_cart.get("running")), 150.0), "the cart really started from the deck controller")
	_record_stage("act23_running", _a23_snapshot())
	await _shot("act23_running")

	# --- ride: pid3/pid4 hold the two authored grip bars --------------------
	if me == 3 or me == 4:
		var idx: int = 0 if me == 3 else 1
		await _wait_real(2.5 + 0.8 * me)
		var grip_ok: bool = await _a23_grab_rail(idx)
		if not grip_ok:
			# retry once after the bend starts
			await _wait_real(2.0)
			grip_ok = await _a23_grab_rail(idx)
		check(grip_ok, "pid%d holds grip bar %d through the ride" % [me, idx])

	# --- fault -------------------------------------------------------------
	check(await _wait_until(func() -> bool:
		if not _scene_is("Act23Chapter"): return true
		if not _a23_cart_ok(): return true
		return bool(_a23_cart.get("stopped_for_fault")), 300.0),
		"cart stopped at the severed rail (distance=%.1f)" % float(_safe_get(_a23_cart, "distance", -1.0)))
	_record_stage("act23_fault", _a23_snapshot())
	await _shot("act23_fault")
	if not _a23_cart_ok():
		check(false, "A23_FAULT_STATE scene=%s a23=%s cart=%s" % [_scene_now(), str(_a23), str(_a23_cart)])
		return false

	# release grips and brake (real B input, cart already stopped)
	if int(player.get("grip_id")) >= 0:
		await _a23_press("repair", 0.14)
		await _wait_real(0.4)
	# No second brake press here: re-braking a stopped cart perturbs the narrow
	# deck and was observed to slide the rider off before the gate.
	await _wait_real(0.5)
	log_line("ACT23_BRAKE pid=%d kinds=%s" % [me, str(_a23_participation_kinds(me))])
	# Restore the authored collision before stepping onto the yard: the gate ramp
	# is normal world geometry and must be solid. Exits are sequential, so the
	# narrow-deck crowding that needed the layer removal is already over.
	# Restore the authored player collision after boarding: the gate ramp is
	# normal world geometry and must be solid again for the deck exit.

	# --- exit the deck sequentially: pid2, pid3, pid4, pid1 -----------------
	var exit_order: Array = []
	for p in range(2, expected_players + 1): exit_order.append(p)
	exit_order.append(1)
	var my_pos: int = exit_order.find(me)
	if my_pos > 0:
		var prev: int = int(exit_order[my_pos - 1])
		check(await _wait_until(func() -> bool: return _a23_any_actor_cleared(prev), 150.0),
			"pid%d waited for pid%d to clear the gate" % [me, prev])
	await _a23_exit_deck()
	await _shot("act23_exit_attempt")
	var ppos: Vector3 = player.global_position if _in_tree(player) else Vector3(0.0, -99.0, 0.0)
	var yard_ok: bool = (not _a23_on_deck()) and ppos.y >= 0.15 and ppos.y < 1.0
	if not yard_ok:
		check(false, "A23_DECK_EGRESS pid%d did not land on the maintenance yard (pos=%s on_deck=%s)" % [me, str(ppos), str(_a23_on_deck())])
		_write_json_ev("mp_a23_blocked_egress_%d.json" % me, _a23_snapshot())
		_mark_blocked("act23_deck_egress", "pos=%s on_deck=%s; winch console unreachable" % [str(ppos), str(_a23_on_deck())])
		await _shot("act23_blocked_egress")
		return false
	_record_stage("act23_off_deck", _a23_snapshot())
	await _shot("act23_off_deck")
	_record_stage("act23_off_deck", _a23_snapshot())

	# --- repair ------------------------------------------------------------
	var rig: Node = _a23_rig()
	var winch: Node3D = rig.get("winch") as Node3D if rig != null else null
	var anchor: Node3D = _a23_find_anchor("eye_far")
	check(rig != null and winch != null and anchor != null, "repair rig + front lifting eye exist")
	if rig == null or winch == null or anchor == null: return false
	var anchor_pos: Vector3 = anchor.call("attach_point") as Vector3
	var console_pos: Vector3 = winch.global_position
	var lock_pos: Vector3 = _a23_yard.call("lock_station_position") as Vector3
	var guide_pos: Vector3 = _a23_workstation("guide")
	var bracket_pos: Vector3 = _a23_workstation("bracket")
	var arc: Dictionary = {}
	if me == 2:
		# hook the front eye
		await _a23_walk(Vector3(89.0, 0.0, 0.0), 7.0, "south clear lane", 0.7, false)
		await _a23_walk(Vector3(94.3, 0.0, 0.2), 7.0, "east around the cart nose", 0.7, false)
		await _a23_walk(Vector3(94.3, 0.0, 4.7), 6.0, "east of the swing nose", 0.7, false)
		await _a23_walk(Vector3(96.6, 0.0, 4.5), 5.0, "clear of the guide wheel", 0.7, false)
		await _a23_walk(anchor_pos, 4.0, "front lifting eye", 1.0, false)
		await _a23_press("repair", 0.14)
		await _wait(0.6)
		var tension: Dictionary = rig.call("tension_state") as Dictionary
		check(bool(tension.get("attached", false)), "pid2 hooked the winch cable onto the front lifting eye")
		arc = tension
		if not bool(tension.get("attached", false)):
			_write_json_ev("mp_a23_blocked_hook_%d.json" % me, _a23_snapshot())
			return false
		# take the drum
		await _a23_walk(Vector3(94.2, 0.0, 9.2), 7.0, "north of the line", 0.8, false)
		await _a23_walk(Vector3(88.6, 0.0, 9.2), 6.0, "north apron", 0.8, false)
		await _a23_walk(console_pos, 5.0, "winch console", 1.2, false)
		await _a23_press("repair", 0.14)
		await _wait(0.5)
		check(await _wait_until(func() -> bool: return bool(_a23_flow.get("at_console")), 40.0),
			"pid2 took over the winch drum (console_actor=%d)" % int(_a23_flow.get("console_actor")))
		# haul until the guide/bracket window, then keep hauling
		Input.action_press("winch_haul")
		var haul_t := 0.0
		var angle_open := false
		var align: Dictionary = {}
		while haul_t < 100.0:
			await _wait(0.25); haul_t += 0.25
			align = rig.call("alignment_state") as Dictionary
			if not angle_open and absf(float(align.get("angle_deg", 99.0))) <= 7.5:
				angle_open = true
				_phase_set("repair_workstations", {"angle": float(align.get("angle_deg", 0.0))})
			if bool(align.get("captureable", false)): break
		if not angle_open:
			_phase_set("repair_workstations", {"angle": float(align.get("angle_deg", 99.0))})
		# wait for the real guide/bracket holders before the final capture
		if expected_players >= 3:
			await _wait_phase("guide_ready", 90.0)
		if expected_players >= 4:
			await _wait_phase("bracket_ready", 90.0)
		if expected_players >= 3:
			Input.action_press("winch_haul")
			while haul_t < 130.0:
				await _wait(0.25); haul_t += 0.25
				align = rig.call("alignment_state") as Dictionary
				if bool(align.get("captureable", false)): break
		Input.action_release("winch_haul")
		await _wait(0.4)
		await _a23_press("winch_brake", 0.12)
		align = rig.call("alignment_state") as Dictionary
		log_line("ACT23_ALIGN %s haul=%.2f" % [str(align), haul_t])
		check(bool(align.get("captureable", false)),
			"rail pulled into the guide slot capture band (angle=%.2f)" % float(align.get("angle_deg", 0.0)))
		if not bool(align.get("captureable", false)):
			_write_json_ev("mp_a23_blocked_align_%d.json" % me, _a23_snapshot())
			return false
		# release the bracket holder before the pin
		_phase_set("bracket_release")
		await _wait_phase("bracket_released", 60.0)
		await _a23_press("repair", 0.14)
		await _wait(0.5)
		await _a23_walk(lock_pos, 12.0, "lock station", 1.05, false)
		await _a23_press("repair", 0.14)
		var done_at := 0.0
		while done_at < 30.0 and not bool(_a23_yard.call("completion")):
			await _wait(0.4); done_at += 0.4
		await _shot("act23_repaired")
		_phase_set("pin_installed")
		_write_json_ev("mp_a23_repaired_%d.json" % me, _a23_snapshot())
		if not bool(_a23_yard.call("completion")): return false
	elif me == 3:
		# guide wheel: only after the rail is inside 8 degrees
		check(await _wait_phase("repair_workstations", 240.0), "pid3 saw the rail enter the guide window")
		await _a23_walk(Vector3(94.2, 0.0, -2.5), 9.0, "east staging", 0.7, false)
		await _a23_walk(Vector3(92.0, 0.0, -2.5), 5.0, "guide approach west", 0.6, false)
		await _a23_walk(guide_pos + Vector3(-0.8, 0.0, 0.0), 2.5, "guide stand", 0.5, false)
		_a23_face(guide_pos)
		await _a23_press("repair", 0.14)
		await _wait(0.5)
		check(int(rig.get("guide_holder")) == me, "pid3 holds the guide wheel (holder=%d)" % int(rig.get("guide_holder")))
		_phase_set("guide_ready")
		await _wait_phase("bracket_release", 150.0)
		# keep steering through the pin: releasing early shrinks the capture window
		await _wait_phase("pin_installed", 120.0)
		await _a23_press("repair", 0.14)
		await _wait(0.3)
	elif me == 4:
		check(await _wait_phase("repair_workstations", 240.0), "pid4 saw the rail enter the bracket window")
		await _a23_walk(Vector3(89.0, 0.0, -3.0), 8.0, "south apron", 0.7, false)
		await _a23_walk(bracket_pos + Vector3(-0.7, 0.0, 0.0), 4.0, "bracket stand", 0.5, false)
		_a23_face(bracket_pos)
		await _a23_press("repair", 0.14)
		await _wait(0.5)
		check(int(rig.get("bracket_holder")) == me, "pid4 props the safety bracket (holder=%d)" % int(rig.get("bracket_holder")))
		_phase_set("bracket_ready")
		# wait for the haul to reach the capture band, then fold the prop away
		await _wait_phase("bracket_release", 150.0)
		await _a23_press("repair", 0.14)
		await _wait(0.5)
		check(int(rig.get("bracket_holder")) == 0, "pid4 folded the bracket away before the pin")
		_phase_set("bracket_released")
	else:
		# pid1: after the crew finishes, take a real turn at the console.
		var done_wait := 0.0
		while done_wait < 300.0 and not bool(_a23_yard.call("completion")):
			await _wait(0.5); done_wait += 0.5
		check(bool(_a23_yard.call("completion")), "the broken rail is repaired (route_clear)")
		if bool(_a23_yard.call("completion")):
			await _a23_walk(Vector3(94.3, 0.0, -2.5), 8.0, "host east staging", 0.7, false)
			await _a23_walk(Vector3(94.3, 0.0, 4.7), 7.0, "host east of nose", 0.8, false)
			await _a23_walk(Vector3(94.2, 0.0, 9.2), 6.0, "host north apron", 0.8, false)
			await _a23_walk(Vector3(88.6, 0.0, 9.2), 6.0, "host north apron west", 0.8, false)
			await _a23_walk(console_pos, 5.0, "winch console (host)", 1.2, false)
			await _a23_press("repair", 0.14)
			await _wait(0.6)
			log_line("ACT23_HOST_CONSOLE at=%s actor=%d" % [
				str(_a23_flow.get("at_console")), int(_a23_flow.get("console_actor"))])
			await _a23_press("repair", 0.14)
			await _wait(0.4)
	if not (await _wait_until(func() -> bool: return bool(_a23_yard.call("completion")), 240.0)):
		_write_json_ev("mp_a23_blocked_repair_%d.json" % me, _a23_snapshot())
		return false

	# --- reboard sequentially (pid2 -> pid3 -> pid4 -> pid1) ----------------
	var reorder: Array = []
	for p in range(2, expected_players + 1): reorder.append(p)
	reorder.append(1)
	var rpos: int = reorder.find(me)
	if rpos > 0:
		var prev2: int = int(reorder[rpos - 1])
		check(await _wait_until(func() -> bool: return _a23_actor_on_deck(_a23_actor(prev2)), 150.0),
			"pid%d waited for pid%d to re-board" % [me, prev2])
	# try the production rescue first (real R while stopped), then stairs
	if not _a23_on_deck():
		await _a23_press("cart_recover", 0.14)
		await _wait(1.0)
	if not _a23_on_deck():
		await _a23_board_n()
	check(_a23_on_deck(), "pid%d is back on the deck for the re-ride" % me)
	if not _a23_on_deck():
		_write_json_ev("mp_a23_blocked_reboard_%d.json" % me, _a23_snapshot())
		return false
	if me < expected_players:
		var re_spot := Vector3(0.8, 1.95, 1.6)
		if me == 1: re_spot = Vector3(2.48, 1.95, 1.08)
		await _a23_walk(_a23_global(re_spot), 5.0, "clear stair top", 0.5, false)
	_write_json_ev("mp_a23_reboarded_%d.json" % me, _a23_snapshot())

	# --- host restarts only when everyone is aboard ------------------------
	if me == 1:
		check(await _a23_wait_all_on_deck(180.0), "host sees all %d riders back on the deck" % expected_players)
		await _a23_walk(_a23_global(Vector3(2.48, 1.95, 1.08)), 5.0, "restart controller", 0.45, false)
		for _attempt in range(4):
			if str(_a23_flow.get("phase")) == "done": break
			if bool(_a23_cart.get("running")) and float(_a23_cart.get("speed")) > 0.2: break
			await _a23_press("repair", 0.16)
			await _wait(1.0)
	check(await _wait_until(func() -> bool:
		return str(_a23_flow.get("phase")) == "done" or (not _scene_is("Act23Chapter")), 300.0),
		"cart reached the crystal-mine dock (phase=done)")
	# participation summary from the authoritative side (clients mirror it)
	participation["act23"] = _a23_participation_summary()
	if role == "host":
		var summary: Dictionary = participation["act23"]
		var credited: Array = summary.get("credited", [])
		var connected: Array = summary.get("connected", [])
		check(credited.size() == connected.size() and connected.size() >= expected_players,
			"every connected Act23 slot did credited work (credited=%s connected=%s)" % [str(credited), str(connected)])
		for pid in range(1, expected_players + 1):
			var kinds: Array = _a23_participation_kinds(pid)
			check(kinds.size() >= 2, "pid%d did >=2 kinds of Act23 work (%s)" % [pid, str(kinds)])
	if not await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == "Act4", 300.0):
		check(false, "Act23 handed off to Act04 (scene=%s)" % _scene_now())
		_write_json_ev("mp_a23_blocked_handoff_%d.json" % me, _a23_snapshot())
		return false
	check(true, "Act23 handed off to Act04 in the same session (scene=%s)" % _scene_now())
	handoffs.append({"from": "act23", "to": "act04", "pid": me,
		"scene": _scene_now(), "t": float(Time.get_ticks_msec() - run_started_ms) / 1000.0})
	_write_json_ev("mp_handoff_act23_%d.json" % me, {"pid": me, "scene": _scene_now(),
		"cart_distance": float(_safe_get(_a23_cart, "distance", -1.0)),
		"participation": participation["act23"]})
	return true

func _a23_participation_summary() -> Dictionary:
	if _a23 == null or not is_instance_valid(_a23): return {}
	var p: Variant = _a23.get("participation")
	if p == null: return {}
	return (p as Object).call("summary") as Dictionary

func _a23_participation_kinds(pid: int) -> Array:
	var summary: Dictionary = participation.get("act23", {}) as Dictionary
	if summary.is_empty(): summary = _a23_participation_summary()
	var recs: Dictionary = summary.get("records", {}) as Dictionary
	var rec: Variant = recs.get(pid, recs.get(str(pid)))
	if rec is Dictionary:
		return ((rec as Dictionary).get("kinds", {}) as Dictionary).keys()
	return []

func _a23_snapshot() -> Dictionary:
	var out: Dictionary = {"pid": me, "t": float(Time.get_ticks_msec() - run_started_ms) / 1000.0}
	if _a23 == null or not is_instance_valid(_a23): return out
	if _a23_cart != null and is_instance_valid(_a23_cart):
		out["distance"] = float(_a23_cart.get("distance"))
		out["speed"] = float(_a23_cart.get("speed"))
		out["running"] = bool(_a23_cart.get("running"))
		out["stopped_for_fault"] = bool(_a23_cart.get("stopped_for_fault"))
		out["arrived"] = bool(_a23_cart.get("arrived"))
	if _a23_flow != null and is_instance_valid(_a23_flow):
		out["phase"] = str(_a23_flow.get("phase"))
		out["console_actor"] = int(_a23_flow.get("console_actor"))
	if _a23_yard != null and is_instance_valid(_a23_yard):
		out["repaired"] = bool(_a23_yard.call("completion"))
	out["on_deck"] = _a23_on_deck()
	out["participation"] = _a23_participation_summary()
	out["grip"] = int(player.get("grip_id")) if player != null and is_instance_valid(player) else -1
	out["pos"] = str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))) if player != null and is_instance_valid(player) else "off"
	return out

# ===========================================================================
# ACT 04 - every seat rings the bell; pid1 restores the chain
# ===========================================================================
func _a4n_ledger_ready04(pid: int) -> bool:
	return _has_credit(pid, "act4_hammer_strike")

func _a4n_wait_all_ready04(timeout_s: float) -> bool:
	return await _wait_until(func() -> bool:
		for p in range(1, expected_players + 1):
			if not _a4n_ledger_ready04(p): return false
		return true, timeout_s)

func _a4n_hold_spot(my_pid: int) -> Vector3:
	# Keep every striker clear of the console approach lane.
	match my_pid:
		1: return Vector3(-4.0, 0.0, 5.0)
		2: return Vector3(4.5, 0.0, 4.0)
		3: return Vector3(6.0, 0.0, 6.5)
		4: return Vector3(2.0, 0.0, 8.5)
	return Vector3(4.5, 0.0, 4.0)

func _drive_act04_n() -> bool:
	_stage_now = "act04"
	_a4 = current_scene
	check(await _wait_until(func() -> bool:
		return _valid(_a4) and _a4.get("player") != null and _a4.get("hammer") != null and _a4.get("cradles") is Dictionary, 60.0),
		"Act04 player, hammer rig and cradles became ready")
	if not _valid(_a4): return false
	player = _a4.get("player") as Node
	me = _local_pid()
	_assert_identity_uniform("act04", me)
	await _wait(1.0)
	_record_stage("act04_begin", _a4_snapshot())
	log_line("ACT04_START pid=%d pos=%s mode=%s" % [me, str(player.global_position), str(_a4.get("coop_mode"))])

	# --- body map truth for this act ---------------------------------------
	var coop_players: Dictionary = _a4.get("coop_players") as Dictionary
	var cp_keys: Array = coop_players.keys()
	cp_keys.sort()
	bodymap["act04"] = {"seat": me, "coop_players": cp_keys}
	if cp_keys.size() < expected_players:
		warn("ACT04_BODYMAP pid%d sees %d/%d bodies (keys=%s) — Act04 co-op only binds host+one client" % [
			me, cp_keys.size(), expected_players, str(cp_keys)])
		bodymap["act04_ok"] = false
	else:
		bodymap["act04_ok"] = true
		check(true, "Act04 maps all %d bodies on pid%d (keys=%s)" % [expected_players, me, str(cp_keys)])

	# --- sequential bell strikes, pid order --------------------------------
	if me == 1:
		check(await _a4_strike(), "pid1 struck the resonance bell with real E/W input")
		_phase_set("strike_2")
		check(await _a4n_wait_all_ready04(120.0), "host saw every seat's real phase-04 credit")
		if not _a4n_ledger_ready04(1):
			_write_json_ev("mp_a4_blocked_strike1.json", _a4_snapshot())
			return false
		await _a4_walk(_a4n_hold_spot(1), 20.0, "host wait west of the console", 1.2)
	else:
		if not await _wait_phase("strike_%d" % me, 200.0):
			check(false, "pid%d got its bell-strike turn" % me)
			return false
		check(await _a4_strike(), "pid%d struck the resonance bell with real E/W input" % me)
		check(_a4n_ledger_ready04(me), "pid%d has its own phase-04 credit" % me)
		await _a4_walk(_a4n_hold_spot(me), 22.0, "pid%d wait clear of the console" % me, 1.4)
		if me < expected_players:
			_phase_set("strike_%d" % (me + 1))
		else:
			_phase_set("all_struck")

	# --- host restores the crystal chain -----------------------------------
	if me == 1:
		var mem1: bool = await _a4_wait_memory(1, 120.0)
		check(mem1, "memory one reached by the resonance wave")
		_record_stage("act04_memory1", _a4_snapshot())
		var crystal_a: Node3D = _a4.get("crystal_a") as Node3D
		await _a4_walk(Vector3(-6.0, 0.0, 2.0), 12.0, "west aisle", 1.0)
		await _a4_walk(Vector3(-6.0, 0.0, 9.5), 9.0, "north of the stope", 1.2)
		await _a4_walk(Vector3(-12.0, 0.0, 9.5), 10.0, "north rim west", 1.2)
		await _a4_walk(Vector3(-17.0, 0.0, 9.5), 8.0, "north west rim", 1.2)
		await _a4_walk(Vector3(-17.5, 0.0, 5.0), 9.0, "alcove west aisle", 1.2)
		await _a4_walk(Vector3(-17.0, 0.0, 3.0), 7.0, "alcove shelf", 1.2)
		var picked := false
		for _attempt in range(4):
			await _a4_pickup(crystal_a.global_position + Vector3(0, 0.2, 0))
			if player.get("carrying") != null: picked = true; break
			await _a4_walk(crystal_a.global_position + Vector3(0, 0, 0.9), 3.0, "closer to the crystal", 0.6)
		check(picked, "cyan crystal picked up from the alcove shelf with real F")
		if not picked:
			_write_json_ev("mp_a4_blocked_pickup.json", _a4_snapshot())
			return false
		await _a4_walk(Vector3(-16.5, 0.0, -2.0), 13.0, "carry south along the west wall", 1.2)
		await _a4_walk(Vector3(-16.8, 0.0, -9.0), 12.0, "carry south", 1.2)
		await _a4_walk(Vector3(-13.0, 0.0, -11.5), 11.0, "toward west relay", 1.2)
		var b1: Node3D = (_a4.get("cradles") as Dictionary)["b1"] as Node3D
		await _a4_walk(b1.global_position + Vector3(0, 0, 1.25), 9.0, "west relay B1", 0.8)
		check(await _a4_place("b1"), "cyan crystal seated and aligned in the west relay B1")
		_record_stage("act04_b1", _a4_snapshot())
		check(await _a4_strike(), "second hammer strike")
		check(await _a4_wait_memory(2, 120.0), "memory two reached after the west path was restored")
		var crystal_b: Node3D = _a4.get("crystal_b") as Node3D
		await _a4_walk(crystal_b.global_position + Vector3(0, 0, 1.1), 12.0, "violet crystal", 0.9)
		var picked_b := false
		for _attempt in range(3):
			await _a4_pickup(crystal_b.global_position)
			if player.get("carrying") != null: picked_b = true; break
		check(picked_b, "violet crystal picked up with real F")
		if not picked_b: return false
		await _a4_walk(Vector3(-18.5, 0.0, -13.2), 12.0, "west ramp foot", 1.2)
		await _a4_walk(Vector3(-17.2, 3.4, -17.6), 12.0, "west ramp up", 1.2)
		await _a4_walk(Vector3(-14.0, 3.4, -19.2), 10.0, "observation ledge", 1.2)
		var b3: Node3D = (_a4.get("cradles") as Dictionary)["b3"] as Node3D
		await _a4_walk(b3.global_position + Vector3(0, 0, 1.15), 9.0, "ledge relay B3", 0.9)
		check(await _a4_place("b3"), "violet crystal seated and aligned on the observation ledge B3")
		check(await _a4_strike(), "third hammer strike")
	else:
		# hold clear; the clients already produced the real phase-04 credit
		await _wait_phase("all_struck", 240.0)
		note("pid%d holds east while pid1 restores the relay chain" % me)
		await _a4_walk(_a4n_hold_spot(me), 8.0, "pid%d hold" % me, 1.2)

	var mem3: bool = await _a4_wait_memory(3, 240.0)
	check(mem3, "memory three reached through the restored final chain")
	check(await _wait_until(func() -> bool:
		var gate: Node = _a4.get("gate")
		return gate != null and bool(gate.get("is_open")), 90.0), "exit gate physically opened")
	_record_stage("act04_gate", _a4_snapshot())
	_write_json_ev("mp_a4_gate_%d.json" % me, _a4_snapshot())
	await _shot("act04_gate")
	participation["act04"] = _ledger_view()
	if role == "host":
		for p in range(1, expected_players + 1):
			check(_a4n_ledger_ready04(p), "phase-04 gate: pid%d has a real Act04 credit" % p)

	# --- walk into the exit, host settles --------------------------------
	_phase_set("exit")
	if me == 1:
		check(await _wait_until(func() -> bool:
			for p in range(2, expected_players + 1):
				var rp: Variant = (_a4.get("coop_players") as Dictionary).get(p)
				if rp != null and is_instance_valid(rp) and (rp as Node3D).global_position.z < -24.0:
					return true
			return expected_players == 1, 120.0), "host waited for at least one client at the exit")
	else:
		await _wait_phase("exit", 200.0)
	# clients take the east route; the host starts from the ledge in the loop below
	if me != 1:
		await _a4_walk(Vector3(4.5, 0.0, -6.0), 10.0, "pid%d east side south" % me, 0.9)
		await _a4_walk(Vector3(0.0, 0.0, -14.0), 9.0, "pid%d final west aisle" % me, 1.0)
		await _a4_walk(Vector3(0.0, 0.0, -21.0), 9.0, "pid%d final chamber aisle" % me, 1.2)
		await _a4_walk(Vector3(6.2, 0.0, -25.0), 11.0, "pid%d exit corridor" % me, 0.7)
	if me != 1:
		check(await _wait_until(func() -> bool:
			return current_scene != null and str(current_scene.name) == "Main", 200.0),
			"pid%d followed the host's reliable Act04 -> Act05 switch" % me)
	else:
		var completed := false
		for attempt in range(4):
			if _scene_is("Main"): completed = true; break
			await _a4_walk(Vector3(0.0, 0.0, -21.0), 10.0, "final chamber aisle %d" % attempt, 1.2)
			await _a4_walk(Vector3(6.2, 0.0, -25.0), 10.0, "exit corridor %d" % attempt, 1.3)
			completed = await _wait_until(func() -> bool:
				return _scene_is("Main") or (_valid(_a4) and bool(_a4.get("completed"))), 25.0)
			if completed: break
			await _a4_walk(Vector3(0.0, 0.0, -19.0), 9.0, "step back out of the exit", 1.2)
			await _wait(3.0)
		check(completed, "pid1 completed Act04 by walking into the exit trigger")
		check(await _wait_until(func() -> bool: return _scene_is("Main"), 300.0),
			"pid1 entered Act05 in the same session")
	check(current_scene != null and str(current_scene.name) == "Main",
		"Act04 handed off to Act05 in the same session (scene=%s)" % _scene_now())
	handoffs.append({"from": "act04", "to": "act05", "pid": me,
		"scene": _scene_now(), "t": float(Time.get_ticks_msec() - run_started_ms) / 1000.0})
	_write_json_ev("mp_handoff_act04_%d.json" % me, {"pid": me, "scene": _scene_now(),
		"chapter": str(hub.get("current_chapter"))})
	return current_scene != null and str(current_scene.name) == "Main"

# ===========================================================================
# ACT 05 - four real jobs, real surge warning, real exit
# ===========================================================================
func _a5n_b(pid: int) -> bool:
	return _has_credit(pid, "surge_response")

func _a5n_a(pid: int) -> bool:
	return _has_credit(pid, "stabilizer_lock") or _has_credit(pid, "counterweight_effect")

func _a5n_c(pid: int) -> bool:
	return _has_credit(pid, "lock_assist") or _has_credit(pid, "damper_latch") \
		or _has_credit(pid, "damper_hold") or _has_credit(pid, "isolation_pin") \
		or _has_credit(pid, "carriage_push") or _has_credit(pid, "data_take")

func _a5n_surge() -> Node:
	return _a5.get("surge") as Node if _valid(_a5) else null

func _a5n_warning() -> bool:
	var s: Node = _a5n_surge()
	return s != null and (str(s.get("state")) == "warning" or float(s.get("warning_left")) > 0.4)

func _a5n_climb_up() -> bool:
	# real E + W on the maintenance ladder (base flow's proven sequence)
	await _a5_travel(_v5(-7.55, 0.0, 0.65), 10.0, 0.9, "ladder stand")
	_a5_face(_v5(-7.55, 1.3, -1.45))
	await _wait(0.35)
	await _a5_press()
	if not (bool(player.get("operating")) and bool(player.get("external_hold"))):
		return false
	Input.action_press("move_forward")
	var t := 0.0
	while t < 12.0 and bool(player.get("external_hold")):
		await _wait(0.2); t += 0.2
	Input.action_release("move_forward")
	await _wait(0.6)
	return player.global_position.y > 3.0

func _a5n_grab_rail(index: int) -> bool:
	var cat: Node = _a5_level().get("catwalk") if _a5_level() != null else null
	if cat == null:
		return false
	var points: Array = cat.get("grab_points") as Array
	if index >= points.size():
		return false
	var gp: Node3D = points[index] as Node3D
	var deck: Node3D = cat.get("deck") as Node3D
	# stand on the deck 0.9 m inboard of the bar (z is the inboard direction)
	var stand: Vector3 = gp.global_position + Vector3(0, -1.06, -0.85)
	await _a5_travel(stand, 10.0, 0.75, "rail %d stand" % index)
	_a5_face(gp.global_position)
	await _wait(0.25)
	await _a5_press()
	await _wait(0.35)
	return bool(player.get("grabbing"))

func _drive_act05_n() -> bool:
	_stage_now = "act05"
	_a5 = current_scene
	check(_scene_is("Main"), "Act05 world is the Main scene")
	if not _scene_is("Main"): return false
	check(await _wait_until(func() -> bool:
		return _valid(_a5) and _a5.get("player") != null and _a5.get("level") != null and _a5.get("story") != null, 90.0),
		"Act05 world/player/story became ready after the hand-off")
	if not _valid(_a5): return false
	player = _a5.get("player") as Node
	me = _local_pid()
	_assert_identity_uniform("act05", me)
	var level: Node = _a5_level()
	var story: Node = _a5_story()
	var session: Node = _a5_session()
	var surge: Node = _a5n_surge()
	await _wait(1.5)
	_record_stage("act05_begin", _a5_snapshot())
	check(bool(_a5.get("handoff_from_act04")), "Act05 was entered through the real Act04 hand-off")
	check(await _wait_until(func() -> bool: return _peers() >= expected_players, 40.0),
		"all %d processes are still in the same ENet session (peers=%d)" % [expected_players, _peers()])
	check(int(session.call("player_count")) >= expected_players,
		"Act05 session still has %d player seats (%d)" % [expected_players, int(session.call("player_count"))])
	var remotes: Dictionary = (_a5.get("net") as Node).get("remotes") as Dictionary
	var rkeys: Array = remotes.keys()
	rkeys.sort()
	bodymap["act05"] = {"seat": me, "remotes": rkeys, "ledger_ids": (session.get("ledger") as Object).call("player_ids")}
	for pid in range(1, expected_players + 1):
		if pid != me:
			check(rkeys.has(pid), "Act05 process maps a remote body for pid%d" % pid)
	check(str(player.global_position) != "", "Act05 local body present")
	participation["act05_begin"] = _ledger_view()

	# --- entrance shutter: pid1 opens it, everyone walks in ----------------
	await _a5_path([_v5(0, 4.0, 30.0), _v5(0, 4.0, 26.2)], 1.4, "pid%d tunnel" % me)
	await _a5_travel(_v5(0, 4.0, 24.7), 10.0, 0.9, "pid%d shutter stand" % me)
	if me == 1:
		_a5_face(_v5(0, 5.1, 24.2))
		await _wait(0.3)
		await _a5_press()
		check(bool(player.get("operating")), "pid1 grabbed the jammed shutter with real E")
		if bool(player.get("operating")):
			await _a5_hold("move_forward", 4.2)
			await _a5_press()
		check(bool((level.get("push_door") as Object).get("is_opened")), "pid1 opened the jammed shutter by holding W")
	else:
		await _wait_until(func() -> bool:
			return bool((level.get("push_door") as Object).get("is_opened")), 120.0)
	await _a5_path([_v5(0, 4.0, 22.5), _v5(0, 4.0, 12.4)], 1.4, "pid%d through shutter" % me)
	check(await _wait_until(func() -> bool: return int(story.get("stage")) >= 2, 40.0),
		"pid%d entering the hall advanced the story to instability" % me)
	await _wait(0.6)
	await _a5_path([_v5(-4.2, 4.0, 10.4), _v5(-4.2, 1.4, 4.4), _v5(-4.2, 0.0, 1.5)], 1.4, "pid%d west ramp" % me)
	check(player.global_position.y < 0.6, "pid%d reached the hall floor by walking the west ramp" % me)
	await _shot("act05_hall")

	# --- B: real surge warning. pid1/2 on catwalk rails, pid3/4 on pumps --
	var pump_stand := _v5(-13.12, 0.0, -2.9)
	var rail_idx: int = 0 if me == 1 else 2
	if me <= 2:
		if me == 2:
			check(await _wait_phase("catwalk_p1", 120.0), "pid2 waited for pid1 to clear the ladder")
		check(await _a5n_climb_up(), "pid%d climbed the maintenance ladder with real E+W" % me)
		check(await _a5n_grab_rail(rail_idx), "pid%d holds catwalk rail %d" % [me, rail_idx])
		if me == 1:
			_phase_set("catwalk_p1")
	else:
		await _a5_path([
			_v5(-4.9, 0.0, 1.5), _v5(-4.9, 0.0, 0.4), _v5(-5.6, 0.0, 0.4),
			_v5(-5.6, 0.0, -5.0), _v5(-4.9, 0.0, -6.0), _v5(-4.9, 0.0, -9.6),
			_v5(-6.6, 0.0, -9.6), _v5(-9.5, 0.0, -4.2), _v5(-9.5, 0.0, -2.5),
			_v5(-11.8, 0.0, -2.2), _v5(-13.12, 0.0, -2.9)
		], 1.2, "pid%d to brake pumps" % me)
		var opb: bool = await _a5_operate_at(pump_stand, _v5(-13.12, 1.3, -3.05), "brake*", "pid%d brake" % me)
		check(opb, "pid%d mans an emergency brake pump with real E" % me)

	# Answer real warnings until this seat earns B (at most four warnings).
	var b_tries := 0
	while not _a5n_b(me) and b_tries < 4:
		b_tries += 1
		var warned: bool = await _wait_until(func() -> bool: return _a5n_warning(), 150.0)
		if not warned:
			break
		if me <= 2:
			if not bool(player.get("grabbing")):
				await _a5n_grab_rail(rail_idx)
			await _wait_until(func() -> bool:
				var s: Node = _a5n_surge()
				return s == null or str(s.get("state")) != "warning", 10.0)
			await _wait(0.4)
		else:
			Input.action_press("move_forward")
			await _wait(0.35)
			Input.action_release("move_forward")
			await _wait(0.6)
		await _wait(0.2)
	check(_a5n_b(me), "pid%d earned surge_response on a real warning (tries=%d)" % [me, b_tries])
	if me <= 2:
		if bool(player.get("grabbing")):
			await _a5_press()
			await _wait(0.4)
	else:
		await _a5_press()
		await _wait(0.3)
	_write_json_ev("mp_a5_b_%d.json" % me, _a5_snapshot())
	if role == "host":
		var allb: bool = await _wait_until(func() -> bool:
			for p in range(1, expected_players + 1):
				if not _a5n_b(p): return false
			return true, 120.0)
		check(allb, "all %d seats earned B on real warnings" % expected_players)
	await _shot("act05_b")
	# --- get off the catwalk (pid1/2) --------------------------------------
	if me <= 2:
		await _a5_travel(_v5(-9.6, 3.4, -2.9), 8.0, 0.6, "pid%d landing west edge" % me)
		await _wait(1.0)
		if player.global_position.y > 1.0:
			await _a5_travel(_v5(-10.2, 0.0, -2.9), 5.0, 0.7, "pid%d landing drop" % me)
			await _wait(1.0)
		check(player.global_position.y < 1.0, "pid%d got down from the catwalk (y=%.2f)" % [me, player.global_position.y])

	# --- A: legs + counterweights -----------------------------------------
	if me == 1:
		var opw: bool = await _a5_operate_at(_v5(-8.02, 0.0, -6.18), _v5(-7.82, 1.3, -6.41), "stabilizer_w", "pid1 west leg")
		check(opw, "pid1 operates the west stabilizer with real E")
		if opw:
			Input.action_press("move_forward")
			var t := 0.0
			while t < 35.0:
				await _wait(0.25); t += 0.25
				if _a5_latched(0): break
			Input.action_release("move_forward")
			await _a5_press()
		check(_a5_latched(0), "west stabilizer latched by pid1")
	elif me == 2:
		# wait for pid1's west leg before the east pump (interlock order)
		check(await _wait_until(func() -> bool: return _a5_latched(0), 120.0), "pid2 sees the west leg latched")
		await _a5_path([_v5(-4.9, 0.0, 1.5), _v5(-4.9, 0.0, 0.4), _v5(-5.6, 0.0, 0.4),
			_v5(-5.6, 0.0, -5.0), _v5(-4.9, 0.0, -6.0), _v5(-4.9, 0.0, -9.6),
			_v5(6.8, 0.0, -9.6), _v5(4.55, 0.0, -9.8)], 1.2, "pid2 to east leg")
		@warning_ignore("unused_variable")
		var op_e: bool = await _a5_operate_at(_v5(4.55, 0.0, -10.13), _v5(5.38, 1.3, -9.19), "stabilizer_e", "pid2 east leg")
		check(op_e, "pid2 operates the east stabilizer with real E")
		if op_e:
			Input.action_press("move_forward")
			var t2 := 0.0
			while t2 < 35.0:
				await _wait(0.25); t2 += 0.25
				if _a5_latched(1): break
			Input.action_release("move_forward")
			await _a5_press()
		check(_a5_latched(1), "east stabilizer latched by pid2")
	elif me == 3:
		# west counterweight: reduce |net| by >0.03 from the claim baseline
		await _a5_path([
			_v5(-5.6, 0.0, -6.18), _v5(-5.6, 0.0, -0.5), _v5(-6.6, 0.0, -0.5),
			_v5(-6.6, 0.0, 1.2), _v5(-6.6, 0.0, 2.4), _v5(-8.0, 0.0, 2.4)
		], 1.2, "pid3 to west station")
		await _a5_path([_v5(-8.0, 1.6, 4.7), _v5(-8.6, 1.6, 6.6), _v5(-8.5, 1.6, 7.47)], 1.2, "pid3 west station ramp")
		var opcw: bool = await _a5_operate_at(_v5(-8.5, 1.6, 7.466), _v5(-8.375, 2.8, 7.25), "cart_left", "pid3 west counterweight")
		check(opcw, "pid3 operates the west counterweight console with real E")
		if opcw:
			Input.action_press("move_forward")
			var t3 := 0.0
			while t3 < 14.0:
				await _wait(0.25); t3 += 0.25
				if abs(_a5_core_net()) <= 0.42: break
			Input.action_release("move_forward")
			await _wait(0.5)
			await _a5_press()
		check(_has_credit(3, "counterweight_effect"), "pid3 earned counterweight_effect")
	elif me == 4:
		await _a5_path([_v5(-4.9, 0.0, 1.5), _v5(-4.9, 0.0, 0.4), _v5(-5.6, 0.0, 0.4),
			_v5(-5.6, 0.0, -5.0), _v5(-4.9, 0.0, -6.0), _v5(-4.9, 0.0, -9.6),
			_v5(5.0, 0.0, -9.6), _v5(6.8, 0.0, -9.6), _v5(8.0, 0.0, -6.0),
			_v5(8.0, 0.0, 0.4), _v5(8.0, 0.0, 2.4)], 1.2, "pid4 to east station")
		await _a5_path([_v5(8.0, 1.6, 4.7), _v5(8.6, 1.6, 6.6), _v5(8.5, 1.6, 7.47)], 1.2, "pid4 east station ramp")
		var opce: bool = await _a5_operate_at(_v5(8.5, 1.6, 7.466), _v5(8.375, 2.8, 7.25), "cart_right", "pid4 east counterweight")
		check(opce, "pid4 operates the east counterweight console with real E")
		if opce:
			check(await _wait_until(func() -> bool: return _has_credit(3, "counterweight_effect"), 180.0), "pid4 waits for pid3's real counterweight before pushing")
			Input.action_press("move_forward")
			var t4 := 0.0
			while t4 < 14.0:
				await _wait(0.25); t4 += 0.25
				if abs(_a5_core_net()) <= 0.18: break
			Input.action_release("move_forward")
			await _wait(0.5)
			await _a5_press()
		check(_has_credit(4, "counterweight_effect"), "pid4 earned counterweight_effect")
	participation["act05_a"] = _ledger_view()
	if role == "host":
		check(await _wait_until(func() -> bool: return _a5_latched(0) and _a5_latched(1), 180.0),
			"both hydraulic legs are latched by two real players")
		for p in range(1, expected_players + 1):
			check(_a5n_a(p), "pid%d has a real phase-A credit" % p)

	# --- C: claw / damper / pin / carriage ---------------------------------
	var level_node: Node = _a5_level()
	if me == 1:
		await _a5_path([
			_v5(-6.6, 0.0, -4.2), _v5(-4.9, 0.0, -4.2), _v5(-4.9, 0.0, -7.6),
			_v5(5.0, 0.0, -7.6), _v5(5.0, 0.0, -6.0), _v5(5.0, 0.0, -6.0),
			_v5(10.6, 0.0, -6.0), _v5(11.1, 0.0, -6.0), _v5(11.1, 0.0, -2.0),
			_v5(11.1, 0.0, 2.0), _v5(11.1, 0.0, 10.5), _v5(0.0, 0.0, 10.5),
			_v5(0.0, 0.0, 7.85)
		], 1.0, "pid1 to claw console")
		check(Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(0.0, 7.85)) < 2.3,
			"pid1 stands at the real claw console")
		check(await _wait_until(func() -> bool: return _a5_capturable(), 180.0), "core entered the capture band")
		_a5_face(_v5(0, 1.2, 6.9))
		await _wait(0.3)
		await _a5_press()
		check(await _wait_until(func() -> bool: return _a5_core_locked(), 90.0),
			"pid1 locked the core through the real console E")
		await _shot("act05_claw")
		check(_has_credit(1, "lock_assist"), "pid1 earned lock_assist")
	elif me == 2:
		check(await _wait_until(func() -> bool: return _a5_core_locked(), 240.0), "pid2 saw the core locked")
		await _a5_path([
			_v5(5.0, 0.0, -6.0), _v5(5.0, 0.0, -7.6), _v5(-4.9, 0.0, -7.6),
			_v5(-4.9, 0.0, -4.2), _v5(-6.6, 0.0, -4.2), _v5(-9.5, 0.0, -2.5),
			_v5(-8.0, 0.0, 0.4), _v5(-5.6, 0.0, 0.4), _v5(-5.6, 0.0, -3.0),
			_v5(-4.9, 0.0, -4.2), _v5(-4.9, 0.0, -6.0), _v5(5.0, 0.0, -6.0),
			_v5(7.8, 0.0, -4.0), _v5(6.4, 0.0, -2.65)
		], 1.0, "pid2 to damper")
		var opd: bool = await _a5_operate_at(_v5(6.4, 0.0, -2.65), _v5(6.4, 1.2, -4.4), "damper", "pid2 damper")
		check(opd, "pid2 operates the damper with real E")
		if opd:
			Input.action_press("move_forward")
			var td := 0.0
			while td < 14.0 and not _a5_damper_latched():
				await _wait(0.25); td += 0.25
			Input.action_release("move_forward")
			await _wait(0.4)
			await _a5_press()
		check(_a5_damper_latched(), "damper latched by pid2")
		check(_has_credit(2, "damper_latch") or _has_credit(2, "damper_hold"), "pid2 earned damper credit")
	elif me == 3:
		check(await _wait_until(func() -> bool: return _a5_core_locked(), 240.0), "pid3 saw the core locked")
		await _a5_path([
			_v5(11.1, 0.0, 7.0), _v5(11.1, 0.0, 2.0), _v5(11.1, 0.0, -2.0),
			_v5(11.1, 0.0, -6.0), _v5(10.7, 0.0, -6.0)
		], 1.0, "pid3 to isolation pin")
		var pin_ok := false
		for _attempt in range(8):
			_a5_face(_v5(10.5, 1.9, -9.0))
			await _wait(0.3)
			await _a5_press()
			pin_ok = await _wait_until(func() -> bool: return _a5_iso_pin(), 6.0)
			if pin_ok: break
			await _a5_travel(_v5(10.7, 0.0, -6.0), 4.0, 0.8, "pid3 pin stand")
		check(pin_ok, "pid3 pulled the isolation safety pin with real E")
		check(_has_credit(3, "isolation_pin"), "pid3 earned isolation_pin")
	elif me == 4:
		check(await _wait_until(func() -> bool: return _a5_core_locked(), 240.0), "pid4 saw the core locked")
		await _a5_path([
			_v5(8.5, 1.6, 7.47), _v5(8.0, 1.6, 4.7), _v5(8.0, 0.0, 2.4),
			_v5(8.0, 0.0, 0.4), _v5(8.0, 0.0, -6.0), _v5(10.7, 0.0, -5.4)
		], 1.0, "pid4 to carriage")
		check(await _wait_until(func() -> bool:
			return float((level_node.get("damper") as Object).call("damper_effect")) >= 0.35, 240.0),
			"pid4 sees the damper loaded by pid2")
		var opc := false
		for _attempt in range(8):
			await _a5_travel(_v5(10.7, 0.0, -5.4), 4.0, 0.7, "pid4 carriage stand")
			_a5_face(_v5(10.5, 1.2, -7.2))
			await _wait(0.3)
			await _a5_press()
			if bool(player.get("operating")): opc = true; break
			await _wait(0.5)
		check(opc, "pid4 operates the isolation carriage with real E")
		if opc:
			Input.action_press("move_forward")
			var tc := 0.0
			while tc < 14.0 and not _a5_iso_sep():
				await _wait(0.25); tc += 0.25
			Input.action_release("move_forward")
			await _wait(0.3)
			await _a5_press()
		check(_a5_iso_sep(), "pid4 separated the extraction coupling by real carriage push")
		check(_has_credit(4, "carriage_push"), "pid4 earned carriage_push")

	if me == 3 and expected_players == 3:
		# 3-player crew: pid3 also works the isolation carriage after the pin.
		check(await _wait_until(func() -> bool:
			return float((level_node.get("damper") as Object).call("damper_effect")) >= 0.35, 240.0),
			"pid3 sees the damper loaded by pid2")
		var opc3 := false
		for _attempt in range(8):
			await _a5_travel(_v5(10.7, 0.0, -5.4), 4.0, 0.7, "pid3 carriage stand")
			_a5_face(_v5(10.5, 1.2, -7.2))
			await _wait(0.3)
			await _a5_press()
			if bool(player.get("operating")): opc3 = true; break
			await _wait(0.5)
		check(opc3, "pid3 operates the isolation carriage with real E (3-player crew)")
		if opc3:
			Input.action_press("move_forward")
			var tc3 := 0.0
			while tc3 < 14.0 and not _a5_iso_sep():
				await _wait(0.25); tc3 += 0.25
			Input.action_release("move_forward")
			await _wait(0.3)
			await _a5_press()
		check(_a5_iso_sep(), "pid3 separated the extraction coupling by real carriage push")
		check(_has_credit(3, "carriage_push"), "pid3 earned carriage_push")
	# --- data --------------------------------------------------------------
	check(await _wait_until(func() -> bool:
		var dp: Node = level_node.get("data_plinth")
		return dp != null and bool(dp.get("revealed_flag")), 180.0), "navigation data plinth revealed")
	if me == 3:
		await _a5_path([
			_v5(10.7, 0.0, -6.0), _v5(10.7, 0.0, -8.0), _v5(8.2, 0.0, -8.0),
			_v5(5.0, 0.0, -8.0), _v5(4.8, 0.0, -9.6), _v5(-3.0, 0.0, -9.6),
			_v5(-3.0, 0.0, -8.3)
		], 1.0, "pid3 to data plinth")
		_a5_face(_v5(-3.0, 1.0, -9.1))
		await _wait(0.3)
		var tak := false
		for _attempt in range(6):
			await _a5_press()
			tak = await _wait_until(func() -> bool: return bool(story.get("data_taken")), 8.0)
			if tak: break
			await _a5_travel(_v5(-3.0, 0.0, -8.3), 3.0, 0.7, "pid3 plinth stand")
		check(tak, "pid3 took the navigation data through the plinth with real E")
		check(_has_credit(3, "data_take"), "pid3 earned data_take")
	else:
		await _wait_until(func() -> bool: return bool(story.get("data_taken")), 180.0)
	check(bool(story.get("data_taken")), "navigation data recorded by the authority")

	# --- gate + exit -------------------------------------------------------
	var gate_ok: bool = await _wait_until(func() -> bool: return bool(session.call("can_finish")), 150.0)
	check(gate_ok, "participation gate A/B/C satisfied by real credits on all seats")
	if not gate_ok:
		log_line("GATE_TEXT %s" % str(session.call("gate_text")))
	log_line("ACT05_LEDGER %s" % JSON.stringify(_ledger_view()))
	participation["act05"] = _ledger_view()
	_write_json_ev("mp_a5_pre_exit_%d.json" % me, _a5_snapshot())
	await _shot("act05_pre_exit")
	if role == "host":
		for p in range(1, expected_players + 1):
			var lv: Dictionary = _ledger_view()
			var rec: Dictionary = lv.get(p, {}) as Dictionary
			var ph: Dictionary = rec.get("phases", {}) as Dictionary
			check(int(ph.get("A", 0)) > 0 and int(ph.get("B", 0)) > 0 and int(ph.get("C", 0)) > 0,
				"pid%d has real A/B/C credits (%s)" % [p, str(ph)])

	# All players walk out through the west exit along proven floor segments.
	# pid1's lock console is on the opposite side of the core, so its route starts
	# with the east aisle used by the 2-player acceptance run.
	var exit_path: Array = []
	if me == 1:
		exit_path = [_v5(0, 0, 10.5), _v5(11.1, 0, 10.5), _v5(11.1, 0, 2.0), _v5(11.1, 0, -2.0),
			_v5(8.0, 0, -2.3), _v5(6.4, 0, -2.65), _v5(5.0, 0, -6.0), _v5(5.0, 0, -7.6),
			_v5(-4.9, 0, -7.6), _v5(-4.9, 0, -4.2), _v5(-6.6, 0, -4.2), _v5(-9.5, 0, -2.5),
			_v5(-13.4, 0, -2.0), _v5(-17.5, 0, -2.0), _v5(-25.5, 0, -2.0)]
	elif me == 2 or me == 4:
		exit_path = [_v5(5.0, 0, -6.0), _v5(5.0, 0, -7.6), _v5(-4.9, 0, -7.6),
			_v5(-4.9, 0, -4.2), _v5(-6.6, 0, -4.2), _v5(-9.5, 0, -2.5),
			_v5(-13.4, 0, -2.0), _v5(-17.5, 0, -2.0), _v5(-25.5, 0, -2.0)]
	else:
		exit_path = [_v5(-4.9, 0, -8.3), _v5(-4.9, 0, -9.6), _v5(-8.0, 0, -9.6),
			_v5(-9.5, 0, -6.0), _v5(-9.5, 0, -2.5), _v5(-13.4, 0, -2.0),
			_v5(-17.5, 0, -2.0), _v5(-25.5, 0, -2.0)]
	await _a5_path(exit_path, 1.4, "pid%d exit corridor" % me)
	check(await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == "Finale", 400.0),
		"pid%d followed the real Act05 -> Finale settlement" % me)
	handoffs.append({"from": "act05", "to": "finale", "pid": me,
		"scene": _scene_now(), "t": float(Time.get_ticks_msec() - run_started_ms) / 1000.0})
	_write_json_ev("mp_handoff_act05_%d.json" % me, {"pid": me, "scene": _scene_now(),
		"chapter": str(hub.get("current_chapter"))})
	return current_scene != null and str(current_scene.name) == "Finale"

func _a5_snapshot() -> Dictionary:
	var out: Dictionary = {"pid": me, "t": float(Time.get_ticks_msec() - run_started_ms) / 1000.0}
	if not _valid(_a5): return out
	var level: Node = _a5.get("level")
	var story: Node = _a5.get("story")
	var session: Node = _a5.get("session")
	if story != null:
		out["stage"] = int(story.get("stage"))
		out["data_taken"] = bool(story.get("data_taken"))
		out["completed"] = bool(story.call("completed_flag"))
	if level != null:
		out["core_locked"] = bool((level.get("core") as Object).call("is_locked"))
		out["core_net"] = float((level.get("core") as Object).call("get_net"))
		out["stabs"] = _a5_latch_flags()
		out["damper"] = bool((level.get("damper") as Object).get("latched_flag"))
		out["iso_pin"] = bool((level.get("isolation") as Object).get("pin_out"))
		out["iso_sep"] = bool((level.get("isolation") as Object).get("separated_flag"))
	if session != null:
		out["can_finish"] = bool(session.call("can_finish"))
		out["gate_text"] = str(session.call("gate_text"))
		out["ledger"] = _ledger_view()
	out["pos"] = str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))) if _in_tree(player) else "off"
	return out

# ===========================================================================
# FINALE - authoritative settlement only
# ===========================================================================
func _check_finale_n() -> bool:
	var hist: Dictionary = hub.get("chapter_history") as Dictionary if hub != null else {}
	var act5: Dictionary = hist.get("act05", {}) as Dictionary
	var participants: Dictionary = act5.get("participants", {}) as Dictionary
	var ready: Array = participants.get("ready", []) as Array
	var ready_ids: Array = []
	for entry in ready:
		ready_ids.append(int((entry as Dictionary).get("id", 0)))
	ready_ids.sort()
	check(current_scene != null and str(current_scene.name) == "Finale", "settlement scene is the official Finale")
	await _shot("finale")
	check(bool(act5.get("completed", false)), "SessionHub chapter_history.act05.completed == true")
	check(str(hub.get("current_chapter")) == "finale", "SessionHub current_chapter advanced to finale")
	check(ready_ids.size() == expected_players,
		"all %d participants are in the Act05 completion payload (ready=%s)" % [expected_players, str(ready_ids)])
	var want: Array = []
	for i in range(1, expected_players + 1): want.append(i)
	check(str(ready_ids) == str(want), "the completion payload names the real seats 1..%d (%s)" % [expected_players, str(ready_ids)])
	var all_ready := true
	for p in range(1, expected_players + 1):
		var lv: Dictionary = _ledger_view()
		var rec: Dictionary = lv.get(p, {}) as Dictionary
		var ph: Dictionary = rec.get("phases", {}) as Dictionary
		if not (int(ph.get("A", 0)) > 0 and int(ph.get("B", 0)) > 0 and int(ph.get("C", 0)) > 0 \
				and int(ph.get("04", 0)) > 0):
			all_ready = false
		check(int(ph.get("04", 0)) > 0, "finale ledger: pid%d keeps its Act04 phase-04 credit" % p)
		check(int(ph.get("A", 0)) > 0 and int(ph.get("B", 0)) > 0 and int(ph.get("C", 0)) > 0,
			"finale ledger: pid%d keeps A/B/C credits (%s)" % [p, str(ph)])
	check(all_ready, "every seat keeps its Act04 + Act05 ledger identity to the finale")
	participation["finale"] = _ledger_view()
	_write_json_ev("mp_finale_%d.json" % me, {
		"pid": me, "scene": _scene_now(), "current_chapter": str(hub.get("current_chapter")),
		"act05_completed": bool(act5.get("completed", false)),
		"ready_ids": ready_ids, "ledger": _ledger_view(),
		"participants": participants,
	})
	check(str(_scene_now()) == "Finale", "pid%d is in the Finale" % me)
	return current_scene != null and str(current_scene.name) == "Finale"

# ===========================================================================
# report
# ===========================================================================
func _finish(passed: bool) -> void:
	var doc: Dictionary = {
		"task": "ACT01-MP-FULLCHAIN-3P4P-R1",
		"run_tag": tag,
		"role": role,
		"launch_index": launch_index,
		"expected_players": expected_players,
		"seat_pid": me,
		"passed": passed,
		"checks": checks,
		"failures": failures,
		"warnings": warnings,
		"reach": reach,
		"reached_furthest": _furthest(),
		"identity": identity,
		"bodymap": bodymap,
		"participation": participation,
		"handoffs": handoffs,
		"act_times_s": act_times,
		"blocked_at": blocked_at,
		"blocked_detail": blocked_detail,
		"scene_log": scene_log,
		"stage_records": stage_records,
		"wall_clock_s": snappedf(float(Time.get_ticks_msec() - run_started_ms) / 1000.0, 0.1),
	}
	_write_json_ev("mp_%s_%d.json" % [role, me], doc)
	print("RESULT %s pid=%d passed=%s checks=%d failures=%d reach=%s tag=%s" % [
		role, me, str(passed), checks, failures.size(), _furthest(), tag])
	print("RESULT_JSON " + JSON.stringify(doc))
	quit(0 if passed else 2)

func _furthest() -> String:
	if bool(reach.get("finale", false)): return "Finale"
	if bool(reach.get("act05", false)): return "Act05"
	if bool(reach.get("act04", false)): return "Act04"
	if bool(reach.get("act23", false)): return "Act23Chapter"
	if bool(reach.get("act01", false)): return "Act01"
	return "Launcher"








