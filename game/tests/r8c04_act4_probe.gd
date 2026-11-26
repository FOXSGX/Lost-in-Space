extends SceneTree

## R8C-04 focused Act 4 co-op probe.
## Two real processes; the role comes from --role=host|client.
## This probe binds to the real Act 4 scene and drives the hammer with the
## real input map. Teleporting is only used to reach the hammer console fast in
## this diagnostic; the interaction itself is E/W/E and checkable state.

var role: String = "host"
var tag: String = "act4"
var out_dir: String = ""
var wait_seconds: float = 8.0

var game: Node = null
var player: Node = null
var hammer: Node = null
var started: int = 0
var log_lines: Array[String] = []


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


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 600:
		await process_frame
		guard += 1
	log_line("BOOT scene=%s" % (str(current_scene.name) if current_scene != null else "null"))
	# Wait for the scene's _ready and coop setup.
	await _wait(2.0)
	game = current_scene
	if game == null or str(game.name) not in ["Act4", "Resonance04"]:
		log_line("FAIL wrong scene")
		_finish()
		return
	player = game.get("player") as Node
	hammer = game.get("hammer") as Node
	var hub: Node = root.get_node_or_null("/root/SessionHub")
	var net: Node = hub.get("net") if hub != null else null
	var session: Node = hub.get("session") if hub != null else null
	log_line("GAME scene=%s coop_mode=%s player=%s hammer=%s" % [
		str(game.name), str(game.get("coop_mode")), str(player != null), str(hammer != null)])
	if hub != null:
		log_line("HUB mode=%s local_pid=%s net_is_host=%s peers=%s session_local=%s" % [
			str(hub.get("mode")), str(net.get("local_pid") if net != null else "?"),
			str(net.get("is_host") if net != null else "?"),
			str(net.call("peer_count") if net != null else "?"),
			str(session.get("local_pid") if session != null else "?")])
	# Wait until the peer link is actually connected.
	if net != null:
		var connected := false
		for _i in range(120):
			var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
			if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and int(net.call("peer_count")) >= 2:
				connected = true
				break
			await _wait(0.25)
		log_line("LINK connected=%s peers=%s" % [str(connected), str(net.call("peer_count"))])
	# Let the other side bind Act 4 too.
	await _wait(wait_seconds)
	if player == null or hammer == null:
		log_line("FAIL missing player/hammer")
		_finish()
		return
	# Teleport to the hammer console and use real input to grab and strike.
	player.call("teleport", Vector3(2.25, 0.2, -0.4), 0.0)
	await _wait(0.5)
	player.call("aim_camera_at", Vector3(2.25, 1.2, -4.5), -0.08)
	await _wait(0.3)
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	await _wait(0.4)
	log_line("GRAB mode=%s strike_count=%d pos=%s" % [
		str(hammer.get("mode")), int(hammer.get("strike_count")), str(player.global_position)])
	Input.action_press("move_forward")
	await _wait(1.45)
	Input.action_release("move_forward")
	await _wait(0.2)
	var before: int = int(hammer.get("strike_count"))
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	var struck := false
	for _i in range(40):
		await _wait(0.1)
		if int(hammer.get("strike_count")) > before:
			struck = true
			break
	log_line("STRIKE local_count=%d was=%d struck=%s" % [
		int(hammer.get("strike_count")), before, str(struck)])
	# Give the host time to process the reliable RPC.
	await _wait(2.0)
	# Read local ledger (host: authoritative; client: mirror, expected empty).
	if session != null and session.get("ledger") != null:
		var led = session.get("ledger")
		for pid in led.call("player_ids"):
			log_line("LEDGER pid=%d status=%s phases=%s" % [
				int(pid), str(led.call("status_of", int(pid))),
				str((led.call("get_record", int(pid)).get("phases", {})))])
	_finish()


func _finish() -> void:
	var payload := {
		"probe": "r8c04_act4_probe.gd",
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
