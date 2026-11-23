extends Node

## Two-process co-op smoke / full-act attempt for the Act 01 MODULE.
## Launched by Act1App when --autotest is present. It survives the Act 01 ->
## handoff because it lives under /root rather than under the level.
##
## Adapted from the Act01 V2 `act01_autotest.gd`:
## * types renamed (Act1Interactable / Act1StationPlayer)
## * Q-let-go uses the module action `act1_cancel`
## * the final scene handoff check now asserts the Act1SessionBridge recorded the
##   Act01 completion instead of reaching a local fake "act02_ride" scene.

var stage: Node3D
var player: Act1StationPlayer
var failures: Array[String] = []
var lines: Array[String] = []
var role := ""
var result_flags: Dictionary = {}
var result_credits: Dictionary = {}
## `Act1SessionBridge` held independently of the level. The departure handoff
## frees the Act01 scene, so `stage.bridge` becomes an access on a freed object
## exactly when the completion is read. The bridge itself is a RefCounted owned
## by the session (integrated) or by this reference (standalone), so keeping it
## here lets the completion check survive the handoff without weakening it.
var bridge: Object = null


func _ready() -> void:
	call_deferred("_run")


func log_line(text: String) -> void:
	var prefix := role.to_upper()
	print("%s %s" % [prefix, text])
	lines.append(text)


func check(ok: bool, text: String) -> void:
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)


func args_has(prefix: String) -> String:
	for a in OS.get_cmdline_args():
		if str(a).begins_with(prefix):
			return str(a).substr(prefix.length())
	return ""


func _run() -> void:
	role = args_has("--role=")
	if role == "":
		role = "coop_host" if "--host" in OS.get_cmdline_args() else "coop_client"
	while stage == null:
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	player = stage.local_player
	log_line("start mode=%s pid=%d pos=%s" % [stage.net.mode, stage.local_pid, str(player.global_position)])
	if role == "coop_host":
		await _run_host()
	elif role == "rescue_host":
		await _run_rescue_host()
	elif role == "rescue_client":
		await _run_rescue_client()
	else:
		await _run_client()


func _face(target: Vector3) -> void:
	var d := target - player.global_position
	player.yaw = atan2(-d.x, -d.z)
	player.rotation.y = player.yaw


func _walk(target: Vector3, seconds: float, label := "") -> void:
	_face(target)
	Input.action_press("move_forward")
	for i in range(int(seconds * 60.0)):
		await get_tree().physics_frame
		_face(target)
		if Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < 0.55:
			break
	Input.action_release("move_forward")
	await get_tree().physics_frame
	log_line("WALK %s pos=%s" % [label, str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])


func _press(id: String, hold := 0.14) -> bool:
	if not stage.interactables.has(id):
		check(false, "missing interactable " + id)
		return false
	var point: Act1Interactable = stage.interactables[id]
	player.look_at_point(point.global_position)
	await get_tree().create_timer(0.25).timeout
	var found := "none"
	if player.current_target != null:
		found = str(player.current_target.get("interaction_id"))
	log_line("AIM %s -> %s dist=%.2f" % [id, found, player.global_position.distance_to(point.global_position)])
	if found != id:
		return false
	Input.action_press("interact")
	await get_tree().create_timer(hold).timeout
	Input.action_release("interact")
	await get_tree().create_timer(0.6).timeout
	return true


func _hold(id: String, seconds: float) -> bool:
	var point: Act1Interactable = stage.interactables[id]
	player.look_at_point(point.global_position)
	await get_tree().create_timer(0.25).timeout
	var found := "none"
	if player.current_target != null:
		found = str(player.current_target.get("interaction_id"))
	log_line("HOLD %s -> %s" % [id, found])
	if found != id:
		return false
	Input.action_press("interact")
	for i in range(int(seconds * 60.0)):
		await get_tree().physics_frame
	Input.action_release("interact")
	await get_tree().create_timer(0.4).timeout
	return true


