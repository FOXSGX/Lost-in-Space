extends SceneTree

## R1 focused Act05 west-leg reproduction (two real processes, direct Main scene).
##
## Root-cause probe, not acceptance: both bodies are teleported next to their
## console so only the claim/axis/latch chain is under test. Every interaction
## (E to claim, W to pump) is real input. The host prints its authoritative view
## of both legs, the claim owner and the streamed remote axis every 250 ms; the
## client prints only its own local mirror. A host-side latch is the only result
## counted as proof.

var role: String = "host"
var tag: String = "r1"
var out_dir: String = ""
var log_lines: Array[String] = []
var started: int = 0
var failures: int = 0
var legacy: bool = false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--role="):
			role = s.split("=")[1]
		elif s.begins_with("--tag="):
			tag = s.split("=")[1]
		elif s.begins_with("--out="):
			out_dir = s.split("=")[1]
		elif s == "--legacy":
			legacy = true
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
	await _wait(0.3)


func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)
	await _wait(0.2)


func _state_line(stab_index: int) -> String:
	var game := current_scene
	if game == null:
		return "no-scene"
	var level: Node = game.get("level")
	var session := _session()
	if level == null or session == null:
		return "no-level"
	var stabs: Array = level.get("stabilizers") as Array
	var stab: Object = stabs[stab_index] as Object
	var axis: float = float((session.get("remote_axes") as Dictionary).get("stabilizer_w", -99.0))
	return "STAB t=%.1f idx=%d ext=%.3f press=%.3f latched=%s owner=%d remote_w=%.2f claimed_by=%d op=%s loc_machine=%s pos=%s" % [
		float(Time.get_ticks_msec() - started) / 1000.0, stab_index,
		float(stab.get("extension")), float(stab.get("pressure")), str(bool(stab.get("latched"))),
		int(session.call("claim_owner", "stabilizer_w")), axis,
		int(session.call("claim_owner", "stabilizer_e")),
		str(bool((game.get("player") as Object).get("operating"))),
		str(session.get("local_operating_machine")),
		str((game.get("player") as Node3D).global_position.snapped(Vector3(0.01, 0.01, 0.01)))]


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 600:
		await process_frame
		guard += 1
	await _wait(1.5)
	var game := current_scene
	if game == null or str(game.name) != "Main":
		log_line("FAIL wrong scene %s" % (str(game.name) if game != null else "null"))
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
	log_line("LINK peers=%s mode=%s" % [
		str(int(_net().call("peer_count"))), str(game.get("mode"))])
	await _wait(1.0)
	var level: Node = game.get("level")
	var session := _session()
	var player: Node3D = game.get("player") as Node3D
	var stabs: Array = level.get("stabilizers") as Array
	var index: int = 0 if role == "client" else 1
	var stab: Object = stabs[index] as Object
	var area: Node3D = stab.get("area") as Node3D
	var center: Vector3 = area.global_position
	var rig_basis: Basis = (stab as Node3D).global_transform.basis
	var stand: Vector3 = center + rig_basis.z * 1.25
	stand.y = 0.06
	player.call("teleport", stand, 0.0)
	await _wait(0.6)
	_face(center)
	await _wait(0.3)
	# Real E to claim/operate.
	await _press()
	var operating: bool = bool(player.get("operating"))
	log_line("E_RESULT operating=%s machine=%s claim_owner=%d" % [
		str(operating), str(session.get("local_operating_machine")),
		int(session.call("claim_owner", "stabilizer_w" if role == "client" else "stabilizer_e"))])
	# Print both legs before pumping: host sees claim owner; client sees mirror.
	log_line(_state_line(0))
	log_line(_state_line(1))
	# Real W pump, sampled. `--legacy` reproduces the R8C-04 one-shot 6 s hold
	# exactly; the default keeps pumping so a surge cannot be confused with a
	# broken input path.
	var elapsed := 0.0
	if legacy:
		Input.action_press("move_forward")
		while elapsed < 6.0:
			await _wait(0.25)
			elapsed += 0.25
			log_line(_state_line(index))
		Input.action_release("move_forward")
		await _wait(1.2)
	else:
		Input.action_press("move_forward")
		while elapsed < 10.0:
			await _wait(0.25)
			elapsed += 0.25
			log_line(_state_line(index))
		Input.action_release("move_forward")
	await _wait(0.4)
	log_line("AFTER_PUMP")
	log_line(_state_line(0))
	log_line(_state_line(1))
	# Let snapshots settle, then read the authoritative latched flag again.
	await _wait(1.5)
	log_line("SETTLED")
	log_line(_state_line(0))
	log_line(_state_line(1))
	# Stop operating so the claim is released and the world is clean.
	await _press()
	await _wait(0.5)
	log_line("RELEASED owner_w=%d owner_e=%d" % [
		int(session.call("claim_owner", "stabilizer_w")),
		int(session.call("claim_owner", "stabilizer_e"))])
	var latched_w: bool = bool((stabs[0] as Object).get("latched"))
	var latched_e: bool = bool((stabs[1] as Object).get("latched"))
	if role == "host":
		# Authority view: the host statement is the only proof.
		var p2_has: bool = bool((session.get("ledger") as Object).call("has_credit", 2, "stabilizer_lock"))
		log_line("HOST_AUTHORITY west_latched=%s east_latched=%s pid2_credit=%s ledger=%s" % [
			str(latched_w), str(latched_e), str(p2_has),
			JSON.stringify((session.get("ledger") as Object).call("snapshot"))])
		if not latched_w:
			failures += 1
			log_line("FAIL host authoritative west leg did not latch")
		if not p2_has:
			failures += 1
			log_line("FAIL host ledger has no pid2 stabilizer_lock credit")
	_finish()


func _finish() -> void:
	var payload := {
		"probe": "r1_act05_stab_probe.gd",
		"role": role,
		"tag": tag,
		"failures": failures,
		"elapsed_seconds": float(Time.get_ticks_msec() - started) / 1000.0,
		"log": log_lines,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("stab_%s_%s.json" % [role, tag]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(payload, "  "))
			f.close()
	quit(0 if failures == 0 else 1)
