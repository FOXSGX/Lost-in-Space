extends SceneTree
## Independent audit probe for the Act23 -> Act04 hand-off.
##
## It drives the real Act23 end-of-run state (route released, cart just short of
## the crystal gate, rider on deck) and never writes flow.phase / completed.
## It then observes the *actual* SceneTree multiplayer peer after the switch,
## instead of trusting the cached SessionHub.net.online flag.
##
## Roles:
##   --host   -> creates the unified session, positions the cart, switches.
##   --client -> joins the same session, follows do_scene_switch.
##
## Output is one machine-readable AUDIT line per process.

var role: String = "solo"
var port: int = 26904
var started_ms: int = 0
var positioned: bool = false
var host_registered: bool = false
var reported: bool = false
var act4_seen_frames: int = 0
# Barrier: both processes must have reached Act04 before either reports, so a
# report never observes the peer after the other side has already exited.
var out_dir: String = ""
var ready_written: bool = false

func _initialize() -> void:
	started_ms = Time.get_ticks_msec()
	var args: Array[String] = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	for index: int in range(args.size()):
		var arg: String = args[index]
		if arg == "--host" or arg == "--auto=host":
			role = "host"
		elif arg == "--client" or arg == "--auto=client":
			role = "client"
		elif arg.begins_with("--port="):
			port = int(arg.split("=")[1])
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	print("AUDIT_PROBE_START role=", role, " port=", port, " out=", out_dir)

func _ready_path(who: String) -> String:
	return out_dir.path_join("handoff_%s.ready" % who)

func _write_ready() -> void:
	if out_dir == "":
		return
	var f: FileAccess = FileAccess.open(_ready_path(role), FileAccess.WRITE)
	if f != null:
		f.store_string("ready")
		f.close()

func _both_ready() -> bool:
	if out_dir == "":
		return true
	return FileAccess.file_exists(_ready_path("host")) and FileAccess.file_exists(_ready_path("client"))

func _stage_node() -> Node:
	if current_scene == null:
		return null
	return current_scene.find_child("MovingCartSlice", true, false)

func _process(_delta: float) -> bool:
	var elapsed: int = Time.get_ticks_msec() - started_ms
	if role == "host" and not host_registered and elapsed > 1000:
		# The launcher registers the local host participant before Act01; a
		# direct --host boot does not. Mirror that production step in the probe.
		var hub_node: Node = root.get_node_or_null("/root/SessionHub")
		var session_node: Node = hub_node.get_node_or_null("CoopSession") if hub_node != null else null
		if session_node != null:
			session_node.call("add_player", 1, "七号", true)
			host_registered = true
	if role == "host" and not positioned and elapsed > 3000:
		positioned = true
		var stage: Node = _stage_node()
		if stage == null:
			print("AUDIT_PROBE host_stage_missing scene=", str(current_scene.name) if current_scene != null else "null")
			return false
		var cart: Node = stage.get_node_or_null("MovingCart")
		var player: Node = stage.get_node_or_null("Player1")
		if cart == null or player == null:
			print("AUDIT_PROBE host_cart_or_player_missing")
			return false
		cart.call("release_route")
		cart.call("snap_to_distance", 103.5)
		cart.set("running", true)
		player.call("restore_at", cart.to_global(Vector3(1.0, 1.91, 1.6)))
		print("AUDIT_PROBE_HOST_POSITIONED distance=103.5 running=true route_clear=true")
		return false

	if current_scene != null and str(current_scene.name) == "Resonance04":
		act4_seen_frames += 1
		# Let the old Act23 scene finish queue_free() and Act04 finish _ready().
		if act4_seen_frames < 120:
			return false
		if not ready_written:
			ready_written = true
			_write_ready()
			print("AUDIT_PROBE_ACT4_READY role=", role)
		if reported:
			return false
		# Do not sample the peer after the other side has exited: both sides must
		# be alive in Act04 when the post-handoff connection is judged.
		if not _both_ready():
			return false
		reported = true
		_report_after_handoff(elapsed)
		quit(0)
		return false

	# Timeout guard: never hang the runner.
	if elapsed > 45000 and not reported:
		reported = true
		print("AUDIT_PROBE_TIMEOUT role=", role, " scene=", str(current_scene.name) if current_scene != null else "null")
		quit(2)
	return false

