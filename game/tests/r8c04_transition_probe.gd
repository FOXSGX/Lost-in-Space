extends SceneTree

## R8C-04 transition probe: Act23Chapter -> Resonance04 in one live session,
## then a real client hammer strike. Used to reproduce the reported loss of the
## client's phase-04 credit when Act 4 is reached through the real hand-off.

var role: String = "host"
var tag: String = "transition"
var out_dir: String = ""
var mode: String = "transition"
var wait_seconds: float = 8.0

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
		elif s.begins_with("--wait="):
			wait_seconds = float(s.split("=")[1])
	started = Time.get_ticks_msec()
	_run.call_deferred()


func log_line(text: String) -> void:
	print("[%s] %s" % [role, text])
	log_lines.append(text)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_scene(names: Array, timeout_s: float) -> bool:
	var waited := 0.0
	while waited < timeout_s:
		if current_scene != null and names.has(str(current_scene.name)):
			return true
		await _wait(0.2)
		waited += 0.2
	return current_scene != null and names.has(str(current_scene.name))


func _hub() -> Node:
	return root.get_node_or_null("/root/SessionHub")


func _net() -> Node:
	var hub := _hub()
	return hub.get("net") if hub != null else null


func _session() -> Node:
	var hub := _hub()
	return hub.get("session") if hub != null else null


func _snapshot_ledger(label: String) -> void:
	var session := _session()
	if session == null:
		log_line("LEDGER %s session=null" % label)
		return
	var led = session.get("ledger")
	if led == null:
		log_line("LEDGER %s ledger=null" % label)
		return
	var rows: Array = []
	for pid in led.call("player_ids"):
		var rec: Dictionary = led.call("get_record", int(pid))
		rows.append({
			"pid": int(pid),
			"status": str(led.call("status_of", int(pid))),
			"phases": (rec.get("phases", {}) as Dictionary).duplicate(true),
			"kinds": (rec.get("credits", {}) as Dictionary).keys(),
		})
	log_line("LEDGER %s %s" % [label, JSON.stringify(rows)])


func _peer_ready() -> bool:
	var net := _net()
	if net == null:
		return false
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return int(net.call("peer_count")) >= 2


func _strike() -> bool:
	var game := current_scene
	if game == null:
		return false
	var player: Node = game.get("player") as Node
	var hammer: Node = game.get("hammer") as Node
	if player == null or hammer == null:
		log_line("STRIKE missing player/hammer")
		return false
	player.call("teleport", Vector3(2.25, 0.2, -0.4), 0.0)
	await _wait(0.4)
	player.call("aim_camera_at", Vector3(2.25, 1.2, -4.5), -0.08)
	await _wait(0.3)
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	await _wait(0.4)
	log_line("GRAB mode=%s count=%d" % [str(hammer.get("mode")), int(hammer.get("strike_count"))])
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
			await _wait(1.5)
			log_line("STRIKE local_count=%d was=%d coop_mode=%s" % [
				int(hammer.get("strike_count")), before, str(game.get("coop_mode"))])
			return true
	log_line("STRIKE failed local_count=%d was=%d" % [int(hammer.get("strike_count")), before])
	return false


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 600:
		await process_frame
		guard += 1
	log_line("BOOT scene=%s" % (str(current_scene.name) if current_scene != null else "null"))
	if not await _wait_scene(["Act23Chapter", "Act23"], 20.0):
		log_line("FAIL not in Act23Chapter")
		_finish()
		return
	await _wait(2.0)
	var hub := _hub()
	log_line("HUB mode=%s chapter=%s" % [str(hub.get("mode")) if hub != null else "?", str(hub.get("current_chapter")) if hub != null else "?"])
	var ok := false
	for _i in range(240):
		if _peer_ready():
			ok = true
			break
		await _wait(0.5)
	log_line("LINK ready=%s peers=%s" % [str(ok), str(int(_net().call("peer_count")) if _net() != null else -1)])
	_snapshot_ledger("act23")
	if role == "host":
		await _wait(4.0)
		log_line("HANDOFF call complete_chapter act23->act04")
		hub.call("complete_chapter", "act23", {"phase": "done", "completed": true}, "act04", "res://scenes/act4.tscn", {"from_chapter": "act23", "to_chapter": "act04"})
	if not await _wait_scene(["Act4", "Resonance04"], 60.0):
		log_line("FAIL no Act04 (scene=%s)" % (str(current_scene.name) if current_scene != null else "null"))
		_finish()
		return
	await _wait(3.0)
	log_line("ACT4 scene=%s coop=%s" % [str(current_scene.name), str(current_scene.get("coop_mode"))])
	_snapshot_ledger("act4_begin")
	await _wait(wait_seconds)
	var struck := await _strike()
	_snapshot_ledger("after_strike")
	log_line("RESULT struck=%s" % str(struck))
	_finish()


func _finish() -> void:
	var payload := {
		"probe": "r8c04_transition_probe.gd",
		"role": role,
		"tag": tag,
		"elapsed_seconds": float(Time.get_ticks_msec() - started) / 1000.0,
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
