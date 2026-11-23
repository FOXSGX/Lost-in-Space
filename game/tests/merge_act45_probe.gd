extends SceneTree

# -----------------------------------------------------------------------------
# merge_act45_probe.gd · Act04 -> Act05 dual-process session continuity probe
#
#   host : & $G --headless --path <project> res://scenes/act4.tscn \
#                -s res://tests/merge_act45_probe.gd -- --host --port=26960
#   client: ... -- --client --port=26960 --address=127.0.0.1
#
# It checks the REAL MultiplayerPeer object (class, connection status,
# multiplayer.get_peers()), not the cached CoopNet.online flag:
#   * Act04: ENet connected on both ends, remote body visible on both ends,
#     client bootstrap applied, host served the sync request.
#   * host orders one SessionHub.request_scene_switch to res://scenes/main.tscn.
#   * Act05: peer still ENetMultiplayerPeer / CONNECTED, peers preserved,
#     SessionHub and CoopNet unique, Act04 binding null, no Act04 node left,
#     old Act04 scene freed, pending spawn carried.
#
# One machine-readable MERGE_ACT45 line per process.
# -----------------------------------------------------------------------------

var role: String = "host"
var port: int = 26960
var started_ms: int = 0

func _initialize() -> void:
	started_ms = Time.get_ticks_msec()
	var args: Array[String] = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	for arg: String in args:
		if arg == "--host":
			role = "host"
		elif arg == "--client":
			role = "client"
		elif arg.begins_with("--port="):
			port = int(arg.split("=")[1])
	print("MERGE_ACT45_START role=", role, " port=", port)
	run.call_deferred()


func frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func wait_scene(suffix: String, limit_ms: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + limit_ms
	while Time.get_ticks_msec() < deadline:
		if current_scene != null and str(current_scene.scene_file_path).ends_with(suffix):
			return true
		await process_frame
	return false


func peer_record() -> Dictionary:
	var ml: MultiplayerAPI = root.multiplayer
	var peer: MultiplayerPeer = ml.multiplayer_peer if ml != null else null
	var peers: Array = []
	if ml != null:
		peers = ml.get_peers()
	return {
		"peer_class": peer.get_class() if peer != null else "null",
		"peer_status": peer.get_connection_status() if peer != null else -1,
		"peers": peers,
		"peer_count": peers.size() + 1,
	}


func hub_record(hub: Node) -> Dictionary:
	var hub_count: int = 0
	if hub != null and hub.get_parent() == root:
		hub_count += 1
	var coop_nets: Array[Node] = root.find_children("CoopNet", "", true, false)
	var paths: Array[String] = []
	for n: Node in coop_nets:
		paths.append(str(n.get_path()))
	return {"sessionhub_count": hub_count, "coopnet_paths": paths}


func count_script_nodes(path_suffix: String) -> int:
	var total: int = 0
	for node: Node in root.find_children("*", "", true, false):
		var scr: Script = node.get_script() as Script
		if scr != null and str(scr.resource_path).ends_with(path_suffix):
			total += 1
	return total


func report(record: Dictionary) -> void:
	print("MERGE_ACT45 ", JSON.stringify(record))
	print("MERGE_ACT45_DONE role=", role)
	quit(0 if bool(record.get("passed", false)) else 2)


func fail(reason: String, detail: Dictionary = {}) -> void:
	var rec: Dictionary = {"role": role, "passed": false, "reason": reason}
	rec.merge(detail, true)
	report(rec)


func run() -> void:
	# --- Act04 boot ---------------------------------------------------------
	var ok_act4: bool = await wait_scene("scenes/act4.tscn", 30000)
	if not ok_act4:
		fail("act4_scene_not_loaded", {"scene": str(current_scene.scene_file_path) if current_scene != null else "null"})
		return
	await frames(10)

	var hub: Node = root.get_node_or_null("/root/SessionHub")
	if hub == null:
		fail("sessionhub_missing")
		return
	var net: Node = hub.get("net")
	if net == null:
		fail("coopnet_missing")
		return
	var game: Node = current_scene
	var ml: MultiplayerAPI = root.multiplayer

	# Wait until the real ENet link is up (not CoopNet.online).
	var connected: bool = false
	var deadline: int = Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var peer: MultiplayerPeer = ml.multiplayer_peer
		if peer is ENetMultiplayerPeer \
				and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
				and ml.get_peers().size() > 0:
			connected = true
			break
		await process_frame
	if not connected:
		fail("enet_not_connected", peer_record())
		return

	var remote: Node = game.get("remote_player")
	var ready: bool = false
	deadline = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		remote = game.get("remote_player")
		var visible: bool = remote != null and bool(remote.get("visible"))
		if role == "client":
			if visible and int(game.get("act4_bootstrap_count")) >= 1:
				ready = true
				break
		else:
			if visible and int(game.get("act4_sync_requests")) >= 1:
				ready = true
				break
		await process_frame
	if not ready:
		fail("act4_peer_not_ready", {
			"remote_visible": remote != null and bool(remote.get("visible")),
			"bootstrap_count": int(game.get("act4_bootstrap_count")),
			"sync_requests": int(game.get("act4_sync_requests")),
			"peer": peer_record(),
		})
		return

	var pre: Dictionary = {
		"act4_scene": str(game.scene_file_path),
		"act4_coop_mode": str(game.get("coop_mode")),
		"act4_remote_visible": bool(remote.get("visible")) if remote != null else false,
		"act4_players_keys": (game.get("coop_players") as Dictionary).keys(),
		"act4_bootstrap_count": int(game.get("act4_bootstrap_count")),
		"act4_sync_requests": int(game.get("act4_sync_requests")),
		"act4_net_bound_to_act4": net.get("act4_game") == game,
		"pre_peer": peer_record(),
		"pre_hub": hub_record(hub),
		"pre_local_pid": int(hub.get("session").get("local_pid")),
	}
	print("MERGE_ACT45_PRE ", JSON.stringify(pre))

	# --- host orders the real cross-scene switch ---------------------------
	var old_ref: WeakRef = weakref(game)
	game = null
	remote = null
	if role == "host":
		await frames(30)
		hub.call("request_scene_switch", "res://scenes/main.tscn", {
			"from": "act4", "to": "act5", "testkit": "merge",
		})
		print("MERGE_ACT45_SWITCH_REQUESTED")

	# --- Act05 --------------------------------------------------------------
	var ok_act5: bool = await wait_scene("scenes/main.tscn", 30000)
	if not ok_act5:
		fail("act5_scene_not_loaded", {
			"scene": str(current_scene.scene_file_path) if current_scene != null else "null",
			"peer": peer_record(),
		})
		return
	await frames(120)

	var app: Node = current_scene
	var net_after: Node = hub.get("net")
	var act4_bound: Variant = net_after.get("act4_game") if net_after != null else null
	var bound_text: String = "<null>"
	if act4_bound != null:
		bound_text = str(act4_bound) if is_instance_valid(act4_bound) else "<Freed Object>"
	var old_alive: bool = old_ref.get_ref() != null
	var pending: Dictionary = hub.get("pending_spawn") as Dictionary
	var after_peer: Dictionary = peer_record()
	var after_hub: Dictionary = hub_record(hub)
	var session_after: Node = hub.get("session")
	var checks: Dictionary = {
		"act5_scene_loaded": ok_act5,
		"peer_is_enet": str(after_peer["peer_class"]) == "ENetMultiplayerPeer",
		"peer_connected": int(after_peer["peer_status"]) == MultiplayerPeer.CONNECTION_CONNECTED,
		"peers_preserved": (after_peer["peers"] as Array).size() > 0,
		"sessionhub_unique": int(after_hub["sessionhub_count"]) == 1,
		"coopnet_unique": (after_hub["coopnet_paths"] as Array).size() == 1,
		"act4_unbound": act4_bound == null,
		"act4_node_count_zero": count_script_nodes("scripts/act4/game.gd") == 0,
		"old_act4_scene_freed": not old_alive,
		"local_player_present": app.get("player") != null,
		"pending_spawn_carried": pending.has("testkit"),
		"pid_preserved": int(session_after.get("local_pid")) == int(pre["pre_local_pid"]),
		"remote_visible_in_act4": bool(pre["act4_remote_visible"]),
	}
	var passed: bool = true
	for key: String in checks:
		if not bool(checks[key]):
			passed = false
	var record: Dictionary = {
		"role": role,
		"passed": passed,
		"checks": checks,
		"pre": pre,
		"after_peer": after_peer,
		"after_hub": after_hub,
		"act4_bound_after": bound_text,
		"act4_node_count_after": count_script_nodes("scripts/act4/game.gd"),
		"old_act4_freed": not old_alive,
		"act5_scene": str(app.scene_file_path),
		"act5_player": app.get("player") != null,
		"act5_level": app.get("level") != null,
		"act5_story": app.get("story") != null,
		"pending_spawn_keys": pending.keys(),
		"local_pid_after": int(session_after.get("local_pid")) if session_after != null else -1,
		"elapsed_ms": Time.get_ticks_msec() - started_ms,
	}
	report(record)
