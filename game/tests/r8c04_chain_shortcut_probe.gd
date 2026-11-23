extends SceneTree

## R8C-04 shortcut campaign chain: Act01 -> Act23 -> Act04 through the real
## SessionHub scene-switch contract, then a real client hammer strike.
## This is NOT a gameplay pass; it exists to isolate whether the Act01/Act23
## scene lifecycle loses the Act04 participation state before the real
## end-to-end probe runs.

var role: String = "host"
var tag: String = "shortcut"
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


func _wait_scene(names: Array, timeout_s: float) -> bool:
	var waited := 0.0
	while waited < timeout_s:
		if current_scene != null and names.has(str(current_scene.name)):
			return true
		await _wait(0.2)
		waited += 0.2
	return current_scene != null and names.has(str(current_scene.name))


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


func _strike() -> bool:
	var game := current_scene
	if game == null:
		return false
	var player: Node = game.get("player") as Node
	var hammer: Node = game.get("hammer") as Node
	if player == null or hammer == null:
		log_line("STRIKE missing player=%s hammer=%s" % [str(player != null), str(hammer != null)])
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
		log_line("STRIKE grab_failed mode=%s" % str(hammer.get("mode")))
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
			await _wait(1.5)
			log_line("STRIKE ok count=%d was=%d coop=%s" % [
				int(hammer.get("strike_count")), before, str(game.get("coop_mode"))])
			return true
	log_line("STRIKE failed count=%d was=%d" % [int(hammer.get("strike_count")), before])
	return false


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 600:
		await process_frame
		guard += 1
	log_line("BOOT scene=%s" % (str(current_scene.name) if current_scene != null else "null"))
	await _wait(2.0)
	var ok := false
	for _i in range(240):
		if _peer_ready():
			ok = true
			break
		await _wait(0.25)
	log_line("LINK ready=%s peers=%s" % [str(ok), str(int(_net().call("peer_count")) if _net() != null else -1)])
	_log_ledger("act01")
	if not ok:
		_finish()
		return
	var hub := _hub()
	if role == "host":
		await _wait(2.0)
		log_line("HANDOFF act01 -> act23")
		hub.call("complete_chapter", "act01", {"completed": true, "mode": "coop_host"}, "act23", "res://scenes/act23.tscn", {"from_chapter": "act01", "to_chapter": "act23"})
	if not await _wait_scene(["Act23Chapter", "Act23"], 40.0):
		log_line("FAIL no Act23 scene")
		_finish()
		return
	log_line("SCENE act23 coop=%s" % str(current_scene.get("coop_mode")))
	await _wait(3.0)
	_log_ledger("act23")
	if role == "host":
		log_line("HANDOFF act23 -> act04")
		hub.call("complete_chapter", "act23", {"phase": "done", "completed": true}, "act04", "res://scenes/act4.tscn", {"from_chapter": "act23", "to_chapter": "act04"})
	if not await _wait_scene(["Act4", "Resonance04"], 60.0):
		log_line("FAIL no Act04 scene")
		_finish()
		return
	await _wait(3.0)
	log_line("SCENE act4 coop=%s" % str(current_scene.get("coop_mode")))
	_log_ledger("act4_begin")
	await _wait(2.0)
	var struck := await _strike()
	_log_ledger("after_strike")
	log_line("RESULT struck=%s" % str(struck))
	_finish()


func _finish() -> void:
	var payload := {
		"probe": "r8c04_chain_shortcut_probe.gd",
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
