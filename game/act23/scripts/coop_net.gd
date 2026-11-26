extends Node

# -----------------------------------------------------------------------------
# CoopNet - host-authoritative transport for the continuous 02+03 cart chapter.
#
# Ownership model (same split that was proven in the Resonance 04 slice):
#
#   HOST (peer 1, slot 1)
#     cart distance / speed / governor / brake
#     cargo rigid bodies (the only place they are integrated)
#     winch drum, cable length, clutch, brake
#     swing rail angle, jam, guide slot, lock pin
#     grip occupancy, console occupancy, cargo carrier
#     mission phases and participation records
#
#   CLIENT (slots 2..4)
#     its own character body only (first-person feel stays local)
#     mirrors every shared object from a 20 Hz snapshot
#     sends interaction requests; never writes shared state directly
#
# Player identity is a SLOT (1..4), not an ENet peer id. The host keeps the
# peer -> slot map, so a reconnect or a second client can never be mistaken for
# the host's own player. This is the bug the 04 slice had to fix once already.
#
# Node path must be identical on both ends: <stage>/CoopNet.
# -----------------------------------------------------------------------------

signal link_changed(mode: String, detail: String)

const MAX_PLAYERS: int = 4
const SNAPSHOT_HZ: float = 20.0
const DEFAULT_PORT: int = 26831
# Both ends build the same scene from the same script, so the boarding platform
# is a safe spawn for everybody. No player is ever spawned on the moving deck.
const SPAWN_POINT := Vector3(1.0, 0.38, -2.0)
# A 3- or 4-player crew used to be spawned onto that one point. Character capsules
# collide with each other (cart_player collision_mask 50 includes the player
# layer), so the second body was placed *inside* the first one and the landing
# depenetrated the pair off the edge before any input arrived. In the 3p/4p Act23
# runs the crew started 1.0-1.5 m away from the platform (one seat 1.5 m below
# it). Each slot now owns a standing spot on the same 4.6 x 2.6 m deck plate, at
# least 1.05 m apart (capsule diameter 0.76 m) and clear of the 0.9 m boarding
# stairs; a late joiner who arrives after the cart has left the dock gets a spot
# on the open deck that keeps the 0.96 m near-side exit gate clear.
const DOCK_SPAWN_SPOTS: Dictionary = {
	1: Vector3(0.0, 0.0, 0.0),
	2: Vector3(1.20, 0.0, 0.0),
	3: Vector3(0.0, 0.0, -1.05),
	4: Vector3(1.20, 0.0, -1.05),
}
const DECK_SPAWN_SPOTS: Dictionary = {
	1: Vector3(0.0, 1.91, 2.20),
	2: Vector3(-0.90, 1.91, 2.20),
	3: Vector3(0.0, 1.91, 3.05),
	4: Vector3(1.90, 1.91, 2.90),
}
const WELCOME_TIMEOUT: float = 8.0

var stage: Node3D
var mode: String = "offline"          # offline | host | client | connecting
# True when this chapter-level CoopNet is riding SessionHub's ENet peer instead
# of owning one. The chapter must then NOT close the socket when the Act23 scene
# is freed by the chapter hand-off to Act04.
var _adopted_session: bool = false
# Set once the chapter hand-off timer starts, so the chapter transport stops
# emitting pose/action RPCs while both processes are swapping scenes.
var _handoff_closing: bool = false
var port: int = DEFAULT_PORT
var local_slot: int = 1
var slots: Dictionary = {}            # slot -> {peer, connected, name, since}
var peer_to_slot: Dictionary = {}
var _next_slot: int = 2
var _timer: float = 0.0
var _welcome_clock: float = 0.0
var _sequence: int = 0

var snapshots_sent: int = 0
var snapshots_received: int = 0
var max_snapshot_bytes: int = 0
var rejected_poses: int = 0
var rejected_actions: int = 0
var last_snapshot_ms: float = 0.0
var link_detail: String = "离线"
var _last_pose_time: Dictionary = {}
# Coarse barrier used by co-op testing (and by a future "wait for the crew"
# prompt): the client reports which checkpoint it has reached, the host waits.
var client_stage: int = 0

