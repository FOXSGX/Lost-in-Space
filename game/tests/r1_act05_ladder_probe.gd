extends SceneTree

## R1 focused ladder interaction probe (two real processes, direct Main scene).
##
## Both roles are teleported to the maintenance-ladder stand (test setup only)
## and then use real E / W. The probe records which interactable the body's E
## actually resolved to, whether the maintenance lock was claimed on the host,
## and whether the body's Y actually rose along the climb instead of being
## teleported onto the deck. The host's view of the client position is printed
## as the authoritative state-sync check.

var role: String = "host"
var tag: String = "ladder"
var out_dir: String = ""
var log_lines: Array[String] = []
var started: int = 0
var failures: int = 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--role="):
			role = s.split("=")[1]
		elif s.begins_with("--tag="):
			tag = s.split("=")[1]
		elif s.begins_with("--out="):
			out_dir = s.split("=")[1]
	started = Time.get_ticks_msec()
	_run.call_deferred()


func log_line(text: String) -> void:
	print("[%s] %s" % [role, text])
	log_lines.append(text)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _hub() -> Node:
	return root.get_node_or_null("/root/SessionHub")


func _net() -> Node:
	var hub := _hub()
	return hub.get("net") if hub != null else null


func _session() -> Node:
	var hub := _hub()
	return hub.get("session") if hub != null else null


func _connected() -> bool:
	var net := _net()
	if net == null:
		return false
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return int(net.call("peer_count")) >= 2


func _face(pos: Vector3) -> void:
	var p: Node3D = current_scene.get("player") as Node3D
	if p == null:
		return
	var d: Vector3 = pos - p.global_position
	var yaw: float = atan2(-d.x, -d.z)
	var flat: float = Vector2(d.x, d.z).length()
	var pitch: float = -atan2(d.y - 1.45, maxf(flat, 0.05))
	p.call("set_look", yaw, clampf(pitch, -1.1, 1.1))


func _press(action := "interact", hold := 0.12) -> void:
	Input.action_press(action)
	await _wait(hold)
	Input.action_release(action)
	await _wait(0.35)


func _state(label: String) -> void:
	var game := current_scene
	var p: Node3D = game.get("player") as Node3D
	var session := _session()
	var target_name: String = "null"
	var t: Variant = p.get("operate_target")
	if t is Node and is_instance_valid(t):
		target_name = str((t as Node).name)
	var host_view: String = "n/a"
	if session != null:
		var st: Dictionary = session.call("player_state", 2)
		if not st.is_empty():
			host_view = str(st.get("pos", Vector3.ZERO))
	log_line("%s y=%.2f op=%s target=%s machine=%s grabbing=%s ext_hold=%s catwalk_claim=%d host_view_p2=%s" % [
		label, p.global_position.y, str(bool(p.get("operating"))), target_name,
		str(session.get("local_operating_machine") if session != null else "?"),
		str(bool(p.get("grabbing"))), str(bool(p.get("external_hold"))),
		int(session.call("claim_owner", "catwalk_lock")) if session != null else -1,
		host_view])


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 600:
		await process_frame
		guard += 1
	await _wait(1.5)
	var game := current_scene
	if game == null or str(game.name) != "Main":
		log_line("FAIL wrong scene")
		_finish()
		return
	for _i in range(240):
		if _connected():
			break
		await _wait(0.25)
	if not _connected():
		log_line("FAIL no peer link")
		_finish()
		return
	var level: Node = game.get("level")
	var session := _session()
	var player: Node3D = game.get("player") as Node3D
	var catwalk: Node = level.get("catwalk")
	var station: Node3D = catwalk.get("ladder_station_node") as Node3D
	# Test setup: place the body at the real ladder stand, facing the ladder.
	var stand: Vector3 = Vector3(station.global_position.x, 0.06, station.global_position.z + 0.9)
	player.call("teleport", stand, 0.0)
	await _wait(0.5)
	_face(Vector3(station.global_position.x, 1.3, station.global_position.z - 1.2))
	await _wait(0.3)
	_state("BEFORE_E")
	await _press()
	_state("AFTER_E")
	var target_name: String = ""
	var t: Variant = player.get("operate_target")
	if t is Node and is_instance_valid(t):
		target_name = str((t as Node).name)
	var opened_lock: bool = str(session.get("local_operating_machine")) == "catwalk_lock"
	var y_before: float = player.global_position.y
	if opened_lock:
		failures += 1
		log_line("FAIL aiming at the ladder started the maintenance lock (machine=catwalk_lock)")
	# If the wrong station opened, close it before the climb so the climb is
	# still observable; this is test cleanup, not a pass.
	if bool(player.get("operating")):
		await _press()
		_state("AFTER_CLEANUP")
	# Real climb attempt: E at the ladder, then hold W.
	_face(Vector3(station.global_position.x, 1.3, station.global_position.z - 1.2))
	await _press()
	_state("CLIMB_START")
	var y0: float = player.global_position.y
	Input.action_press("move_forward")
	var climbed := false
	var elapsed := 0.0
	while elapsed < 8.0:
		await _wait(0.2)
		elapsed += 0.2
		if bool(player.get("operating")) and player.global_position.y > 3.2:
			climbed = true
			break
	Input.action_release("move_forward")
	await _wait(0.3)
	_state("CLIMB_END")
	var y1: float = player.global_position.y
	if role == "host":
		# Authoritative view of the client: the host's mirrored client body
		# position (fed by the client's 20 Hz state stream). Wait one state
		# interval so the final landing packet is included instead of reading
		# a mid-climb sample.
		await _wait(0.8)
		var st: Dictionary = session.call("player_state", 2)
		var host_y: float = float((st.get("pos", Vector3.ZERO) as Vector3).y) if not st.is_empty() else -99.0
		log_line("HOST_ASSERT pid2_host_y=%.2f (client local y=%.2f)" % [host_y, y1])
		if host_y < 3.0:
			failures += 1
			log_line("FAIL host never saw the client climb above the deck (y=%.2f)" % host_y)
		if opened_lock:
			log_line("HOST_ASSERT catwalk_lock claim from client=%d" % int(session.call("claim_owner", "catwalk_lock")))
		log_line("HOST_ASSERT deck_pins=%d preload=%.2f" % [
			int(catwalk.get("pins_seated")), float(catwalk.get("preload_state"))])
	else:
		log_line("CLIENT_ASSERT climbed=%s y_before=%.2f y_now=%.2f y0=%.2f target=%s" % [
			str(climbed), y_before, y1, y0, target_name])
		if not climbed or y1 < 3.0:
			failures += 1
			log_line("FAIL client did not really climb the maintenance ladder")
	if bool(player.get("operating")):
		await _press()
	_finish()


func _finish() -> void:
	var payload := {
		"probe": "r1_act05_ladder_probe.gd",
		"role": role,
		"tag": tag,
		"failures": failures,
		"elapsed_seconds": float(Time.get_ticks_msec() - started) / 1000.0,
		"log": log_lines,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("ladder_%s_%s.json" % [role, tag]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(payload, "  "))
			f.close()
	quit(0 if failures == 0 else 1)