func _wait_flag(key: String, seconds: float) -> bool:
	for i in range(int(seconds * 2.0)):
		if bool(stage.flags.get(key, false)):
			return true
		await get_tree().create_timer(0.5).timeout
	return bool(stage.flags.get(key, false))


func _wait_peers(seconds: float) -> bool:
	var host_roles := ["coop_host", "rescue_host"]
	var expected_pid := 1 if role in host_roles else 2
	for i in range(int(seconds * 2.0)):
		if stage.net != null and stage.net.peer_count() > 1 and stage.local_pid == expected_pid:
			return true
		await get_tree().create_timer(0.5).timeout
	return false


func _run_host() -> void:
	var connected := await _wait_peers(40.0)
	check(connected, "host sees a second peer")
	# Wait for the client to clear the entry physically.
	var door := await _wait_flag("door_open", 150.0)
	check(door, "client opened the entry door")
	await _walk(Vector3(0, 0, 12.0), 3.0, "door approach")
	# the cleared gantry sits to the west of the opening; step around its actual
	# visible mass rather than walking through the centre line
	await _walk(Vector3(1.35, 0, 10.2), 2.0, "door east side")
	await _walk(Vector3(1.35, 0, 7.2), 2.2, "through door east side")
	await _walk(Vector3(0, 0, 4.0), 1.6, "airlock exit")
	await _walk(Vector3(-3.0, 0, 0.4), 2.5, "power room")
	await _walk(Vector3(-7.8, 0, 0.4), 3.0, "power north")
	await _walk(Vector3(-8.0, 0, -2.5), 1.7, "cart rear")
	await _press("cart_push", 0.12)
	check(player.external_hold, "host gripped trolley")
	Input.action_press("move_forward")
	for i in range(150):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	await get_tree().create_timer(0.4).timeout
	Input.action_press("act1_cancel")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("act1_cancel")
	await get_tree().create_timer(0.4).timeout
	await _walk(Vector3(-4.6, 0, -0.4), 2.4, "around cart")
	await _walk(Vector3(-1.0, 0, -0.5), 3.0, "bracket")
	await _walk(Vector3(-0.95, 0, -1.15), 1.2, "bracket close")
	await _press("rail_shove", 0.10)
	check(bool(stage.flags["rail_cleared"]), "host cleared rail bracket")
	await _walk(Vector3(-1.0, 0, -0.4), 1.8, "return")
	await _walk(Vector3(-7.8, 0, -0.4), 3.2, "cart rear north")
	await _walk(Vector3(-7.8, 0, -2.5), 1.3, "cart rear center")
	await _walk(Vector3(-7.2, 0, -2.5), 0.8, "cart handle")
	await _press("cart_push", 0.12)
	check(player.external_hold, "host regripped trolley")
	Input.action_press("move_forward")
	for i in range(520):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	await get_tree().create_timer(1.1).timeout
	Input.action_press("act1_cancel")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("act1_cancel")
	await get_tree().create_timer(0.4).timeout
	check(stage.builder.power_cart.docked, "host docked the trolley")
	await _walk(Vector3(1.5, 0, -0.5), 1.8, "cart west north")
	await _walk(Vector3(1.5, 0, -5.0), 2.4, "socket west")
	await _walk(Vector3(1.95, 0, -5.0), 0.8, "winch")
	await _press("power_winch", 0.12)
	await get_tree().create_timer(2.5).timeout
	await _walk(Vector3(2.4, 0, -4.3), 1.2, "clamp")
	await _press("power_clamp", 0.12)
	check(bool(stage.flags["power_ready"]), "host restored auxiliary power")
	# ventilation
	await _walk(Vector3(0, 0, -8.0), 2.5, "power exit")
	await _walk(Vector3(-1.0, 0, -14.2), 3.5, "vent hall")
	await _walk(Vector3(7.0, 0, -14.8), 4.0, "hall east north")
	await _walk(Vector3(7.0, 0, -17.5), 2.0, "hall east")
	await _walk(Vector3(7.7, 0, -22.3), 2.5, "rotor lock")
	await _press("rotor_lock", 0.12)
	await _walk(Vector3(8.1, 0, -28.15), 3.8, "coupling")
	await _press("coupling", 0.12)
	await _walk(Vector3(7.0, 0, -14.8), 4.8, "return north")
	await _walk(Vector3(-7.8, 0, -14.8), 7.0, "control north")
	await _walk(Vector3(-7.8, 0, -18.0), 1.8, "control")
	await _walk(Vector3(-7.8, 0, -23.0), 2.4, "start fan")
	await _press("start_fan", 0.12)
	check(stage.builder.vent.running, "host started fan")
	await _walk(Vector3(-7.8, 0, -14.8), 3.0, "west gallery north")
	await _walk(Vector3(7.0, 0, -14.8), 7.0, "damper north")
	await _walk(Vector3(7.0, 0, -18.0), 1.8, "damper side")
	await _walk(Vector3(8.0, 0, -29.6), 5.0, "damper")
	await _press("damper", 0.12)
	await _walk(Vector3(8.0, 0, -34.0), 3.0, "safe south")
	var vent_ok := await _wait_flag("vent_complete", 30.0)
	check(vent_ok, "host completed live pressure test")
	# station prep (client removes chock)
	await _walk(Vector3(7.0, 0, -35.4), 2.5, "hall south")
	await _walk(Vector3(0.0, 0, -35.6), 4.0, "hall center")
	await _walk(Vector3(0.0, 0, -37.6), 2.4, "station threshold")
	await _walk(Vector3(4.0, 0, -38.2), 3.0, "station east")
	await _walk(Vector3(7.2, 0, -38.2), 2.4, "ramp north")
	await _walk(Vector3(7.2, 1.55, -43.0), 3.5, "platform")
	# The parking brake interlock requires the chock to be removed first. The
	# client owns that job, so the host waits on the platform instead of pressing
	# a refused brake and cascading failures.
	var chock_ok := await _wait_flag("chock_removed", 120.0)
	check(chock_ok, "client removed wheel chock")
	await _walk(Vector3(7.35, 1.55, -48.2), 3.0, "brake side")
	await _walk(Vector3(6.55, 1.55, -48.6), 1.2, "brake")
	await _press("parking_brake", 0.12)
	log_line("FLAGS after brake: brake=%s cargo=%s" % [str(stage.flags["brake_released"]), str(stage.flags["cargo_secured"])])
	# MECHANICS-001F：货舱固定带现在是矿车货台上的真实棘轮，要摇多档才达到工作张力
	await _walk(Vector3(6.55, 1.55, -46.2), 2.0, "cargo side")
	await _walk(Vector3(5.35, 1.55, -47.05), 1.6, "cargo ratchet")
	for n in range(10):
		if bool(stage.flags["cargo_secured"]):
			break
		await _press("cargo", 0.12)
		await get_tree().create_timer(0.6).timeout
	log_line("FLAGS after cargo: brake=%s cargo=%s" % [str(stage.flags["brake_released"]), str(stage.flags["cargo_secured"])])
	check(bool(stage.flags["brake_released"]) and bool(stage.flags["cargo_secured"]), "host prepared brake and cargo")
	# board and wait for client（绕开真实货箱：它是 100 kg 实体，撞不动）
	await _walk(Vector3(5.35, 1.55, -48.30), 2.0, "platform edge aft")
	await _walk(Vector3(4.05, 1.55, -48.40), 1.8, "cart entry")
	await _walk(Vector3(2.10, 1.55, -48.65), 1.8, "around cargo")
	await _walk(Vector3(0.0, 1.55, -49.30), 1.8, "cart deck")
	await _walk(Vector3(-3.0, 1.55, -50.0), 2.6, "launch console")
	var aboard := false
	for i in range(80):
		aboard = stage.all_active_aboard()
		if aboard:
			break
		await get_tree().create_timer(0.5).timeout
	check(aboard, "both players physically aboard")
	if aboard:
		await _press("launch_cart", 0.12)
	check(bool(stage.flags["departure_started"]), "host launch interlock accepted")
	await save_and_wait()


