extends SceneTree

## Task 7 focused exit-gate probe (two real processes, direct Act 4 scene).
##
## Adapted from R8C-04's probe for the main-p0-2 integration candidate:
##   * player.teleport() setup removed; the host/client now WALK to the hammer
##     console with real camera-relative movement (same path as R2's probe).
##   * host waits for its real phase-04 ledger credit before the negative gate
##     attempt, and for the client's real credit before the positive attempt;
##     no fixed-time race.
##
## Timeline (seconds after both peers are linked):
##   t=4.0   host walks to the console and strikes (host earns phase 04);
##           client does NOT strike.
##   after host credit: host asks the real gate handler to complete; it MUST
##           be refused because the client has no credit.
##   t=15.0  client walks to the console and performs a real hammer strike.
##   after both credits: host asks again; it MUST accept.
##
## Fixture: the probe marks the three memories done and opens the gate panel at
## link time, because this is a unit test of the participation gate, not of the
## crystal/memory chain. No ledger credit is written by hand: both credits come
## from the real hammer strike RPC. C (full chain) is the evidence that the real
## stages work; this probe only isolates B's refusal/allow rule.

var role: String = "host"
var tag: String = "gate"
var out_dir: String = ""
var wait_seconds: float = 3.0

var log_lines: Array[String] = []
var started: int = 0
var link_at: int = 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--role="):
			role = s.split("=")[1]
		elif s.begins_with("--tag="):
			tag = s.split("=")[1]
		elif s.begins_with("--out="):
			out_dir = s.split("=")[1]
		elif s.begins_with("--wait="):
			wait_seconds = float(s.split("=")[1])
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
			"ready04": bool(led.call("ready_for_phase", int(pid), "04")),
		})
	return out


func _log_ledger(label: String) -> void:
	log_line("LEDGER %s %s" % [label, JSON.stringify(_ledger_rows())])


func _player_ok(p: Variant) -> bool:
	return p is Node and is_instance_valid(p) and (p as Node).is_inside_tree()


func _face(player: Node, target: Vector3) -> void:
	if not _player_ok(player):
		return
	player.call("aim_camera_at", Vector3(target.x, player.global_position.y, target.z), -99.0)


## Real walking only: no teleport. Two waypoints reproduce R2's validated
## approach around the console cabinet's north side.
func _walk_one(player: Node, target: Vector3, seconds: float, tolerance: float) -> bool:
	if not _player_ok(player):
		return false
	var elapsed := 0.0
	var stuck := 0.0
	var last: Vector3 = player.global_position
	Input.action_press("move_forward")
	while elapsed < seconds:
		await physics_frame
		elapsed += 1.0 / 60.0
		if not _player_ok(player):
			break
		var cur: Vector3 = player.global_position
		_face(player, target)
		if Vector2(cur.x - target.x, cur.z - target.z).length() <= tolerance:
			break
		if cur.distance_to(last) < 0.02:
			stuck += 1.0 / 60.0
		else:
			stuck = 0.0
			last = cur
		if stuck > 1.0:
			var side := "move_right" if int(elapsed * 7.0) % 2 == 0 else "move_left"
			Input.action_press(side)
			for _i in range(12):
				await physics_frame
			Input.action_release(side)
			stuck = 0.0
			last = player.global_position
	Input.action_release("move_forward")
	await physics_frame
	if not _player_ok(player):
		return false
	var flat: float = Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length()
	log_line("WALK %s target=%s pos=%s dist=%.2f" % [
		"console" if target.z < 0.0 else "approach", str(target),
		str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))), flat])
	return flat <= tolerance * 2.0


func _approach_console(player: Node) -> bool:
	var a := await _walk_one(player, Vector3(1.15, 0.0, -0.55), 12.0, 0.85)
	var b := await _walk_one(player, Vector3(2.35, 0.0, -0.55), 6.0, 0.42)
	return a and b


func _ledger_ready(pid: int) -> bool:
	for row in _ledger_rows():
		if int(row["pid"]) == pid and bool(row["ready04"]):
			return true
	return false


func _wait_ledger(pid: int, timeout_s: float) -> bool:
	var waited := 0.0
	while waited < timeout_s:
		if _ledger_ready(pid):
			return true
		await _wait(0.25)
		waited += 0.25
	return _ledger_ready(pid)


func _strike(reason: String) -> bool:
	var game := current_scene
	if game == null:
		return false
	var player: Node = game.get("player") as Node
	var hammer: Node = game.get("hammer") as Node
	if player == null or hammer == null:
		return false
	if not await _approach_console(player):
		log_line("STRIKE %s walk_failed pos=%s" % [reason, str(player.global_position)])
		return false
	var anchor: Vector3 = hammer.call("get_interaction_position") as Vector3
	player.call("aim_camera_at", anchor, -99.0)
	await _wait(0.45)
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	await _wait(0.4)
	if str(hammer.get("mode")) != "held":
		log_line("STRIKE %s grab_failed mode=%s" % [reason, str(hammer.get("mode"))])
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
			log_line("STRIKE %s ok count=%d was=%d" % [reason, int(hammer.get("strike_count")), before])
			return true
	log_line("STRIKE %s failed count=%d was=%d" % [reason, int(hammer.get("strike_count")), before])
	return false