func setup(owner_stage: Node3D) -> void:
	stage = owner_stage
	process_physics_priority = 60

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	slots[1] = {"peer": 1, "connected": true, "name": "玩家 1", "since": 0.0}
	# Unified-session adoption: when the SessionHub autoload has already opened
	# the single ENet socket (campaign host/client run), reuse it instead of
	# creating a second peer. One process keeps exactly one multiplayer_peer.
	if _adopt_session_if_present():
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var address: String = "127.0.0.1"
	for index: int in range(args.size()):
		match str(args[index]):
			"--port":
				if index + 1 < args.size():
					port = int(args[index + 1])
			"--host", "--coop-host":
				start_host()
			"--join", "--coop-client":
				if index + 1 < args.size() and not str(args[index + 1]).begins_with("--"):
					address = str(args[index + 1])
				start_client(address)
	# A plain launch stays offline: the single-player chapter is unchanged.

# ---------------------------------------------------------------------------
# Unified-session adoption (五幕整合：一个进程 = 一个 ENet peer)
# ---------------------------------------------------------------------------
# The SessionHub autoload (campaign core) owns the socket. When it is already
# running (host or client), Act 23 binds to THAT peer instead of opening its own
# port 26831. The chapter keeps its proven slot-based RPC surface (push_pose /
# send_action / sync_world / ...) but rides the shared socket, so player
# identity and the session survive across every scene change.
func _adopt_session_if_present() -> bool:
	if not (multiplayer.multiplayer_peer is ENetMultiplayerPeer):
		return false
	_adopted_session = true
	if multiplayer.is_server():
		mode = "host"
		local_slot = 1
		if stage != null:
			_reconcile_host_roster()
		else:
			call_deferred("_reconcile_host_roster")
		_set_link("host", "主机 · 统一会话 socket")
		print("COOP_ADOPTED session host")
	else:
		mode = "client"
		local_slot = _session_local_pid()
		if stage != null:
			_reconcile_client_roster()
		else:
			call_deferred("_reconcile_client_roster")
		_set_link("client", "客户端 · 统一会话（席位 %d 待定）" % local_slot)
		print("COOP_ADOPTED session client local_slot=", local_slot)
	return true


func _session_local_pid() -> int:
	var root: Node = Engine.get_main_loop().root
	var hub: Node = root.get_node_or_null("/root/SessionHub") if root != null else null
	var session: Node = hub.get_node_or_null("CoopSession") if hub != null else null
	if session == null:
		return 2
	return maxi(int(session.get("local_pid")), 2)


func _reconcile_host_roster() -> void:
	if stage == null:
		return
	# Seed peer->slot from the SessionHub pid map so both ends agree on identity
	# without a second join handshake. pid and slot share the 1..4 numbering.
	var root: Node = Engine.get_main_loop().root
	var hub: Node = root.get_node_or_null("/root/SessionHub") if root != null else null
	var net_node: Node = hub.get("net") as Node if hub != null and hub.get("net") != null else null
	var pid_map: Dictionary = (net_node.get("_peer_pid") as Dictionary) if net_node != null else {}
	for peer: int in multiplayer.get_peers():
		var pid: int = int(pid_map.get(peer, 0))
		if pid == 0:
			pid = _next_slot
			_next_slot += 1
		peer_to_slot[peer] = pid
		if not slots.has(pid):
			slots[pid] = {"peer": peer, "connected": true, "name": "玩家 %d" % pid, "since": 0.0}
			stage.call("net_spawn_remote", pid, _join_spawn(pid))
			_send_snapshot_to(peer)
	_next_slot = maxi(_next_slot, int(slots.size()) + 1)
	print("COOP_ADOPTED roster slots=", slots.keys())


