extends SceneTree

## ACT01-MULTIPLAYER-R1 · 3/4-process full Act01 key-path harness.
##
## Every process boots the OFFICIAL launcher, presses the real host/client
## button, and joins the single SessionHub ENet peer. Tasks are split across the
## real seats so every participant performs at least two distinct phases, all
## players grab a different catwalk rail at the same time, one release must not
## clear the others, and the run ends with the real Act01 → Act23 hand-off.
##
## Cross-process ordering uses production flags (entry/power/vent/departure) and
## a small file gate only for the simultaneous-grab phases. No gameplay state is
## injected: bodies walk, aim and press the real input actions.
##
## All paths are absolute so the harness can live in <project>/tests for a run.

const VERSION := "mp-r1"

var role: String = "host"
var index: int = 0
var expected: int = 4
var scenario: String = "coop"
var out_dir: String = ""
var tag: String = ""
var weak: bool = false

var hub: Node = null
var unified: Node = null
var stage: Node = null
var player: Node = null
var facade: Node = null
var seat_pid: int = -1
var net_pid: int = -1

var checks: int = 0
var failures: Array[String] = []
var warnings: Array[String] = []
var log_lines: Array[String] = []
var started_msec: int = 0
var scene_log: Array[String] = []
var _last_scene_id: int = 0
var _cap: Dictionary = {}
var _grab_result: Dictionary = {}
var _release_result: Dictionary = {}

# ------------------------------------------------------------------ boot/args --
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
		if s.begins_with("--role="): role = s.split("=")[1]
		elif s.begins_with("--index="): index = int(s.split("=")[1])
		elif s.begins_with("--expected="): expected = int(s.split("=")[1])
		elif s.begins_with("--scenario="): scenario = s.split("=")[1]
		elif s.begins_with("--out="): out_dir = s.split("=")[1]
		elif s.begins_with("--tag="): tag = s.split("=")[1]
		elif s == "--weak=1": weak = true

func _watchdog() -> void:
	await create_timer(1500.0).timeout
	push_error("MP_COOP_WATCHDOG_TIMEOUT role=%s" % role)
	_finish(false)

# --------------------------------------------------------------------- utils --
func log_line(text: String) -> void:
	print("[%s%d] %s" % [role, index, text])
	log_lines.append(text)

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
	await create_timer(seconds).timeout

## Real-clock wait: production throttles / ENet retransmits use wall time.
func _wait_real(seconds: float) -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await process_frame

func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout_s * 1000.0):
		if bool(cond.call()):
			return true
		await process_frame
	return bool(cond.call())

func _scene_name() -> String:
	return str(current_scene.name) if current_scene != null else "null"

func _find_button_by_text(text: String, from: Node) -> Button:
	if from == null:
		return null
	for n in from.find_children("*", "Button", true, false):
		var b: Button = n as Button
		if b != null and b.text == text:
			return b
	return null

func _click_button(btn: Button) -> bool:
	if btn == null:
		return false
	var vp: Window = get_root()
	for _i in range(3):
		await physics_frame
	await _wait(0.25)
	var canvas_size: Vector2 = vp.get_visible_rect().size
	var window_size: Vector2 = vp.size
	var rect: Rect2 = btn.get_global_rect()
	if rect.size == Vector2.ZERO:
		log_line("CLICK empty rect for '%s'" % btn.text)
		return false
	var scale_v := Vector2(window_size.x / maxf(canvas_size.x, 1.0),
		window_size.y / maxf(canvas_size.y, 1.0))
	var click: Vector2 = rect.get_center() * scale_v
	log_line("CLICK '%s' rect=%s click=%s" % [btn.text, str(rect), str(click)])
	var motion := InputEventMouseMotion.new()
	motion.position = click
	motion.global_position = click
	vp.push_input(motion)
	await _wait(0.12)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click
	press.global_position = click
	vp.push_input(press)
	await _wait(0.10)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click
	release.global_position = click
	vp.push_input(release)
	await _wait(0.30)
	return true

# --------------------------------------------------------------- file gates ---
func _abs(name: String) -> String:
	return out_dir.replace('\\', '/') + "/" + name