func _gate_attempt(label: String) -> bool:
	var game := current_scene
	if game == null:
		return false
	game.set_meta("suppress_act5", true)
	var gate: Node = game.get("gate") as Node
	if gate == null:
		return false
	if not bool(gate.get("is_open")):
		gate.call("open")
		for _i in range(80):
			await _wait(0.1)
			if bool(gate.get("is_open")):
				break
	game.call("_on_exit_entered")
	await _wait(0.3)
	var completed := bool(game.get("completed"))
	log_line("GATE %s completed=%s gate_open=%s ledger=%s" % [
		label, str(completed), str(bool(gate.get("is_open"))), JSON.stringify(_ledger_rows())])
	return completed


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
	for _i in range(240):
		if _peer_ready():
			link_at = Time.get_ticks_msec()
			break
		await _wait(0.25)
	if link_at == 0:
		log_line("FAIL no peer link")
		_finish()
		return
	log_line("LINK ok peers=%s coop=%s" % [
		str(int(_net().call("peer_count"))), str(game.get("coop_mode"))])
	_snapshot_ledger("link")
	# Fixture: `_on_exit_entered()` requires memory 3 and an open gate panel.
	# This probe isolates the participation rule, so only that minimum
	# eligibility flag is set; no ledger credit is written by hand. C (full
	# chain) is the evidence that the real crystal/memory chain opens the gate.
	game.get("seen_memories")[3] = true
	var gate: Node = game.get("gate") as Node
	if gate != null and not bool(gate.get("is_open")):
		gate.call("open")
		for _i in range(80):
			await _wait(0.1)
			if bool(gate.get("is_open")):
				break
	log_line("SETUP gate_open=%s" % str(bool(gate.get("is_open")) if gate != null else false))

	if role == "host":
		await _wait(4.0)
		var host_struck := await _strike("host")
		log_line("HOST_STRIKE ok=%s" % str(host_struck))
		if not host_struck:
			log_line("FAIL host could not earn a real phase-04 credit")
			_finish()
			return
		var host_ready := await _wait_ledger(1, 20.0)
		log_line("HOST_READY ready04=%s" % str(host_ready))
		if not host_ready:
			log_line("FAIL host ledger has no phase-04 credit")
			_finish()
			return
		var blocked_ok := await _gate_attempt("client_missing")
		if blocked_ok:
			log_line("FAIL gate accepted while the client had no phase-04 credit")
		else:
			log_line("PASS gate refused while the client had no phase-04 credit")
		# Clear the console so the client's real walk has a free lane.
		var host_player: Node = game.get("player") as Node
		await _walk_one(host_player, Vector3(4.5, 0.0, 4.0), 6.0, 0.8)
		# Wait for the client's real strike and the host-authoritative credit.
		var client_ready := await _wait_ledger(2, 60.0)
		log_line("CLIENT_READY ready04=%s" % str(client_ready))
		_snapshot_ledger("before_second_attempt")
		if not client_ready:
			log_line("FAIL host ledger never received the client's real phase-04 credit")
			_finish()
			return
		var allowed_ok := await _gate_attempt("both_credited")
		if allowed_ok:
			log_line("PASS gate accepted after both players earned a real phase-04 credit")
		else:
			log_line("FAIL gate still refused after both players struck the bell")
		# Prove the client really earned its credit on the host authority.
		var rows := _ledger_rows()
		var p2_ready := false
		var p2_active := false
		for row in rows:
			if int(row["pid"]) == 2:
				p2_ready = bool(row["ready04"])
				p2_active = str(row["status"]) == "active"
		log_line("ASSERT host ledger pid2 ready04=%s active=%s" % [
			str(p2_ready), str(p2_active)])
		if not p2_ready:
			log_line("FAIL host ledger still has no pid2 phase-04 credit")
		if not p2_active:
			log_line("FAIL host ledger does not show pid2 as an active participant")
		_finish()
	else:
		# Stay out of the host's way until its negative attempt is done, then
		# walk to the console and earn a real phase-04 credit.
		await _wait(20.0)
		var client_struck := await _strike("client")
		log_line("CLIENT_STRIKE ok=%s" % str(client_struck))
		if not client_struck:
			log_line("FAIL client could not earn a real phase-04 credit")
			_finish()
			return
		_snapshot_ledger("client_after_strike")
		# Stay connected while the host takes its second gate attempt, then
		# prove the client mirror received the host's phase-04 authority.
		await _wait(10.0)
		_snapshot_ledger("client_after_authority")
		var rows := _ledger_rows()
		var p2_ready := false
		for row in rows:
			if int(row["pid"]) == 2 and bool(row["ready04"]):
				p2_ready = true
		log_line("ASSERT client mirror pid2 ready04=%s" % str(p2_ready))
		if not p2_ready:
			log_line("FAIL client mirror never received the host's pid2 phase-04 credit")
		_finish()


func _snapshot_ledger(label: String) -> void:
	_log_ledger(label)


func _finish() -> void:
	var payload := {
		"probe": "r8c04_gate_probe.gd",
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