func _reconcile_client_roster() -> void:
	if stage == null:
		return
	var slot: int = maxi(1, local_slot)
	slots[slot] = {"peer": 0, "connected": true, "name": "玩家 %d" % slot, "since": 0.0}
	stage.call("net_set_local_slot", slot, _join_spawn(slot))
	_set_link("client", "客户端 · 统一会话（席位 %d）" % slot)
	print("COOP_ADOPTED client local_slot=", slot)

# --- session lifecycle ------------------------------------------------------

func start_host() -> bool:
	if mode != "offline":
		return false
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		_set_link("offline", "主机创建失败：%s" % error_string(error))
		return false
	multiplayer.multiplayer_peer = peer
	mode = "host"
	local_slot = 1
	_set_link("host", "主机 · 端口 %d" % port)
	print("COOP_HOST_READY ", port)
	return true

func start_client(address: String = "127.0.0.1") -> bool:
	if mode != "offline":
		return false
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, port)
	if error != OK:
		_set_link("offline", "连接失败：%s" % error_string(error))
		return false
	multiplayer.multiplayer_peer = peer
	mode = "connecting"
	_welcome_clock = 0.0
	_set_link("connecting", "正在连接 %s:%d" % [address, port])
	print("COOP_JOIN_ATTEMPT ", address, ":", port)
	return true

func close_session() -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "offline"
	local_slot = 1
	peer_to_slot.clear()
	slots.clear()
	slots[1] = {"peer": 1, "connected": true, "name": "玩家 1", "since": 0.0}
	_next_slot = 2
	_sequence = 0
	_last_pose_time.clear()
	_set_link("offline", "离线")

func _set_link(next_mode: String, detail: String) -> void:
	link_detail = detail
	link_changed.emit(next_mode, detail)

func is_host() -> bool:
	return mode == "host" or mode == "offline"

func roster_rows() -> Array:
	var rows: Array = []
	var keys: Array = slots.keys()
	keys.sort()
	for slot: int in keys:
		var entry: Dictionary = slots[slot] as Dictionary
		rows.append([slot, bool(entry.get("connected", false)), str(entry.get("name", ""))])
	return rows

func connected_slots() -> Array:
	var out: Array = []
	var keys: Array = slots.keys()
	keys.sort()
	for slot: int in keys:
		if bool((slots[slot] as Dictionary).get("connected", false)):
			out.append(slot)
	return out

# --- host: peer management --------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if mode != "host":
		return
	var slot: int = 0
	for candidate: int in range(2, MAX_PLAYERS + 1):
		if not slots.has(candidate):
			slot = candidate
			break
	if slot == 0:
		print("COOP_REFUSED_FULL ", id)
		reject_join.rpc_id(id, "房间已满（4 人）")
		return
	slots[slot] = {"peer": id, "connected": true, "name": "玩家 %d" % slot, "since": float(stage.get("clock"))}
	peer_to_slot[id] = slot
	stage.call("net_spawn_remote", slot, _join_spawn(slot))
	# The newcomer needs the role list, its slot and the current world state in
	# one reliable message before the first unreliable snapshot can land.
	welcome.rpc_id(id, slot, roster_rows(), _join_spawn(slot))
	roster_sync.rpc(roster_rows())
	_send_snapshot_to(id)
	print("COOP_PEER_JOINED ", id, " slot=", slot)

func _on_peer_disconnected(id: int) -> void:
	if mode != "host":
		return
	var slot: int = int(peer_to_slot.get(id, 0))
	if slot == 0:
		return
	peer_to_slot.erase(id)
	_last_pose_time.erase(slot)
	slots.erase(slot)
	stage.call("net_release_slot", slot)
	stage.call("net_despawn_remote", slot)
	roster_sync.rpc(roster_rows())
	stage.set("feedback", "玩家 %d 已离开 · 其抓扶/绞盘/货物占用已释放，其他人可以继续。" % slot)
	print("COOP_PEER_LEFT ", id, " slot=", slot)

func _on_connected_to_server() -> void:
	mode = "client"
	_welcome_clock = 0.0
	_set_link("client", "已连接 · 等待主机分配席位")
	print("COOP_CLIENT_CONNECTED")

