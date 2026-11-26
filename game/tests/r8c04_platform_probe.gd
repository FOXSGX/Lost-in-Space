extends SceneTree

## R8C-04 focused probe: does a real client platform-drive action earn phase-04
## on the host authority? This is the second Act04 participation channel; the
## bell is covered by r8c04_gate_probe.gd.

var role: String = "host"
var tag: String = "platform"
var out_dir: String = ""

var log_lines: Array[String] = []
var started: int = 0


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


func _peer_ready() -> bool:
	var net := _net()
	if net == null:
		return false
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return int(net.call("peer_count")) >= 2


func _ledger_rows() -> Array:
	var out: Array = []
	var session := _session()
	if session == null:
		return out
	var led = session.get("ledger")
	if led == null:
		return out
	for pid in led.call("player_ids"):
		var rec: Dictionary = led.call("get_record", int(pid))
		out.append({
			"pid": int(pid),
			"status": str(led.call("status_of", int(pid))),
			"phases": (rec.get("phases", {}) as Dictionary).duplicate(true),
			"kinds": (rec.get("credits", {}) as Dictionary).keys(),
		})
	return out


func _log_ledger(label: String) -> void:
	log_line("LEDGER %s %s" % [label, JSON.stringify(_ledger_rows())])


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 600:
		await process_frame
		guard += 1
	await _wait(1.5)
	var game := current_scene
	if game == null or str(game.name) not in ["Act4", "Resonance04"]:
		log_line("FAIL wrong scene")
		_finish()
		return
	var player: Node = game.get("player") as Node
	var platform: Node = game.get("platform") as Node
	if player == null or platform == null:
		log_line("FAIL missing player/platform")
		_finish()
		return
	# Mirror the real launcher roster: the host pid 1 must exist in the ledger.
	var session := _session()
	if session != null and role == "host" and not session.get("ledger").call("get_record", 1).size() > 0:
		session.call("add_player", 1, "七号", true)
	for _i in range(240):
		if _peer_ready():
			break
		await _wait(0.25)
	await _wait(2.0)
	log_line("LINK peers=%s coop=%s" % [
		str(int(_net().call("peer_count")) if _net() != null else -1), str(game.get("coop_mode"))])
	_log_ledger("begin")
	if role == "client":
		player.call("teleport", Vector3(-8.6, 2.66, 2.6), 0.0)
		await _wait(0.5)
		var console_pos: Vector3 = platform.call("to_global", Vector3(-1.02, 1.10, -0.50))
		player.call("aim_camera_at", console_pos, -99.0)
		await _wait(0.5)
		var owner_ok := false
		for _i in range(10):
			Input.action_press("interact")
			await _wait(0.12)
			Input.action_release("interact")
			await _wait(0.4)
			if int(platform.get("control_owner_id")) == 2:
				owner_ok = true
				break
		log_line("CLIENT control_owner=%d grabbed=%s" % [int(platform.get("control_owner_id")), str(owner_ok)])
		if owner_ok:
			var x0 := float(platform.get("travel_x"))
			Input.action_press("move_back")
			await _wait(6.0)
			Input.action_release("move_back")
			await _wait(1.0)
			log_line("CLIENT platform_x %.2f -> %.2f" % [x0, float(platform.get("travel_x"))])
		await _wait(3.0)
		_log_ledger("client_after")
		_finish()
	else:
		# Host waits for the client's drive, then reports the authoritative ledger.
		await _wait(18.0)
		_log_ledger("host_after")
		_finish()


func _finish() -> void:
	var payload := {
		"probe": "r8c04_platform_probe.gd",
		"role": role,
		"tag": tag,
		"elapsed_seconds": float(Time.get_ticks_msec() - started) / 1000.0,
		"ledger": _ledger_rows(),
		"log": log_lines,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("probe_%s_%s.json" % [role, tag]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(payload, "  "))
			f.close()
			log_line("REPORT %s" % out_dir.path_join("probe_%s_%s.json" % [role, tag]))
	quit(0)
