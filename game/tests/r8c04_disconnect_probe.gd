extends SceneTree

## R8C-04 regression: a client disconnects during Act04.
## `--after=none` : it leaves with no action; the host must not auto-credit it.
## `--after=strike`: it earns a real phase-04 credit, then leaves; the host must
##                   preserve that credit and mark the player disconnected.
## In both cases the surviving host may pass the exit gate (active pids only).

var role: String = "host"
var tag: String = "disconnect"
var out_dir: String = ""
var after: String = "none"

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
		elif s.begins_with("--after="):
			after = s.split("=")[1]
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


func _row(pid: int) -> Dictionary:
	for row in _ledger_rows():
		if int(row["pid"]) == pid:
			return row
	return {}


func _strike() -> bool:
	var game := current_scene
	if game == null:
		return false
	var player: Node = game.get("player") as Node
	var hammer: Node = game.get("hammer") as Node
	if player == null or hammer == null:
		return false
	player.call("teleport", Vector3(2.25, 0.2, -0.4), 0.0)
	await _wait(0.4)
	player.call("aim_camera_at", Vector3(2.25, 1.2, -4.5), -0.08)
	await _wait(0.3)
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	await _wait(0.4)
	if str(hammer.get("mode")) != "held":
		return false
	Input.action_press("move_forward")
	await _wait(1.45)
	Input.action_release("move_forward")
	await _wait(0.2)
	var before := int(hammer.get("strike_count"))
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	for _i in range(50):
		await _wait(0.1)
		if int(hammer.get("strike_count")) > before:
			return true
	return false


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
	game.set_meta("suppress_act5", true)
	var gate: Node = game.get("gate") as Node
	game.get("seen_memories")[1] = true
	game.get("seen_memories")[2] = true
	game.get("seen_memories")[3] = true
	if gate != null and not bool(gate.get("is_open")):
		gate.call("open")
		for _i in range(80):
			await _wait(0.1)
			if bool(gate.get("is_open")):
				break
	for _i in range(240):
		if _peer_ready():
			break
		await _wait(0.25)
	if role == "host":
		await _wait(4.0)
		var struck := await _strike()
		log_line("HOST strike=%s ledger=%s" % [str(struck), JSON.stringify(_ledger_rows())])
		# Wait until the client process has definitely disconnected.
		var p2: Dictionary = {}
		for _i in range(80):
			await _wait(0.25)
			p2 = _row(2)
			if str(p2.get("status", "")) == "disconnected":
				break
		log_line("HOST after_disconnect pid2=%s ledger=%s" % [
			JSON.stringify(p2), JSON.stringify(_ledger_rows())])
		var ok_p2_status: bool = str(p2.get("status", "")) == "disconnected"
		var has04: bool = (p2.get("phases", {}) as Dictionary).has("04")
		# before: the departed player must NOT be credited; after: the credit it
		# really earned must survive the disconnect.
		var credit_ok: bool = has04 if after == "strike" else not has04
		log_line("ASSERT pid2 disconnected=%s has04=%s expected=%s" % [
			str(ok_p2_status), str(has04), str(after == "strike")])
		game.call("_on_exit_entered")
		await _wait(0.5)
		var completed := bool(game.get("completed"))
		log_line("HOST gate_after_disconnect completed=%s" % str(completed))
		if ok_p2_status and credit_ok and completed:
			if after == "strike":
				log_line("PASS disconnected client kept its real credit; surviving host passed")
			else:
				log_line("PASS disconnected client was not auto-marked; surviving host passed")
		else:
			log_line("FAIL disconnect handling")
		_finish()
	else:
		if after == "strike":
			# Do one real Act04 action, then leave.
			await _wait(4.0)
			var struck := await _strike()
			log_line("CLIENT struck before leaving: %s" % str(struck))
			await _wait(2.0)
			log_line("CLIENT leaves after earning a real phase-04 credit")
		else:
			# This client does no Act04 action at all and then leaves.
			await _wait(5.0)
			log_line("CLIENT leaves without an Act04 action")
		_finish()


func _finish() -> void:
	var payload := {
		"probe": "r8c04_disconnect_probe.gd",
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