func _on_connection_failed() -> void:
	_set_link("offline", "连接失败：房间未开、已满或地址/端口不通")
	print("COOP_CONNECTION_FAILED")
	close_session()

func _on_server_disconnected() -> void:
	_set_link("disconnected", "主机已退出")
	print("COOP_SERVER_LOST")
	close_session()

func _join_spawn(for_slot: int = 1) -> Vector3:
	# A late joiner is placed on the boarding platform while the cart is parked,
	# and on the open near-side deck once the cart is already away from the dock.
	# `for_slot` is what keeps a 3/4-player crew from being spawned inside itself:
	# see DOCK_SPAWN_SPOTS / DECK_SPAWN_SPOTS above.
	var dock_spot: Vector3 = DOCK_SPAWN_SPOTS.get(for_slot, Vector3.ZERO) as Vector3
	if stage == null:
		return SPAWN_POINT + dock_spot
	var cart: Node3D = stage.get("cart") as Node3D
	if cart == null:
		return SPAWN_POINT + dock_spot
	if float(cart.get("distance")) > 2.0:
		return cart.to_global(DECK_SPAWN_SPOTS.get(for_slot, DECK_SPAWN_SPOTS[1]) as Vector3)
	return SPAWN_POINT + dock_spot

@rpc("authority", "call_remote", "reliable")
func reject_join(reason: String) -> void:
	_set_link("offline", reason)
	(stage.get("hud") as CanvasLayer).call("set_link_text", reason)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "offline"

@rpc("authority", "call_remote", "reliable")
func welcome(slot: int, rows: Array, spawn: Vector3) -> void:
	local_slot = slot
	_apply_roster(rows)
	stage.call("net_set_local_slot", slot, spawn)
	_set_link("client", "已加入 · 席位 %d" % slot)
	print("COOP_WELCOME slot=", slot)

@rpc("authority", "call_remote", "reliable")
func roster_sync(rows: Array) -> void:
	_apply_roster(rows)

func _apply_roster(rows: Array) -> void:
	var incoming: Dictionary = {}
	for row: Array in rows:
		var slot: int = int(row[0])
		incoming[slot] = {"peer": 0, "connected": bool(row[1]), "name": str(row[2]), "since": 0.0}
	# Host's own slot keeps its peer mapping.
	if incoming.has(1) and slots.has(1):
		(incoming[1] as Dictionary)["peer"] = (slots[1] as Dictionary).get("peer", 1)
	slots = incoming
	if stage != null:
		stage.call("net_roster_changed", slots)

# --- host: inbound RPCs -----------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func push_pose(at: Vector3, yaw: float, motion: Vector3, grip: int, carrying: int) -> void:
	if mode != "host" or not is_inside_tree():
		return
	# A pose RPC can arrive in the frame the Act23 scene is being freed. The
	# node then has no MultiplayerAPI; drop the packet instead of erroring.
	var ml: MultiplayerAPI = multiplayer
	if ml == null:
		return
	var sender: int = ml.get_remote_sender_id()
	var slot: int = int(peer_to_slot.get(sender, 0))
	if slot == 0:
		return
	if not at.is_finite() or not is_finite(yaw) or not motion.is_finite():
		rejected_poses += 1
		return
	# Sanity box: the chapter lives between the dock, the bay and the tunnel.
	if absf(at.x) > 130.0 or at.y < -12.0 or at.y > 30.0 or absf(at.z) > 40.0:
		rejected_poses += 1
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var last: float = float(_last_pose_time.get(slot, now - 0.05))
	if at.distance_to(stage.call("net_slot_position", slot) as Vector3) > 12.0 * maxf(0.05, now - last) + 2.5:
		# A teleport is not a pose update. The level's own rescue is the only
		# legitimate teleport and it happens host-side.
		rejected_poses += 1
		return
	_last_pose_time[slot] = now
	stage.call("net_apply_remote_pose", slot, at, yaw, motion.limit_length(12.0), grip, carrying)