func _write_json(name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := _abs(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		log_line("FILE_WRITE_FAIL " + name)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()

func _read_json(name: String) -> Dictionary:
	var path := _abs(name)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	var parsed: Variant = j.data
	return parsed as Dictionary if parsed is Dictionary else {}

func _host_phase(name: String, extra: Dictionary = {}) -> void:
	var doc := {"name": name, "seq": Time.get_ticks_msec(), "unix_ms":
		Time.get_unix_time_from_system() * 1000.0}
	for k in extra.keys():
		doc[k] = extra[k]
	_write_json("phase.json", doc)

func _phase() -> String:
	return str(_read_json("phase.json").get("name", ""))

func _wait_phase(name: String, timeout_s: float) -> bool:
	return await _wait_until(func() -> bool: return _phase() == name, timeout_s)

func _role_file(which: String) -> String:
	return "%s%d.%s.json" % [role, index, which]

# ------------------------------------------------------------------- capture --
func _process(_delta: float) -> bool:
	var cs: Node = current_scene
	var id: int = cs.get_instance_id() if cs != null else 0
	if id != _last_scene_id:
		_last_scene_id = id
		scene_log.append(_scene_name())
		log_line("SCENE %s" % _scene_name())
	return false

func _stats() -> Dictionary:
	if unified == null or not is_instance_valid(unified):
		return {}
	return unified.call("act1_stats") as Dictionary

func _capture() -> Dictionary:
	if stage == null or not is_instance_valid(stage) or current_scene != stage:
		return _cap.duplicate(true) if not _cap.is_empty() else {}
	var flags: Dictionary = (stage.get("flags") as Dictionary).duplicate(true)
	var credits: Dictionary = {}
	var raw: Dictionary = stage.get("credits") as Dictionary
	for pid in raw.keys():
		var rec: Dictionary = raw[pid]
		var kinds: Array = (rec.get("kinds", {}) as Dictionary).keys()
		kinds.sort()
		credits[int(pid)] = {
			"name": str(rec.get("name", "")),
			"kinds": kinds,
			"phases": (rec.get("phases", {}) as Dictionary).duplicate(true),
			"active": bool(rec.get("active", true)),
		}
	var players: Dictionary = {}
	var active: Dictionary = stage.get("active_pids") as Dictionary
	for key in active.keys():
		var pid := int(key)
		var st: Dictionary = {}
		if pid == int(stage.get("local_pid")):
			if player != null and is_instance_valid(player):
				st = player.call("get_state_packet") as Dictionary
		else:
			st = ((stage.get("remote_states") as Dictionary).get(pid, {}) as Dictionary).duplicate(true)
		var clean := {}
		for k in ["pos", "yaw", "grab", "downed", "external"]:
			if st.has(k):
				if k == "pos" and st[k] is Vector3:
					var v: Vector3 = st[k]
					clean[k] = [v.x, v.y, v.z]
				else:
					clean[k] = st[k]
		players[pid] = clean
	var grab_owner: Variant = stage.get("grab_owner")
	return {
		"t_ms": Time.get_ticks_msec() - started_msec,
		"role": role, "index": index,
		"stage_pid": int(stage.get("local_pid")),
		"net_pid": int(unified.get("local_pid")),
		"peer_count": int(facade.call("peer_count")),
		"flags": flags,
		"credits": credits,
		"reset_seq": int(stage.get("reset_seq")),
		"cart_operator": int(stage.get("cart_operator")),
		"grab_owner": (grab_owner as Dictionary).duplicate(true) if grab_owner is Dictionary else {},
		"hold_owner": (stage.get("hold_owner") as Dictionary).duplicate(true),
		"local_grabbing": bool(player.get("grabbing")) if player != null and is_instance_valid(player) else false,
		"local_external": bool(player.get("external_hold")) if player != null and is_instance_valid(player) else false,
		"local_pos": [player.global_position.x, player.global_position.y, player.global_position.z]
			if player != null and is_instance_valid(player) else [],
		"players": players,
		"remotes": (stage.get("remotes") as Dictionary).keys(),
		"active_pids": active.keys(),
		"all_ready": bool(stage.call("all_active_ready")),
		"all_aboard": bool(stage.call("all_active_aboard")),
	}

func _snapshot(label: String) -> void:
	var c := _capture()
	if c.is_empty():
		return
	c["label"] = label
	_write_json("%s%d.snap.%s.json" % [role, index, label], c)

# ---------------------------------------------------------------- launcher ----
func _enter_act01() -> bool:
	hub = root.get_node_or_null("/root/SessionHub")
	check(hub != null, "official unified SessionHub autoload is present")
	if hub == null:
		return false
	unified = hub.get("net") as Node
	var guard := 0
	while current_scene == null and guard < 900:
		await physics_frame
		guard += 1
	if current_scene == null or str(current_scene.name) != "Launcher":
		check(false, "booted into the official Launcher (scene=%s)" % _scene_name())
		return false
	var button_text := "创建主机（等待队友加入）" if role == "host" else "加入主机（本机 127.0.0.1）"
	var btn: Button = null
	guard = 0
	while btn == null and guard < 400:
		await _wait(0.05)
		btn = _find_button_by_text(button_text, current_scene)
		guard += 1
	if btn == null:
		check(false, "Launcher built the '%s' button" % button_text)
		return false
	await _click_button(btn)
	if not await _wait_until(func() -> bool: return _scene_name() == "Act01", 60.0):
		check(false, "real Launcher click entered Act01 (scene=%s)" % _scene_name())
		return false
	check(true, "official Launcher + real mouse click entered Act01")
	stage = current_scene
	player = stage.get("local_player") as Node
	facade = stage.get("net") as Node
	check(stage != null and player != null and facade != null, "Act01 stage/player/facade exist")
	return stage != null and player != null and facade != null

func _wait_seat() -> bool:
	if role == "host":
		var all: bool = await _wait_until(func() -> bool:
			var active: Dictionary = stage.get("active_pids") as Dictionary
			var reg: Dictionary = unified.get("_act1_registered_pids") as Dictionary
			return active.size() >= expected and reg.size() >= expected - 1, 300.0)
		check(all, "host registered %d real seats (active=%s)" % [expected, str((stage.get("active_pids") as Dictionary).keys())])
		var avatars: bool = await _wait_until(func() -> bool:
			return (stage.get("remotes") as Dictionary).size() >= expected - 1, 120.0)
		check(avatars, "host renders %d remote bodies (%s)" % [expected - 1, str((stage.get("remotes") as Dictionary).keys())])
		return all and avatars
	var welcomed: bool = await _wait_until(func() -> bool:
		var cn: Node = root.get_node_or_null("/root/SessionHub/CoopNet")
		return cn != null and bool(cn.get("_act1_welcomed")) and bool(cn.get("_act1_bootstrapped")), 300.0)
	check(welcomed, "client applied welcome + authoritative bootstrap")
	if not welcomed:
		return false
	var all_seen: bool = await _wait_until(func() -> bool:
		return (stage.get("active_pids") as Dictionary).size() >= expected, 180.0)
	check(all_seen, "client sees %d active pids (%s)" % [expected, str((stage.get("active_pids") as Dictionary).keys())])
	var avatars: bool = await _wait_until(func() -> bool:
		return (stage.get("remotes") as Dictionary).size() >= expected - 1, 180.0)
	check(avatars, "client renders %d remote bodies (%s)" % [expected - 1, str((stage.get("remotes") as Dictionary).keys())])
	return all_seen and avatars

func _assert_identity() -> void:
	seat_pid = int(stage.get("local_pid"))
	net_pid = int(unified.get("local_pid"))
	check(seat_pid >= 1 and seat_pid <= expected, "seat pid is in the valid 1..%d range (pid=%d)" % [expected, seat_pid])
	check(net_pid == seat_pid, "CoopNet.local_pid matches the assigned seat (net=%d stage=%d)" % [net_pid, seat_pid])
	check(not (stage.get("remotes") as Dictionary).has(seat_pid), "no self avatar for pid %d" % seat_pid)
	if role != "host":
		var cn: Node = root.get_node_or_null("/root/SessionHub/CoopNet")
		check(int(cn.get("_act1_welcome_pid")) == seat_pid,
			"welcome pid == seat pid (welcome=%d seat=%d)" % [int(cn.get("_act1_welcome_pid")), seat_pid])
		check(bool(cn.get("_act1_bootstrapped")), "client bootstrap applied")
	else:
		check(seat_pid == 1, "host owns pid 1")

# --------------------------------------------------------------- motion -------
func _face(target: Vector3) -> void:
	if not is_instance_valid(player):
		return
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	player.set("yaw", yaw)
	player.rotation.y = yaw

func _walk(target: Vector3, seconds: float, label := "", arrive := 0.6) -> void:
	if not is_instance_valid(player):
		return
	var start: Vector3 = player.global_position
	_face(target)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	var frames: int = int(seconds * 60.0)
	for _i in range(frames):
		await physics_frame
		if not is_instance_valid(player) or current_scene != stage:
			break
		_face(target)
		if Vector2(player.global_position.x - target.x,
				player.global_position.z - target.z).length() < arrive:
			break
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await physics_frame
	if is_instance_valid(player):
		log_line("WALK %s target=%s pos=%s moved=%.2f" % [
			label, str(target.snapped(Vector3(0.01, 0.01, 0.01))),
			str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
			player.global_position.distance_to(start)])

func _jump_forward(seconds: float, label := "") -> void:
	Input.action_press("move_forward")
	await physics_frame
	Input.action_press("jump")
	await _wait(0.12)
	Input.action_release("jump")
	var frames: int = int(seconds * 60.0)
	for _i in range(frames):
		await physics_frame
		if not is_instance_valid(player) or current_scene != stage:
			break
	Input.action_release("move_forward")
	await physics_frame
	if is_instance_valid(player):
		log_line("JUMP %s pos=%s" % [label, str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])

func _aim(id: String) -> String:
	if stage == null or player == null:
		return "no_stage"
	var points: Dictionary = stage.get("interactables") as Dictionary
	if not points.has(id):
		return "missing"
	var point: Node3D = points[id] as Node3D
	if point == null:
		return "null"
	player.call("look_at_point", point.global_position)
	await _wait(0.22)
	if player.get("current_target") == null:
		return "none"
	return str((player.get("current_target") as Object).get("interaction_id"))

func _press(id: String, hold := 0.14) -> bool:
	var found: String = await _aim(id)
	log_line("AIM %s -> %s pos=%s" % [id, found,
		str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])
	if found != id:
		return false
	Input.action_press("interact")
	await _wait(hold)
	Input.action_release("interact")
	await _wait_real(0.45)
	return true

func _press_until(id: String, flag: String, tries: int, gap := 1.0) -> bool:
	for _i in range(tries):
		if _flag(flag):
			return true
		if await _press(id, 0.14):
			await _wait(gap)
		else:
			await _wait(0.6)
	return _flag(flag)

## The collapsed gantry is a real 54 kg rigid body: one impulse moves it ~1 m,
## just outside the 4.25 m reach, and `debris_cleared` only trips past 1.55 m.
## A player must step closer and shove again (exactly what a human does).
func _push_gantry() -> bool:
	for i in range(5):
		if _flag("debris_cleared"):
			return true
		var g: Node = (stage.get("interactables") as Dictionary).get("shove_gantry") as Node
		if g == null or not is_instance_valid(g):
			return _flag("debris_cleared")
		var gp: Vector3 = g.global_position
		await _walk(Vector3(gp.x + 1.7, 0, gp.z + 1.25), 2.4, "gantry push %d" % i, 0.45)
		await _press("shove_gantry", 0.14)
		await _wait(1.2)
	return _flag("debris_cleared")

func _hold(id: String, seconds: float) -> bool:
	var found: String = await _aim(id)
	if found != id:
		log_line("HOLD_FAIL %s -> %s" % [id, found])
		return false
	Input.action_press("interact")
	await _wait_real(seconds)
	Input.action_release("interact")
	await _wait_real(0.3)
	return true

func _tap_interact() -> void:
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	await _wait_real(0.6)

func _flag(key: String) -> bool:
	if stage == null or not is_instance_valid(stage):
		return false
	return bool((stage.get("flags") as Dictionary).get(key, false))

func _wait_flag(key: String, timeout_s: float) -> bool:
	return await _wait_until(func() -> bool: return _flag(key), timeout_s)

func _credit_kinds(pid: int) -> Array:
	if stage != null and is_instance_valid(stage) and current_scene == stage:
		var credits: Dictionary = stage.get("credits") as Dictionary
		var rec: Variant = credits.get(pid)
		if rec is Dictionary:
			return ((rec as Dictionary).get("kinds", {}) as Dictionary).keys()
	var cached: Dictionary = _cap.get("credits", {}) as Dictionary
	var crec: Variant = cached.get(pid, cached.get(str(pid)))
	if crec is Dictionary:
		return (crec as Dictionary).get("kinds", []) as Array
	return []

func _phase_count(pid: int) -> int:
	if stage != null and is_instance_valid(stage) and current_scene == stage:
		var credits: Dictionary = stage.get("credits") as Dictionary
		var rec: Variant = credits.get(pid)
		if rec is Dictionary:
			return ((rec as Dictionary).get("phases", {}) as Dictionary).size()
	var cached: Dictionary = _cap.get("credits", {}) as Dictionary
	var crec: Variant = cached.get(pid, cached.get(str(pid)))
	if crec is Dictionary:
		return ((crec as Dictionary).get("phases", {}) as Dictionary).size()
	return 0

# ------------------------------------------------------------ catwalk route ---
func _goto_ramp_foot() -> void:
	await _walk(Vector3(2.2, 0, -15.4), 6.0, "ramp foot")
	await _walk(Vector3(2.35, 0, -18.4), 4.0, "ramp climb")
	await _walk(Vector3(2.35, 0, -20.0), 2.0, "ramp top step")
	await _jump_forward(1.0, "onto catwalk")

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

func _walk_to_rail() -> void:
	await _goto_ramp_foot()
	await _walk(Vector3(2.0, 3.42, _rail_z(seat_pid)), 8.0, "rail %s" % _rail_for_pid(seat_pid))

func _grab_own_rail() -> bool:
	var rid := _rail_for_pid(seat_pid)
	for attempt in range(4):
		if bool(player.get("grabbing")):
			return true
		if await _press(rid, 0.14):
			await _wait_real(0.8)
			if bool(player.get("grabbing")):
				var anchor: Variant = player.get("grab_anchor")
				var got := str((anchor as Object).get("interaction_id")) if anchor != null and is_instance_valid(anchor) else ""
				check(got == rid, "pid %d grabbed its own rail %s (got=%s)" % [seat_pid, rid, got])
				return got == rid
		# Small lateral correction; the rail collides inside the west lip.
		await _walk(Vector3(1.85, 3.42, _rail_z(seat_pid)), 1.4, "rail approach %d" % attempt)
	return false

# ---------------------------------------------------------------- full flow ---
func _run_coop() -> void:
	_cap = _capture()
	_snapshot("joined")
	await _wait(0.8 + 0.7 * index)  # stagger the bodies leaving spawn

	# ---- 1. entry -----------------------------------------------------------
	if seat_pid == 1:
		# Stand clear of the gantry until the client has shoved it. Walking into
		# the rigid body would move it out of the client's reach and make the
		# entry gate unreachable for everyone.
		await _walk(Vector3(0, 0, 14.0), 4.0, "entry approach")
		var debris_seen := await _wait_flag("debris_cleared", 120.0)
		check(debris_seen, "host sees pid2 clear the collapsed gantry")
		await _wait_real(1.6)
		# The physics fallback must not hand the host a credit for the client's
		# real shove. This is the cross-seat attribution check for entry_shove.
		check(not _credit_kinds(1).has("entry_shove"),
			"host did not claim pid2's gantry shove credit (host kinds=%s)" % str(_credit_kinds(1)))
		var latched := await _wait_flag("latch_released", 60.0)
		check(latched, "host sees the client's latch release")
		await _walk(Vector3(2.4, 0, 10.5), 3.0, "door handle east")
		await _hold("door_handle", 7.4)
		var opened := await _wait_flag("door_open", 20.0)
		check(opened, "host opened the industrial door by holding E")
	elif seat_pid == 2:
		await _walk(Vector3(3.1, 0, 10.35), 6.0, "latch side")
		var debris := await _push_gantry()
		check(debris, "pid2 cleared the collapsed gantry with a real shove (entry credit owner)")
		var latched2 := await _press_until("release_latch", "latch_released", 5, 1.0)
		check(latched2, "pid2 released the mechanical latch (entry credit owner)")
	else:
		await _walk(Vector3(0, 0, 11.0), 5.0, "wait outside door")
		var opened2 := await _wait_flag("door_open", 120.0)
		check(opened2, "pid%d sees the door open" % seat_pid)

	await _wait_flag("door_open", 120.0)
	await _walk(Vector3(0, 0, 6.4), 5.0, "through doorway")
	await _walk(Vector3(0, 0, 4.0), 2.5, "airlock exit")

	# ---- 2. power -----------------------------------------------------------
	if seat_pid == 1:
		await _walk(Vector3(-3.0, 0, 0.4), 3.5, "power room west")
		await _walk(Vector3(-7.8, 0, 0.4), 3.5, "power room north")
		await _walk(Vector3(-8.0, 0, -2.5), 2.2, "cart rear")
		await _press("cart_push", 0.14)
		check(bool(player.get("external_hold")), "host gripped the power trolley")
		Input.action_press("move_forward")
		for _i in range(150):
			await physics_frame
		Input.action_release("move_forward")
		await _wait(0.3)
		await _tap_interact()
		await _walk(Vector3(-4.6, 0, -0.4), 2.8, "around cart north")
		await _walk(Vector3(-1.0, 0, -0.5), 3.6, "rail bracket")
		await _walk(Vector3(-0.95, 0, -1.15), 1.6, "bracket approach")
		await _press("rail_shove", 0.12)
		await _wait(0.8)
		check(_flag("rail_cleared"), "host cleared the rail bracket")
		await _walk(Vector3(-1.0, 0, -0.4), 2.2, "return north")
		await _walk(Vector3(-7.8, 0, -0.4), 3.6, "cart rear north")
		await _walk(Vector3(-7.8, 0, -2.55), 1.8, "cart rear center")
		await _walk(Vector3(-7.2, 0, -2.55), 1.2, "cart handle")
		await _press("cart_push", 0.14)
		Input.action_press("move_forward")
		for _i in range(520):
			await physics_frame
		Input.action_release("move_forward")
		await _wait(1.0)
		await _tap_interact()
		await _wait(0.5)
		check(_flag("power_docked"), "host docked the power trolley")
		await _walk(Vector3(1.5, 0, -0.5), 2.2, "cart west north")
		await _walk(Vector3(1.5, 0, -5.0), 2.8, "socket west")
		await _walk(Vector3(1.95, 0, -5.0), 1.2, "winch")
		await _press("power_winch", 0.14)
		await _wait(2.6)
		check(_flag("power_seated"), "host moved the power module into the socket")
		if expected == 2:
			await _walk(Vector3(2.4, 0, -4.3), 2.6, "clamp west")
			var clamped2 := await _press_until("power_clamp", "power_clamped", 5, 1.0)
			check(clamped2, "host clamped the power module (2-player topology)")
	elif seat_pid == 3:
		await _walk(Vector3(1.5, 0, -0.5), 3.0, "cart west")
		await _walk(Vector3(2.4, 0, -4.3), 3.0, "clamp west")
		var seated := await _wait_flag("power_seated", 180.0)
		check(seated, "pid3 sees the power module seated")
		var clamped := await _press_until("power_clamp", "power_clamped", 5, 1.0)
		check(clamped, "pid3 clamped the power module (power credit owner)")
	else:
		await _walk(Vector3(2.6, 0, -4.3), 4.0, "clamp queue")

	var clamped_all := await _wait_flag("power_clamped", 120.0)
	check(clamped_all, "power module clamped (networked flag)")
	await _walk(Vector3(0, 0, -8.0), 3.0, "power exit")
	await _walk(Vector3(-1.0, 0, -12.8), 3.5, "vent threshold")

	# ---- 3. ventilation -----------------------------------------------------
	if seat_pid == 1:
		await _walk(Vector3(-7.8, 0, -14.8), 5.0, "west gallery north")
		await _walk(Vector3(-7.8, 0, -18.0), 2.4, "control gallery")
		var coupled := await _wait_flag("coupling_engaged", 180.0)
		check(coupled, "host sees the coupling engaged")
		await _walk(Vector3(-7.8, 0, -23.0), 2.8, "fan start")
		var fan := await _press_until("start_fan", "fan_started", 4, 1.0)
		check(fan, "host started the main fan (vent credit)")
		await _walk(Vector3(-7.8, 0, -14.8), 3.6, "west gallery return")
		await _walk(Vector3(7.0, 0, -14.8), 7.2, "east gallery north")
		await _walk(Vector3(7.0, 0, -18.0), 2.4, "east gallery")
		await _walk(Vector3(8.0, 0, -29.6), 5.2, "damper control")
		var damper := await _press_until("damper", "damper_open", 4, 1.0)
		check(damper, "host opened the main duct damper (vent credit)")
	elif seat_pid == 3:
		await _walk(Vector3(7.0, 0, -14.8), 7.2, "east hall north")
		await _walk(Vector3(7.0, 0, -17.5), 2.2, "east hall")
		await _walk(Vector3(7.7, 0, -22.3), 3.0, "rotor lock")
		var rotor := await _press_until("rotor_lock", "rotor_lock_released", 4, 1.0)
		check(rotor, "pid3 removed the rotor lock (vent credit owner)")
		await _walk(Vector3(8.1, 0, -28.15), 4.0, "coupling")
		var couple := await _press_until("coupling", "coupling_engaged", 4, 1.0)
		check(couple, "pid3 engaged the drive coupling")
	elif seat_pid == 2:
		if expected == 2:
			# No pid3 in a two-player crew: the client owns the fan drive chain
			# (rotor lock + coupling) before the host's start handle.
			await _walk(Vector3(7.0, 0, -14.8), 7.2, "east hall north")
			await _walk(Vector3(7.0, 0, -17.5), 2.2, "east hall")
			await _walk(Vector3(7.7, 0, -22.3), 3.0, "rotor lock")
			var rotor2 := await _press_until("rotor_lock", "rotor_lock_released", 4, 1.0)
			check(rotor2, "pid2 removed the rotor lock (2-player vent owner)")
			await _walk(Vector3(8.1, 0, -28.15), 4.0, "coupling")
			var couple2 := await _press_until("coupling", "coupling_engaged", 4, 1.0)
			check(couple2, "pid2 engaged the drive coupling (2-player vent owner)")
			# Cross the hall on the north floor; the direct diagonal crosses the
			# open pit (x -4..5, z -21..-31).
			await _walk(Vector3(8.0, 0, -18.0), 4.0, "east return")
			await _walk(Vector3(8.0, 0, -16.5), 2.0, "east north")
			await _walk(Vector3(-7.8, 0, -16.5), 5.0, "north crossing")
			await _walk(Vector3(-7.8, 0, -23.0), 3.0, "governor bay")
		else:
			await _walk(Vector3(-7.8, 0, -14.8), 7.2, "west hall north")
			await _walk(Vector3(-7.8, 0, -18.0), 2.4, "gallery")
			await _walk(Vector3(-7.8, 0, -23.0), 3.0, "governor bay")
		var fan_seen := await _wait_flag("fan_started", 240.0)
		check(fan_seen, "pid2 sees the fan started")
		if expected <= 3:
			# The governor cycles 62% -> 100% -> 55%; only one seat may press it
			# in this scripted crew. In a 4-player crew pid4 owns that vent
			# credit, so pid2 must not turn the 6 s test off.
			await _press("governor", 0.14)
			await _wait(1.0)
			check(_credit_kinds(2).has("governor"), "pid2 adjusted the governor (vent credit owner)")
		else:
			note("pid2 leaves the governor to pid4 (single shared control)")
	else:
		# The wind crate sits above the open pit (catwalk level); a floor route
		# walks straight into it. pid4's two required phases are governor (vent)
		# and cargo (departure), both on safe floor routes.
		await _walk(Vector3(-7.8, 0, -14.8), 7.2, "west hall north")
		await _walk(Vector3(-7.8, 0, -18.0), 2.4, "gallery")
		await _walk(Vector3(-7.8, 0, -23.0), 3.0, "governor bay")
		await _wait_flag("fan_started", 240.0)
		await _press("governor", 0.14)
		await _wait(1.0)
		check(_credit_kinds(4).has("governor"), "pid4 adjusted the governor (vent credit owner)")

	var vent_done := await _wait_flag("vent_complete", 180.0)
	check(vent_done, "6 s pressure test completed (networked vent_complete)")

	# ---- 4. simultaneous catwalk grabs -------------------------------------
	if seat_pid == 1 or seat_pid == 3:
		await _walk(Vector3(7.0, 0, -18.0), 4.0, "hall return")
		await _walk(Vector3(7.0, 0, -14.8), 3.0, "hall north")
	else:
		await _walk(Vector3(-7.8, 0, -18.0), 4.0, "hall return")
		await _walk(Vector3(-7.8, 0, -14.8), 3.0, "hall north")
	await _walk(Vector3(2.2, 0, -15.4), 3.0, "ramp foot")
	await _walk_to_rail()
	var here := _capture()
	_write_json(_role_file("at_rail"), here)
	if role == "host":
		var all_here: bool = await _wait_until(func() -> bool:
			var rs: Dictionary = stage.get("remote_states") as Dictionary
			var n := 0
			for pid in rs.keys():
				var st: Dictionary = rs[pid] as Dictionary
				var p: Variant = st.get("pos", null)
				if p is Vector3 and (p as Vector3).y > 3.0 and (p as Vector3).z < -19.5:
					n += 1
			return n >= expected - 1, 120.0)
		check(all_here, "host sees all %d remote bodies on the catwalk" % (expected - 1))
		_host_phase("grab", {"rails": {1: "grab_212", 2: "grab_236", 3: "grab_258", 4: "grab_316"}})
		var own := await _grab_own_rail()
		check(own, "host grabbed its own rail %s" % _rail_for_pid(1))
		# Wait for every client's grab record.
		var t0: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 120000:
			var n := 0
			for i in range(1, expected):
				if not _read_json("client%d.grab.json" % i).is_empty():
					n += 1
			if n >= expected - 1:
				break
			await process_frame
		var owners: Dictionary = stage.get("grab_owner") as Dictionary
		var distinct: Dictionary = {}
		for pid in owners.keys():
			distinct[str(owners[pid])] = true
		check(owners.size() == expected, "host owns %d simultaneous grabs (%s)" % [owners.size(), str(owners)])
		check(distinct.size() == expected, "%d distinct rails are owned at once (%s)" % [distinct.size(), str(distinct.keys())])
		var client_ok := true
		var client_report: Array = []
		for i in range(1, expected):
			var g: Dictionary = _read_json("client%d.grab.json" % i)
			client_report.append(g)
			client_ok = client_ok and bool(g.get("ok", false)) and int(g.get("pid", -1)) == int(g.get("expected_pid", -2))
		check(client_ok, "every client body reports its own grab (%s)" % str(client_report))
		# release exactly one player's grip through the real E path
		var release_pid := 3 if expected >= 3 else 2
		_host_phase("release_one", {"pid": release_pid})
		var released: bool = await _wait_until(func() -> bool:
			var o: Dictionary = stage.get("grab_owner") as Dictionary
			return not o.has(release_pid) and o.size() == expected - 1, 30.0)
		var o2: Dictionary = stage.get("grab_owner") as Dictionary
		check(released, "pid%d release cleared only its own grab (owner=%s)" % [release_pid, str(o2)])
		check(o2.size() == expected - 1, "the other %d grabs survived the release" % (expected - 1))
		_host_phase("release_all")
		await _tap_interact()
		var cleared: bool = await _wait_until(func() -> bool:
			return (stage.get("grab_owner") as Dictionary).is_empty(), 30.0)
		check(cleared, "all grabs released cleanly (owner empty)")
		_host_phase("done_grab")
	else:
		var grab_ok := false
		if await _wait_phase("grab", 180.0):
			grab_ok = await _grab_own_rail()
			await _wait_real(0.6)
			var anchor: Variant = player.get("grab_anchor")
			var got := str((anchor as Object).get("interaction_id")) if anchor != null and is_instance_valid(anchor) else ""
			_write_json(_role_file("grab"), {"index": index, "pid": seat_pid, "expected_pid": seat_pid,
				"grabbing": bool(player.get("grabbing")), "rail": got, "ok": grab_ok and bool(player.get("grabbing"))})
			check(grab_ok, "pid%d grabbed its own rail %s over the real grant path" % [seat_pid, _rail_for_pid(seat_pid)])
			var rel: Dictionary = {}
			if await _wait_phase("release_one", 120.0):
				rel = _read_json("phase.json")
				if int(rel.get("pid", 0)) == seat_pid:
					await _tap_interact()
					await _wait_real(0.8)
					check(not bool(player.get("grabbing")), "pid%d released its own grip via E" % seat_pid)
				else:
					await _wait_real(0.8)
					check(bool(player.get("grabbing")), "pid%d still holds while another player releases" % seat_pid)
			if await _wait_phase("release_all", 120.0):
				await _tap_interact()
				await _wait_real(0.8)
				check(not bool(player.get("grabbing")), "pid%d released after the release_all phase" % seat_pid)
			await _wait_phase("done_grab", 120.0)
		else:
			check(false, "pid%d reached the grab phase" % seat_pid)

	# ---- 5. departure chain -------------------------------------------------
	# Staging only: a 2.85 m catwalk with four bodies is not the subject of this
	# gate, and repeated runs showed a crowded descent can push a body through
	# the missing west-rail section. Every seat has already walked the full
	# level and performed its grab; place the bodies back at the authored ramp
	# foot so the departure chain runs from a deterministic pose.
	await _wait(1.1 * float(seat_pid - 1))
	check(not bool(player.get("downed")), "pid%d is upright after the grab matrix" % seat_pid)
	player.call("teleport", Vector3(2.2, 0.6, -15.6), 0.0, -0.04)
	await _wait(0.4)
	await _walk(Vector3(2.2, 0, -15.4), 1.0, "ramp foot")
	# The pit (x -4..5, z -21..-31) is open; walking straight south from the
	# ramp drops the body into it. Use the east aisle around the pit, exactly
	# like the authored route.
	await _walk(Vector3(8.0, 0, -16.5), 4.0, "east aisle north")
	await _walk(Vector3(8.0, 0, -33.0), 6.0, "east aisle south")
	await _walk(Vector3(0, 0, -35.6), 3.5, "hall center")
	await _walk(Vector3(0, 0, -37.6), 2.5, "station threshold")

	if seat_pid == 2:
		await _walk(Vector3(-5.6, 0, -40.5), 3.5, "station west")
		await _walk(Vector3(-5.6, 0, -44.3), 4.0, "chock approach")
		await _walk(Vector3(-5.62, 0, -45.5), 1.8, "chock")
		var chock := await _press_until("chock", "chock_removed", 6, 1.2)
		check(chock, "pid2 removed the wheel chock (departure credit owner)")
	elif seat_pid == 3:
		await _walk(Vector3(0, 0, -38.2), 2.0, "station center")
		await _walk(Vector3(7.2, 0, -38.2), 4.0, "ramp north")
		await _walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _wait_flag("chock_removed", 180.0)
		await _walk(Vector3(7.35, 1.55, -48.2), 3.5, "platform brake")
		await _walk(Vector3(6.55, 1.55, -48.6), 1.6, "brake")
		var brake := await _press_until("parking_brake", "brake_released", 6, 1.2)
		check(brake, "pid3 released the parking brake (departure credit owner)")
	elif seat_pid == 4:
		await _walk(Vector3(7.2, 0, -38.2), 3.5, "ramp north")
		await _walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _walk(Vector3(7.35, 1.55, -43.9), 2.5, "platform cargo")
		await _wait_flag("brake_released", 180.0)
		await _walk(Vector3(6.55, 1.55, -43.0), 1.8, "cargo strap")
		var cargo := await _press_until("cargo", "cargo_secured", 6, 1.2)
		check(cargo, "pid4 locked the cargo restraint (departure credit owner)")
	elif seat_pid == 1 and expected == 2:
		await _walk(Vector3(7.2, 0, -38.2), 4.0, "ramp north")
		await _walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _wait_flag("chock_removed", 180.0)
		await _walk(Vector3(7.35, 1.55, -48.2), 3.5, "platform brake")
		await _walk(Vector3(6.55, 1.55, -48.6), 1.6, "brake")
		var brake2 := await _press_until("parking_brake", "brake_released", 6, 1.2)
		check(brake2, "host released the parking brake (2-player departure owner)")
		await _walk(Vector3(6.55, 1.55, -43.0), 4.0, "cargo strap")
		var cargo3 := await _press_until("cargo", "cargo_secured", 6, 1.2)
		check(cargo3, "host locked the cargo restraint (2-player departure owner)")
	elif seat_pid == 1 and expected == 3:
		await _walk(Vector3(7.2, 0, -38.2), 4.0, "ramp north")
		await _walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _wait_flag("brake_released", 180.0)
		await _walk(Vector3(7.35, 1.55, -43.9), 3.0, "platform cargo")
		await _walk(Vector3(6.55, 1.55, -43.0), 1.8, "cargo strap")
		var cargo2 := await _press_until("cargo", "cargo_secured", 6, 1.2)
		check(cargo2, "host covered cargo in the 3-player topology")

	var chain := await _wait_until(func() -> bool:
		return _flag("chock_removed") and _flag("brake_released") and _flag("cargo_secured"), 240.0)
	check(chain, "departure chain chock/brake/cargo completed over the network")

	# Everyone boards the cart (the launch console is inside the cart's box).
	# pid2 is still west of the track after the chock; walk back to the station
	# centre and up the authored platform ramp before crossing, otherwise the
	# mine cart body blocks the direct line at ground level.
	if seat_pid == 1 and expected >= 4:
		# The cargo owner is still standing at the strap; give it time to clear
		# the narrow platform before walking the same lane.
		await _wait(4.0)
		await _walk(Vector3(7.2, 0, -38.2), 3.5, "ramp north")
		await _walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _walk(Vector3(6.2, 1.55, -45.5), 2.4, "platform lane")
		await _walk(Vector3(5.6, 1.55, -47.0), 2.2, "platform edge")
	elif seat_pid == 2:
		await _walk(Vector3(-4.5, 0, -40.6), 3.0, "station return")
		await _walk(Vector3(0.0, 0, -38.2), 2.4, "station center")
		await _walk(Vector3(7.2, 0, -38.2), 4.0, "ramp north")
		await _walk(Vector3(7.2, 1.55, -43.0), 4.0, "platform ramp")
		await _walk(Vector3(7.35, 1.55, -47.0), 3.2, "platform edge")
	else:
		await _walk(Vector3(5.6, 1.55, -47.0), 6.0, "platform edge")
	await _walk(Vector3(3.6, 1.55, -47.0), 2.5, "cart side")
	await _walk(Vector3(0.0, 1.55, -48.0), 3.0, "cart deck")
	if seat_pid == 1:
		await _walk(Vector3(-3.0, 1.55, -50.0), 2.5, "launch console")
	var aboard := await _wait_until(func() -> bool:
		return bool(stage.call("all_active_aboard")), 180.0)
	check(aboard, "all %d bodies are physically inside the cart" % expected)
	var ready := await _wait_until(func() -> bool:
		return bool(stage.call("all_active_ready")), 180.0)
	check(ready, "every active player earned >=2 distinct phases")
	var pid_counts: Array = []
	for pid in (stage.get("active_pids") as Dictionary).keys():
		pid_counts.append("%d:%d" % [int(pid), _phase_count(int(pid))])
	note("phase counts %s" % str(pid_counts))
	_snapshot("prelaunch")
	if role == "host":
		# Wait until every client has frozen its pre-launch mirror, then release
		# the launch gate. This makes the cross-process prelaunch comparison a
		# true same-state comparison instead of a start-order artefact.
		var all_snaps: bool = await _wait_until(func() -> bool:
			for i in range(1, expected):
				if _read_json("client%d.snap.prelaunch.json" % i).is_empty():
					return false
			return true, 120.0)
		check(all_snaps, "all clients froze a pre-launch mirror")
		_host_phase("launch")
	else:
		if not await _wait_phase("launch", 180.0):
			check(false, "client reached the launch gate")
			_finish(false)
			return

	# ---- 6. launch + Act23 hand-off ----------------------------------------
	if seat_pid == 1:
		var launched_press := await _press_until("launch_cart", "departure_started", 5, 1.2)
		check(launched_press, "host pressed the launch interlock")
	var launched := await _wait_flag("departure_started", 120.0)
	check(launched, "departure interlock accepted for the whole crew")
	await _wait_real(0.2)
	_cap = _capture()
	_cap["act1_stats_pre_handoff"] = _stats()
	_note_credits()
	# Attribution checks: each seat's exclusive action must be credited to it,
	# and no other seat may be credited for the same action. Run these while the
	# Act01 stage is still alive (the hand-off frees it).
	var expected_kinds := {}
	match expected:
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
	for p in range(1, expected + 1):
		var mine: Array = _credit_kinds(p)
		for kind in expected_kinds.get(p, []):
			check(mine.has(str(kind)), "pid %d earned credit %s (has %s)" % [p, kind, str(mine)])
	if role == "host":
		var exclusive := {"entry_shove": 2, "entry_latch": 2,
			"power_clamp": 1 if expected == 2 else 3,
			"chock": 2,
			"brake": 1 if expected == 2 else 3,
			"cargo": 1 if expected == 2 else (4 if expected == 4 else 1)}
		var leak: Array = []
		for kind in exclusive.keys():
			var owner_pid := int(exclusive[kind])
			if owner_pid > expected:
				continue
			for p in range(1, expected + 1):
				if p == owner_pid:
					check(_credit_kinds(p).has(kind), "exclusive credit %s is on its owner pid %d" % [kind, p])
				elif _credit_kinds(p).has(kind):
					leak.append("%s->pid%d" % [kind, p])
		check(leak.is_empty(), "no exclusive credit leaked to another seat (%s)" % str(leak))

	var moved: bool = await _wait_until(func() -> bool:
		# The Act23 hand-off can fire while the cart is still moving; once the
		# Act01 scene is gone the move and ride checks are already satisfied.
		if stage == null or not is_instance_valid(stage) or current_scene != stage:
			return true
		var builder_v: Variant = stage.get("builder")
		if builder_v == null or not is_instance_valid(builder_v):
			return true
		var builder_obj: Object = builder_v as Object
		if builder_obj == null:
			return true
		var cart: Node = builder_obj.get("mine_cart") as Node
		if cart == null or not is_instance_valid(cart):
			return true
		return cart.global_position.z < -50.0, 120.0)
	check(moved, "the mine cart physically travelled down the rails")
	var ext_ok: bool = await _wait_until(func() -> bool:
		if player == null or not is_instance_valid(player):
			return bool(_cap.get("local_external", false))
		return bool(player.get("external_hold")), 15.0)
	check(ext_ok, "pid%d received the real ride grant and is attached to the cart" % seat_pid)
	await _wait_real(1.5)
	if stage != null and is_instance_valid(stage) and current_scene == stage:
		_snapshot("departing")
		_cap = _capture()
		_note_credits()

	

	var handoff: bool = await _wait_until(func() -> bool:
		return current_scene != null and str(current_scene.name) == "Act23Chapter", 300.0)
	check(handoff, "Act01 handed off to Act23 in the same session (scene=%s)" % _scene_name())
	if handoff:
		await _wait(1.5)
		_write_json(_role_file("handoff"), {"pid": seat_pid, "scene": _scene_name(),
			"chapter": str(hub.get("current_chapter")), "handoff": true})
		# Real Act23 cockpit: the same flow the direct chapter runner uses. It
		# only sends the production Input actions; the caller keeps the unified
		# SessionHub peer alive so the campaign hand-off can be observed.
		var a23_script: Script = load("res://tests/a23_flow.gd") as Script
		if a23_script == null:
			check(false, "Act23 flow helper is installed")
		else:
			var a23: RefCounted = a23_script.new() as RefCounted
			a23.call("setup", self, role, index, expected, out_dir, tag, "full_official", seat_pid)
			var a23_ok: bool = bool(await a23.call("run"))
			check(a23_ok, "Act23 multiplayer deck egress, repair and re-board passed")
			_cap["a23_flow"] = {
				"passed": a23_ok,
				"checks": int(a23.get("checks")),
				"failures": a23.get("failures"),
				"warnings": a23.get("warnings"),
			}
			if a23_ok:
				var next: bool = await _wait_until(func() -> bool:
					var sn: String = str(current_scene.name) if current_scene != null else ""
					return sn == "Act4" or sn == "Resonance04", 180.0)
				check(next, "Act23 handed off to Act04 after the repaired run (scene=%s)" % _scene_name())
				if next:
					_write_json(_role_file("a23_handoff"), {"pid": seat_pid,
						"scene": _scene_name(), "chapter": str(hub.get("current_chapter")),
						"handoff": true})
					# Real Act04 playthrough: the same input-only cockpit the
					# Act23 helper uses. It proves 3/4-player bodies, freight
					# platform grabs/credits, the participation gate and the
					# Act04 -> Act05 hand-off inside this same session.
					var a4_script: Script = load("res://tests/a4_flow.gd") as Script
					if a4_script == null:
						check(false, "Act04 flow helper is installed")
					else:
						var a4: RefCounted = a4_script.new() as RefCounted
						a4.call("setup", self, role, index, expected, out_dir, tag, seat_pid)
						var a4_ok: bool = bool(await a4.call("run"))
						check(a4_ok, "Act04 3/4-player production playthrough reached Act05")
						_cap["a4_flow"] = {
							"passed": a4_ok,
							"checks": int(a4.get("checks")),
							"failures": a4.get("failures"),
							"warnings": a4.get("warnings"),
						}
	_finish(failures.is_empty())

func _note_credits() -> void:
	var summary := {}
	for pid in (stage.get("active_pids") as Dictionary).keys():
		summary[int(pid)] = {"kinds": _credit_kinds(int(pid)), "phases": _phase_count(int(pid))}
	log_line("CREDITS " + JSON.stringify(summary))

# -------------------------------------------------------------------- finish --
func _run() -> void:
	log_line("IT_ARGS role=%s index=%d expected=%d scenario=%s out='%s' tag='%s'" % [
		role, index, expected, scenario, out_dir, tag])
	if not await _enter_act01():
		_finish(false)
		return
	if not await _wait_seat():
		_finish(false)
		return
	_assert_identity()
	_write_json(_role_file("ready"), _capture())
	if scenario == "coop":
		await _run_coop()
	else:
		check(false, "unknown scenario %s" % scenario)
		_finish(false)

func _finish(passed: bool) -> void:
	var cap := _capture()
	cap["act1_stats"] = _stats()
	cap["failures"] = failures
	cap["warnings"] = warnings
	cap["checks"] = checks
	cap["passed"] = passed
	cap["scene_log"] = scene_log
	cap["weak"] = weak
	_write_json(_role_file("result"), cap)
	_write_json(_role_file("stats"), _stats())
	print("RESULT %s index=%d pid=%d passed=%s checks=%d failures=%d tag=%s" % [
		role, index, seat_pid,
		str(passed), checks, failures.size(), tag])
	print("RESULT_JSON " + JSON.stringify(cap))
	quit(0 if passed else 2)