func _run_client() -> void:
	var connected := await _wait_peers(40.0)
	check(connected, "client connected and received pid 2")
	await _walk(Vector3(0, 0, 12.0), 3.0, "entry approach")
	await _walk(Vector3(0, 0, 10.6), 1.8, "door rail")
	for i in range(4):
		await _press("shove_gantry", 0.10)
		await get_tree().create_timer(0.8).timeout
		if bool(stage.flags["debris_cleared"]):
			break
	check(bool(stage.flags["debris_cleared"]), "client cleared the gantry")
	await _walk(Vector3(3.1, 0, 10.35), 2.2, "latch side")
	await _press("release_latch", 0.12)
	check(bool(stage.flags["latch_released"]), "client released latch")
	await _walk(Vector3(1.0, 0, 10.0), 1.6, "door front")
	await _hold("door_handle", 6.2)
	check(bool(stage.flags["door_open"]), "client opened door")
	await _walk(Vector3(0, 0, 6.5), 2.5, "through door")
	await _walk(Vector3(0, 0, 4.0), 2.0, "waiting area")
	var vent_ok := await _wait_flag("vent_complete", 180.0)
	check(vent_ok, "client received ventilation completion")
	if not vent_ok:
		await save_and_wait()
		return
	await _walk(Vector3(0.0, 0, -8.0), 3.0, "power exit")
	await _walk(Vector3(-1.0, 0, -14.2), 3.5, "vent hall")
	await _walk(Vector3(7.0, 0, -14.8), 4.5, "hall east north")
	await _walk(Vector3(7.0, 0, -18.0), 2.0, "hall east")
	await _walk(Vector3(7.0, 0, -35.6), 7.0, "hall south east")
	await _walk(Vector3(0.0, 0, -35.6), 4.0, "hall south")
	await _walk(Vector3(0.0, 0, -37.6), 2.4, "station")
	await _walk(Vector3(-5.6, 0, -40.5), 3.5, "station west")
	await _walk(Vector3(-5.6, 0, -44.3), 2.5, "chock approach")
	await _walk(Vector3(-5.62, 0, -45.5), 1.4, "chock")
	await _press("chock", 0.12)
	check(bool(stage.flags["chock_removed"]), "client removed wheel chock")
	await _walk(Vector3(-4.5, 0, -40.6), 2.4, "station return")
	await _walk(Vector3(0.0, 0, -38.2), 2.0, "station center")
	await _walk(Vector3(7.2, 0, -38.2), 3.5, "ramp north")
	await _walk(Vector3(7.2, 1.55, -43.0), 3.5, "platform")
	await _walk(Vector3(7.35, 1.55, -47.0), 3.0, "platform edge")
	await _walk(Vector3(5.6, 1.55, -47.0), 2.0, "cart edge")
	await _walk(Vector3(3.6, 1.55, -47.0), 2.0, "cart side")
	await _walk(Vector3(0.0, 1.55, -48.0), 2.5, "cart deck")
	check(stage.builder.mine_cart.is_player_aboard(player.global_position), "client physically inside cart")
	await save_and_wait()