@rpc("any_peer", "call_remote", "reliable")
func send_action(action: String, token: int) -> void:
	if mode != "host":
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var slot: int = int(peer_to_slot.get(sender, 0))
	if slot == 0:
		rejected_actions += 1
		return
	var ok: bool = bool(stage.call("request_action", action, slot))
	if not ok:
		rejected_actions += 1
	print("COOP_ACTION slot=", slot, " action=", action, " ok=", ok)
	action_result.rpc_id(sender, token, ok, str(stage.get("feedback")), int(stage.get("action_revision")))

@rpc("authority", "call_remote", "reliable")
func action_result(token: int, ok: bool, feedback: String, revision: int) -> void:
	stage.set("feedback", feedback)
	stage.set("action_revision", revision)
	stage.set("last_action_ok", ok)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func push_console(haul: bool, payout: bool, creep: bool) -> void:
	if mode != "host":
		return
	var slot: int = int(peer_to_slot.get(multiplayer.get_remote_sender_id(), 0))
	if slot == 0:
		return
	stage.call("net_console_input", slot, haul, payout, creep)

@rpc("any_peer", "call_remote", "reliable")
func request_reset_net() -> void:
	if mode != "host":
		return
	stage.call("reset_run")
	do_reset.rpc()

@rpc("authority", "call_remote", "reliable")
func do_reset() -> void:
	stage.call("net_on_reset")

@rpc("authority", "call_remote", "reliable")
func notify(text: String) -> void:
	stage.set("feedback", text)

@rpc("any_peer", "call_remote", "reliable")
func report_stage(stage_index: int) -> void:
	if mode != "host":
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if int(peer_to_slot.get(sender, 0)) == 0:
		return
	client_stage = maxi(client_stage, stage_index)
	print("COOP_STAGE_REPORT from=", sender, " stage=", client_stage)
	host_stage.rpc(client_stage)

# Explicit sender: calling an @rpc function directly runs it locally, which is
# exactly the mistake that makes a "barrier" that never leaves the client.
func report_stage_remote(stage_index: int) -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		report_stage.rpc_id(1, stage_index)

# Host -> client checkpoint ("the drum is stopped, you may grab the wheel").
# Needed because both devices are physical: a player who grabs the guide mid-haul
# legitimately blocks the drum, so the two jobs have to be ordered out loud.
func host_signal(stage_index: int) -> void:
	if mode != "host":
		return
	stage.set("host_stage_mirror", stage_index)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		host_stage.rpc(stage_index)

@rpc("authority", "call_remote", "reliable")
func host_stage(stage_index: int) -> void:
	stage.set("host_stage_mirror", stage_index)
	print("COOP_STAGE_ACK ", stage_index)

# --- host: outbound snapshots ----------------------------------------------

func _physics_process(delta: float) -> void:
	if _handoff_closing or not is_inside_tree():
		return
	if mode == "connecting":
		_welcome_clock += delta
		if _welcome_clock > WELCOME_TIMEOUT:
			_set_link("offline", "连接超时：主机没有响应")
			close_session()
		return
	if mode == "client":
		_client_tick(delta)
		return
	if mode != "host":
		return
	if slots.size() <= 1:
		return
	_timer += delta
	if _timer < 1.0 / SNAPSHOT_HZ:
		return
	_timer = 0.0
	_broadcast_snapshot()

func _broadcast_snapshot() -> void:
	var packet: PackedByteArray = stage.call("net_snapshot_packet") as PackedByteArray
	sync_world.rpc(packet)
	snapshots_sent += 1