func _report_after_handoff(elapsed: int) -> void:
	var hub: Node = root.get_node_or_null("/root/SessionHub")
	var hub_net: Node = hub.get_node_or_null("CoopNet") if hub != null else null
	var session: Node = hub.get_node_or_null("CoopSession") if hub != null else null
	var ml: MultiplayerAPI = root.multiplayer
	var peer: MultiplayerPeer = ml.multiplayer_peer
	var peer_class: String = peer.get_class() if peer != null else "null"
	var peer_status: int = peer.get_connection_status() if peer != null else -1
	var peers: Array = []
	if peer != null:
		peers = ml.get_peers()
	var act4: Node = current_scene
	var act4_player: Node = act4.get("player") if act4.get("player") != null else null
	var coop_mode: String = str(act4.get("coop_mode"))
	var act4_net: Node = act4.get("coop_net")
	var act4_net_online: String = str(act4_net.get("online")) if act4_net != null else "null"
	var act4_net_peer_count: int = int(act4_net.call("peer_count")) if act4_net != null and act4_net.has_method("peer_count") else -1
	var act4_net_is_host: bool = bool(act4_net.get("is_host")) if act4_net != null else false
	var act4_players: Dictionary = act4.get("coop_players") if act4.get("coop_players") != null else {}
	var act4_remote: Node = act4.get("remote_player")
	var act4_remote_visible: bool = bool(act4_remote.get("visible")) if act4_remote != null else false
	var act4_net_bound_to_act4: bool = act4_net != null and act4_net.get("act4_game") == act4
	var act4_net_seq: int = int(act4_net.get("_seq")) if act4_net != null else -1
	var act4_model_present: bool = act4.get("model") != null
	var act4_hud_present: bool = act4.get("hud") != null
	var act4_gate_present: bool = act4.get("gate") != null
	var act4_memory_present: bool = act4.get("memory") != null
	var act4_platform_present: bool = act4.get("platform") != null
	var act4_stage: int = int(act4.get("stage")) if act4.get("stage") != null else -1
	var local_pid: int = int(session.get("local_pid")) if session != null else -1
	var history: Dictionary = hub.get("chapter_history") if hub != null else {}
	var act23_payload: Dictionary = history.get("act23", {}) if history.has("act23") else {}
	var spawn: Dictionary = hub.get("pending_spawn") if hub != null else {}
	var old_stage: Node = root.find_child("MovingCartSlice", true, false)
	var old_act23: Node = root.get_node_or_null("Act23Chapter")
	var old_moving_cart: Node = root.find_child("MovingCart", true, false)
	var hub_count: int = 0
	var coop_net_count: int = 0
	for child: Node in root.get_children():
		if str(child.name) == "SessionHub":
			hub_count += 1
		if str(child.name) == "CoopNet":
			coop_net_count += 1
	var coop_nets: Array[Node] = root.find_children("CoopNet", "", true, false)
	var coop_net_paths: Array[String] = []
	for net_node: Node in coop_nets:
		coop_net_paths.append(str(net_node.get_path()))
	var ledger: Dictionary = {}
	if session != null:
		var led: Variant = session.get("ledger")
		if led != null:
			ledger = led.call("snapshot") as Dictionary
	var record: Dictionary = {
		"role": role,
		"elapsed_ms": elapsed,
		"scene": str(act4.name),
		"scene_path": "res://scenes/act4.tscn",
		"chapter": str(hub.get("current_chapter")) if hub != null else "no-hub",
		"act23_completed": bool(act23_payload.get("completed", false)),
		"act23_payload_keys": act23_payload.keys(),
		"act23_phase": str(act23_payload.get("phase", "")),
		"act23_cart_distance": float(act23_payload.get("cart_distance", -1.0)),
		"act23_participation_present": act23_payload.has("participation"),
		"pending_spawn_keys": spawn.keys(),
		"pending_spawn": str(spawn),
		"story_flags": str(hub.get("story_flags")) if hub != null else "no-hub",
		"chapter_progress": str(hub.get("chapter_progress")) if hub != null else "no-hub",
		"hub_net_online_flag": bool(hub_net.get("online")) if hub_net != null else false,
		"hub_is_online": bool(hub.call("is_online")) if hub != null and hub.has_method("is_online") else false,
		"peer_class": peer_class,
		"peer_status": peer_status,
		"peers": peers,
		"local_pid": local_pid,
		"act4_coop_mode": coop_mode,
		"act4_net_bound": act4_net != null,
		"act4_net_bound_to_act4": act4_net_bound_to_act4,
		"act4_net_online": act4_net_online,
		"act4_net_peer_count": act4_net_peer_count,
		"act4_net_is_host": act4_net_is_host,
		"act4_net_seq": act4_net_seq,
		"act4_players_keys": act4_players.keys(),
		"act4_remote_visible": act4_remote_visible,
		"act4_player_present": act4_player != null,
		"act4_model_present": act4_model_present,
		"act4_hud_present": act4_hud_present,
		"act4_gate_present": act4_gate_present,
		"act4_memory_present": act4_memory_present,
		"act4_platform_present": act4_platform_present,
		"act4_stage": act4_stage,
		"act4_player_pos": str(act4_player.global_position) if act4_player != null else "null",
		"act4_spawn_const": str(R04LevelBuilder.SPAWN),
		"old_act23_stage_present": old_stage != null,
		"old_act23_root_present": old_act23 != null,
		"old_moving_cart_present": old_moving_cart != null,
		"sessionhub_count": hub_count,
		"root_coopnet_count": coop_net_count,
		"coopnet_node_count": coop_nets.size(),
		"coopnet_paths": coop_net_paths,
		"ledger_player_count": ledger.size(),
		"ledger_players": ledger,
	}
	print("AUDIT_HANDOFF ", JSON.stringify(record))
	if old_stage != null:
		print("AUDIT_OLD_STAGE_PATH ", old_stage.get_path())
	if act4_net != null and is_instance_valid(act4_net):
		print("AUDIT_ACT4_NET_PATH ", act4_net.get_path())
	print("AUDIT_PROBE_DONE role=", role)