func _run_rescue_host() -> void:
	var connected := await _wait_peers(40.0)
	check(connected, "rescue host sees the client")
	stage.flags["fan_started"] = true
	stage.flags["damper_open"] = true
	stage.builder.vent.set_running(true)
	stage.builder.vent.set_governor(1.0)
	stage.builder.vent.set_damper_target(1.0)
	await get_tree().create_timer(2.5).timeout
	player.teleport(Vector3(1.45, 3.55, -21.1), 0.0, -0.1)
	var downed := false
	for i in range(40):
		var st: Dictionary = stage.remote_states.get(2, {})
		if bool(st.get("downed", false)) and (st.get("pos", Vector3.ZERO) as Vector3).y < -0.5:
			downed = true
			break
		await get_tree().create_timer(0.5).timeout
	check(downed, "client was physically blown off the catwalk")
	var pressed := await _press("rescue_winch", 0.12)
	check(pressed, "host operated the rescue winch")
	var rescued := false
	for i in range(20):
		var st: Dictionary = stage.remote_states.get(2, {})
		if (st.get("pos", Vector3.ZERO) as Vector3).y > 3.0 and not bool(st.get("downed", true)):
			rescued = true
			break
		await get_tree().create_timer(0.5).timeout
	check(rescued, "client body returned to the catwalk")
	await get_tree().create_timer(1.0).timeout
	result_flags = stage.flags.duplicate(true)
	result_credits = stage._credits_snapshot()
	var report := {"role": role, "passed": failures.is_empty(), "failures": failures, "flags": result_flags, "credits": result_credits, "log": lines}
	var path := ProjectSettings.globalize_path("res://../tests-out/%s.json" % role)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	log_line("RESULT passed=%s failures=%d" % [str(failures.is_empty()), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _run_rescue_client() -> void:
	var connected := await _wait_peers(40.0)
	check(connected, "rescue client connected")
	for i in range(24):
		if stage.builder.vent.speed > 0.5:
			break
		await get_tree().create_timer(0.5).timeout
	player.teleport(Vector3(2.3, 3.55, -29.0), 0.0, -0.1)
	var fell := false
	for i in range(30):
		if player.downed and player.global_position.y < -0.5:
			fell = true
			break
		await get_tree().create_timer(0.3).timeout
	check(fell, "client fell into the lower maintenance pit")
	var rescued := false
	if fell:
		for i in range(30):
			if not player.downed and player.global_position.y > 3.0:
				rescued = true
				break
			await get_tree().create_timer(0.3).timeout
	check(rescued, "client was lifted back to the catwalk by the host winch")
	# Let the host observe the recovered state and release the network link before
	# this process exits; otherwise the host can miss the final snapshot.
	await get_tree().create_timer(2.5).timeout
	var report := {"role": role, "passed": failures.is_empty(), "failures": failures, "pos": [player.global_position.x, player.global_position.y, player.global_position.z], "downed": player.downed, "log": lines}
	var path := ProjectSettings.globalize_path("res://../tests-out/%s.json" % role)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	log_line("RESULT passed=%s failures=%d" % [str(failures.is_empty()), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func save_and_wait() -> void:
	if stage != null and is_instance_valid(stage):
		result_flags = stage.flags.duplicate(true)
		result_credits = stage._credits_snapshot()
		if bridge == null:
			bridge = stage.bridge
	# The stage is freed by the Act01 -> Act02 handoff, so read the completion
	# through the bridge that was captured while the level was still alive. A
	# missing bridge is a real failure, not a forced pass: it can only happen if
	# Act01 never built one, in which case no completion could have been recorded.
	if bridge == null:
		check(false, "session bridge was available before the handoff")
	var completion_ok := false
	for i in range(40):
		if bridge != null and bridge.has_method("recorded_completion"):
			var rec: Dictionary = bridge.call("recorded_completion")
			if bool(rec.get("completed", false)):
				completion_ok = true
				break
		await get_tree().create_timer(0.5).timeout
	check(completion_ok, "Act01 completion recorded through the session bridge")
	var report := {
		"role": role,
		"passed": failures.is_empty() and completion_ok,
		"failures": failures,
		"flags": result_flags,
		"credits": result_credits,
		"completion_ok": completion_ok,
		"log": lines,
	}
	var path := ProjectSettings.globalize_path("res://../tests-out/%s.json" % role)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	log_line("RESULT passed=%s failures=%d" % [str(report["passed"]), failures.size()])
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if report["passed"] else 1)