func _send_snapshot_to(peer: int) -> void:
	var packet: PackedByteArray = stage.call("net_snapshot_packet") as PackedByteArray
	sync_world.rpc_id(peer, packet)
	snapshots_sent += 1

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_world(packet: PackedByteArray) -> void:
	if mode != "client":
		return
	if packet.size() < 5 or packet.size() > 16384:
		return
	var started: int = Time.get_ticks_usec()
	var length: int = packet.decode_u32(0)
	if length < 1 or length > 131072:
		return
	var decoded: Variant = bytes_to_var(packet.slice(4).decompress(length, FileAccess.COMPRESSION_FASTLZ))
	if not decoded is Dictionary:
		return
	stage.call("net_apply", decoded as Dictionary)
	snapshots_received += 1
	max_snapshot_bytes = maxi(max_snapshot_bytes, packet.size())
	last_snapshot_ms = float(Time.get_ticks_usec() - started) / 1000.0

func _client_tick(delta: float) -> void:
	if _handoff_closing or not is_inside_tree():
		return
	# The Act23 node can outlive its multiplayer context by a frame during the
	# scene switch; never fire an RPC into a missing/closed peer.
	var ml: MultiplayerAPI = multiplayer
	if ml == null:
		return
	var peer: MultiplayerPeer = ml.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	# Own pose goes up at the same rate the host publishes, so the two sides
	# never disagree about who moved first.
	_timer += delta
	if _timer < 1.0 / SNAPSHOT_HZ:
		return
	_timer = 0.0
	var actor: CharacterBody3D = stage.get("player") as CharacterBody3D
	if actor == null:
		return
	push_pose.rpc_id(1, actor.global_position, actor.rotation.y, actor.velocity,
		int(actor.get("grip_id")), int(actor.get("carrying")))
	if bool(stage.call("net_console_owned_by_local")):
		push_console.rpc_id(1, Input.is_action_pressed("winch_haul"),
			Input.is_action_pressed("winch_payout"), Input.is_action_pressed("winch_creep"))

# --- rescue (host -> client) ------------------------------------------------
# The host owns the rescue decision (it owns the cart motor and the landing
# spots), but only a client's own process integrates its character: a host-side
# teleport of the remote proxy was overwritten by that client's next 20 Hz pose
# and the client was never moved, so an MP rescue only incremented a counter on
# the host. The rescue now travels as a reliable command. The host moves its
# proxy first (moving_stage.rescue_player), which is what lets the client's
# post-rescue pose pass the anti-teleport check in push_pose().
@rpc("authority", "call_remote", "reliable")
func rescue_to(at: Vector3) -> void:
	if mode != "client" or stage == null or not is_inside_tree():
		return
	var actor: CharacterBody3D = stage.get("player") as CharacterBody3D
	if actor == null or not is_instance_valid(actor):
		return
	actor.call("restore_at", at)
	actor.set("recovery_count", int(actor.get("recovery_count")) + 1)
	actor.set("interaction_locked", false)
	actor.set("fp_console", false)
	print("COOP_RESCUE_APPLIED ", at)

# Host-side sender. `slot` is the production seat id (1..4), never an ENet id.
func rescue_remote(slot: int, at: Vector3) -> void:
	if mode != "host":
		return
	var entry: Dictionary = slots.get(slot, {}) as Dictionary
	var peer: int = int(entry.get("peer", 0))
	if peer <= 1:
		return
	rescue_to.rpc_id(peer, at)

func request_action(action: String) -> bool:
	if mode == "client":
		_sequence += 1
		send_action.rpc_id(1, action, _sequence)
		return true
	return bool(stage.call("request_action", action, local_slot))

func request_reset() -> void:
	if mode == "client":
		request_reset_net.rpc_id(1)
		return
	stage.call("reset_run")

## Called by the Act23 stage when the real end-of-chapter hand-off starts.
## The chapter is finished; stop its pose/action stream before the scene swap.
func begin_handoff() -> void:
	_handoff_closing = true


func _exit_tree() -> void:
	_handoff_closing = true
	# Act 23 -> Act 04 scene switch: the shared SessionHub peer must survive.
	# Only a chapter that opened its own socket (standalone Act23 run) owns the
	# close. Closing the adopted peer here disconnected the client and left
	# Act04 with an OfflineMultiplayerPeer while SessionHub still reported online.
	if _adopted_session:
		print("COOP_RELEASE adopted session kept alive for the chapter hand-off")
		return
	close_session()
