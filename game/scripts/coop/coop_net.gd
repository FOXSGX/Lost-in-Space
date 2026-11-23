class_name CoopNet
extends Node

## Host-authoritative ENet transport for the two-instance Resonance 05 slice.
##
## Authority model
## ---------------
## * The host owns every machine: carts, core, stabilisers, catwalk tilt/pins,
##   brake, damper, isolation carriage, surge director, story stage and the
##   participation ledger.
## * Each process owns its own player transform and sends it at 20 Hz. The host
##   mirrors it to the other peer and renders a RemotePlayer for it.
## * Machine use is claimed: a client asks the host for a machine, the host
##   grants or refuses, and the client's W/S stream is applied by the host to
##   that machine. Nothing about a machine is client-authoritative.
## * A disconnect releases every claim the peer held and marks the participant
##   as disconnected (never as completed).

signal peer_joined(pid: int)
signal peer_left(pid: int)
signal connected_changed(online: bool)

const PORT_DEFAULT := 9877
const SNAPSHOT_HZ := 15.0
const STATE_HZ := 20.0
const SNAPSHOT_TIMEOUT_MS := 750
const SNAPSHOT_RESYNC_MIN_INTERVAL_MS := 2000
const SNAPSHOT_RESYNC_MAX := 3
const ACT5_STATE_MAX_FIELDS := 24
const ACT5_ACTION_IDS: Array[String] = ["isolation_pin", "lock", "data"]
const SnapshotWireScript := preload("res://scripts/coop/snapshot_wire.gd")
const SnapshotAssemblerScript := preload("res://scripts/coop/snapshot_assembler.gd")

var session: CoopSession
var level: LevelBuilder
var story: StoryDirector
var surge: SurgeDirector
var hud: GameHud
var player: PlayerController
var audio: AudioDirector

var is_host: bool = false
var local_pid: int = 1
var online: bool = false
var remote_root: Node3D
var remotes: Dictionary = {}        # pid -> RemotePlayer
var _state_clock: float = 0.0
var _snap_clock: float = 0.0
var _seq: int = 0
var reset_seq: int = 0
var _peer_pid: Dictionary = {}      # enet id -> pid
var _next_pid: int = 2
var _last_snapshot_ms: int = 0
var _last_snapshot_seq: int = -1
var _snapshot_assembler = SnapshotAssemblerScript.new()
var _snapshot_bootstrap_assembler = SnapshotAssemblerScript.new()
var _snapshot_resync_count: int = 0
var _snapshot_next_resync_ms: int = 0
var _last_snapshot_reject_ms: int = 0
var _snapshot_resync_rx_ms: Dictionary = {}
var _last_reset_request_ms: int = 0
var _snapshot_stats: Dictionary = {
	"snapshots_sent": 0, "packets_sent": 0, "chunks_sent": 0,
	"packet_bytes_max": 0, "raw_bytes_max": 0, "packed_bytes_max": 0,
	"apply": 0, "bootstrap_apply": 0, "rejects": 0, "stale": 0,
	"partial_drops": 0, "timeouts": 0, "resync_requests": 0,
	"resync_served": 0, "malformed_packets": 0, "last_apply_seq": -1,
	"last_parts": 0, "last_packet_bytes": 0,
}
var _client_stage: int = 0
var _pending_welcome: bool = false
var _warned: bool = false
var _signals_wired: bool = false

# --- Act 4 (Resonance 04) bridge ------------------------------------------
# The unified CoopNet carries the Act 4 slice on top of the same ENet peer /
# session. Act 4 registers a handler object (the ResonanceGame node) with
# bind_act4(); while active, `sync_snapshot` is not used (Act 4 ships its own
# `act4_sync` snapshot built by the game) and the Act 5 loop is left untouched.
var act4_game: Node = null
var _act4_state_clock: float = 0.0
var _act4_snap_clock: float = 0.0
var _act4_snapshot_assembler = SnapshotAssemblerScript.new()
var _last_act4_snap: Dictionary = {}
var _act4_last_sent_ms: int = 0

# --- Act 1 (Resonance 01) bridge -------------------------------------------
# Same "one peer, per-act handler" pattern as Act 4, but for Act 01's module.
# The Act1NetFacade (module) registers itself with bind_act1(); the unified peer
# then forwards Act01-specific client intents and host grants/snapshots through
# the documented act1_* surface (see MODULE_INTEGRATION_CONTRACT §Act01). While
# Act 1 is bound, its own loops run and the Act 4 / Act 5 loops stay dormant.
var act1_facade: Node = null
var _act1_state_clock: float = 0.0
var _act1_snap_clock: float = 0.0
var _act1_last_reset_ms: int = 0

# --- Act 01 join handshake ---------------------------------------------------
# The host used to push `act1_bootstrap`/`act1_welcome` on ENet `peer_connected`,
# i.e. before the client had an Act01 facade. The client's handlers dropped both
# and nothing retried, so the seat was never applied (a client rendered itself
# as a remote avatar). The protocol is now explicit and idempotent:
#   client: Act1NetFacade bound -> `act1_client_ready`
#   host:   register the seat once, then `act1_welcome` -> `act1_bootstrap`
# A ready that arrives before the host's Act01 bind is kept (bounded TTL) and
# served when the host binds; a lost ready is retried by the client.
const ACT1_PROTOCOL_VERSION := 2
const ACT1_READY_RETRY_MS := 500
const ACT1_READY_RETRY_SLOW_MS := 2000
const ACT1_READY_MAX_ATTEMPTS := 60
const ACT1_READY_TTL_MS := 15000
const ACT1_JOIN_BUFFER_TTL_MS := 15000

# --- Act 01 split wire protocol ---------------------------------------------
# Every unreliable Act01 packet must stay below the ENet MTU (1392). 1200 leaves
# headroom for the RPC envelope and small future fields. Continuous motion goes
# on unreliable channels; discrete task state goes reliable (change + keyframe).
const ACT1_POSE_HZ := 15.0
const ACT1_DYNAMIC_HZ := 10.0
const ACT1_STATE_KEYFRAME_MS := 1000
const ACT1_STATE_MIN_INTERVAL_MS := 80
const ACT1_MAX_UNRELIABLE_BYTES := 1200
const ACT1_STATE_STALE_MS := 3000
const ACT1_RESYNC_MIN_INTERVAL_MS := 2000
const ACT1_RESYNC_MAX := 5

var _act1_pose_clock: float = 0.0
var _act1_dynamic_clock: float = 0.0
var _act1_state_seq: int = 0
var _act1_last_state_sig: int = 0
var _act1_last_state_ms: int = 0
var _act1_state_dirty: bool = false
var _act1_last_pose_seq: int = -1
var _act1_last_dynamic_seq: int = -1
var _act1_last_state_seq: int = -1
var _act1_last_state_rx_ms: int = 0
var _act1_resync_count: int = 0
var _act1_next_resync_ms: int = 0

var _act1_ready_peers: Dictionary = {}      # enet id -> msec of the last ready
var _act1_registered_pids: Dictionary = {}  # pid -> true, for the current visit
var _act1_welcomed: bool = false
var _act1_bootstrapped: bool = false
var _act1_welcome_pid: int = 0
var _act1_ready_attempts: int = 0
var _act1_next_ready_ms: int = 0
var _act1_pending_welcome: int = 0
var _act1_pending_welcome_ms: int = 0
var _act1_pending_bootstrap: Dictionary = {}
var _act1_pending_bootstrap_ms: int = 0
var _act1_last_msg_seq: int = -1

# --- Act 01 wire observability ---------------------------------------------
# O(1) counters, always updated (integers only). They are the auditable source
# for byte budgets, send/receive rates and lifecycle violations; the per-packet
# trace lines are opt-in via `--net-trace` so a normal build stays quiet.
var _act1_trace: bool = false
var _act1_stats: Dictionary = {
	"protocol_version": 2,          # 1 = legacy full snapshot, 2 = pose/state split
	"mode": "split",
	"pose_sends": 0, "pose_bytes_max": 0, "pose_bytes_total": 0, "pose_over_budget": 0,
	"pose_split_sends": 0, "pose_recv": 0, "pose_recv_bytes_max": 0, "pose_stale": 0,
	"dynamic_sends": 0, "dynamic_bytes_max": 0, "dynamic_recv": 0, "dynamic_stale": 0,
	"state_sends": 0, "state_bytes_max": 0, "state_keyframes": 0, "state_recv": 0,
	"state_dup_stale": 0, "unwelcomed_drops": 0, "stale_snapshot_drops": 0,
	"flags_mismatch": 0, "dynamic_recv_stale": 0, "state_stale": 0,
	"legacy_snapshot_sends": 0, "legacy_snapshot_bytes_max": 0, "legacy_snapshot_recv": 0,
	"bootstrap_sends": 0, "bootstrap_recv": 0, "bootstrap_duplicates": 0,
	"welcome_sends": 0, "welcome_recv": 0, "welcome_duplicates": 0,
	"ready_recv": 0, "ready_duplicates": 0, "ready_retries": 0,
	"seats_registered": 0, "seats_released": 0,
	"resync_requests": 0, "resync_served": 0,
	"send_packets": 0, "send_bytes_total": 0, "send_bytes_max": 0,
	"recv_packets": 0, "recv_bytes_total": 0, "recv_bytes_max": 0, "recv_gap_max_ms": 0,
	"stale_builds": 0, "sends_after_exit": 0, "last_send_stage_in_tree": true,
	"last_send_ms": 0, "last_recv_ms": 0,
}


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	_act1_trace = args.has("--net-trace")


## Drop any partially assembled Act05 snapshot when a scene/session boundary is
## crossed. The next valid sequence starts from a clean slate — including the
## replay watermark: the host's seq restarts at 0 after a restart/reconnect, and
## keeping the old watermark would reject every new packet as "stale".
func _reset_snapshot_wire_state() -> void:
	_snapshot_assembler.reset_session()
	_snapshot_bootstrap_assembler.reset_session()
	_act4_snapshot_assembler.reset_session()
	_last_act4_snap.clear()
	_act4_last_sent_ms = 0
	_last_snapshot_seq = -1
	_snapshot_resync_count = 0
	_snapshot_next_resync_ms = 0
	_snapshot_resync_rx_ms.clear()


func snapshot_stats() -> Dictionary:
	var out: Dictionary = _snapshot_stats.duplicate(true)
	out["last_applied_seq"] = _last_snapshot_seq
	out["rx"] = (_snapshot_assembler.stats as Dictionary).duplicate(true)
	out["bootstrap_rx"] = (_snapshot_bootstrap_assembler.stats as Dictionary).duplicate(true)
	return out


## Snapshot of the Act 01 wire counters (test/observability surface).
func act1_stats() -> Dictionary:
	var out: Dictionary = _act1_stats.duplicate(true)
	out["bound"] = _act1_bound()
	out["local_pid"] = local_pid
	out["is_host"] = is_host
	out["online"] = online
	out["peers"] = multiplayer.get_peers().size()
	out["welcomed"] = _act1_welcomed
	out["bootstrapped"] = _act1_bootstrapped
	out["welcome_pid"] = _act1_welcome_pid
	out["ready_attempts"] = _act1_ready_attempts
	out["ready_peers"] = _act1_ready_peers.size()
	out["registered_pids"] = _act1_registered_pids.keys()
	out["last_msg_seq"] = _act1_last_msg_seq
	out["last_pose_seq"] = _act1_last_pose_seq
	out["last_dynamic_seq"] = _act1_last_dynamic_seq
	out["last_state_seq"] = _act1_last_state_seq
	out["state_seq"] = _act1_state_seq
	out["resync_count"] = _act1_resync_count
	out["pending_welcome"] = _act1_pending_welcome
	out["pending_bootstrap"] = not _act1_pending_bootstrap.is_empty()
	return out


func _act1_stat(key: String, delta: int = 1) -> void:
	_act1_stats[key] = int(_act1_stats.get(key, 0)) + delta


func _act1_stat_max(key: String, value: int) -> void:
	if value > int(_act1_stats.get(key, 0)):
		_act1_stats[key] = value


func _act1_trace_line(line: String) -> void:
	if _act1_trace:
		print(line)


func _act1_note_recv(bytes: int) -> void:
	var now: int = Time.get_ticks_msec()
	var last: int = int(_act1_stats.get("last_recv_ms", 0))
	if last > 0:
		_act1_stat_max("recv_gap_max_ms", now - last)
	_act1_stats["last_recv_ms"] = now
	_act1_stat("recv_packets")
	_act1_stats["recv_bytes_total"] = int(_act1_stats["recv_bytes_total"]) + bytes
	_act1_stat_max("recv_bytes_max", bytes)



func bind(p_session: CoopSession, p_level: LevelBuilder, p_story: StoryDirector, p_surge: SurgeDirector, p_hud: GameHud, p_player: PlayerController, p_audio: AudioDirector) -> void:
	# A new Act05 visit must not inherit a partial snapshot from a prior scene.
	_reset_snapshot_wire_state()
	# Rebinding happens on every scene change (Act 4 → Act 5). The ENet peer
	# and session survive on the SessionHub autoload; only the scene-local
	# world references change. Drop stale scene-owned remotes from a past act.
	name = "CoopNet"
	session = p_session
	level = p_level
	story = p_story
	surge = p_surge
	hud = p_hud
	player = p_player
	audio = p_audio
	# Binding Act 5 means the Act 4 scene is gone. Drop its handler explicitly
	# (the authoritative unbind is ResonanceGame._exit_tree) so a scene switch
	# can never leave this node pointing at a torn-down Act 4 world.
	_unbind_act4_node()
	# Same rule for Act 01: a scene switch must never leave the Act 1 loop
	# pointed at a world that already left the tree.
	_unbind_act1_node()
	_clear_remotes()
	remote_root = Node3D.new()
	remote_root.name = "RemotePlayers"
	add_child(remote_root)
	session.net_online = online


func _clear_remotes() -> void:
	remotes.clear()
	if remote_root != null and is_instance_valid(remote_root):
		# Free immediately: an act hand-off re-creates the container in the same
		# frame, and a deferred free would leave two "RemotePlayers" nodes alive
		# at once. Nothing here runs inside the container's own callbacks.
		remote_root.free()
	remote_root = null


var _wired_as_host: bool = false


func _clear_signal_wiring() -> void:
	if not _signals_wired:
		return
	var host_sigs: Array[Array] = [
		["peer_connected", Callable(self, "_on_peer_connected")],
		["peer_disconnected", Callable(self, "_on_peer_disconnected")],
	]
	var client_sigs: Array[Array] = [
		["connected_to_server", Callable(self, "_on_connected")],
		["connection_failed", Callable(self, "_on_connection_failed")],
		["server_disconnected", Callable(self, "_on_server_lost")],
	]
	for pair: Array in host_sigs + client_sigs:
		var sig: String = str(pair[0])
		var cb: Callable = pair[1] as Callable
		if multiplayer.is_connected(sig, cb):
			multiplayer.disconnect(sig, cb)
	_signals_wired = false


func _ensure_signal_wiring() -> void:
	# Wire only the signals this role uses. The host receives peer_connected /
	# peer_disconnected; the client receives connected_to_server / connection
	# failed / server disconnected. Wiring peer_connected on the client too
	# would make it run _on_peer_connected (which calls the authority-only
	# sync_bootstrap) the moment it joins — an RPC permission error.
	if _signals_wired and _wired_as_host == is_host:
		return
	_clear_signal_wiring()
	_signals_wired = true
	_wired_as_host = is_host
	if is_host:
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	else:
		if not multiplayer.connected_to_server.is_connected(_on_connected):
			multiplayer.connected_to_server.connect(_on_connected)
		if not multiplayer.connection_failed.is_connected(_on_connection_failed):
			multiplayer.connection_failed.connect(_on_connection_failed)
		if not multiplayer.server_disconnected.is_connected(_on_server_lost):
			multiplayer.server_disconnected.connect(_on_server_lost)


func start_host(port: int = PORT_DEFAULT) -> int:
	# SessionHub boots the peer before the first scene; adopt it if present.
	# NOTE: the SceneTree default is an OfflineMultiplayerPeer, not null, so we
	# must test the concrete class, not "!= null".
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		is_host = true
		local_pid = 1
		online = true
		session.net_online = true
		session.setup(1, true)
		_ensure_signal_wiring()
		print("COOP_NET adopting running host peer (port %d)" % port)
		connected_changed.emit(true)
		return OK
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: int = peer.create_server(port, CoopSession.MAX_PLAYERS - 1)
	if error != OK:
		push_error("ENet server failed: %d" % error)
		return error
	multiplayer.multiplayer_peer = peer
	is_host = true
	local_pid = 1
	online = true
	session.net_online = true
	session.setup(1, true)
	_ensure_signal_wiring()
	print("COOP_NET host listening on %d" % port)
	connected_changed.emit(true)
	return OK


func start_client(address: String = "127.0.0.1", port: int = PORT_DEFAULT) -> int:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		is_host = false
		online = true
		# Keep the seat this process already holds. Act05's app calls
		# SessionHub.start(false, ...) again on entry; resetting to 2 there made a
		# 3rd/4th client switch identity mid-campaign (observed: pid3 became pid2
		# when Act04 handed off to Act05).
		if local_pid <= 0:
			local_pid = 2
		session.net_online = true
		session.setup(local_pid, false)
		_ensure_signal_wiring()
		print("COOP_NET adopting running client peer (%s:%d) pid=%d" % [address, port, local_pid])
		return OK
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: int = peer.create_client(address, port)
	if error != OK:
		push_error("ENet client failed: %d" % error)
		return error
	multiplayer.multiplayer_peer = peer
	is_host = false
	online = true
	if local_pid <= 0:
		local_pid = 2
	session.net_online = true
	session.setup(local_pid, false)
	_ensure_signal_wiring()
	print("COOP_NET client dialing %s:%d" % [address, port])
	return OK


func shutdown() -> void:
	_clear_signal_wiring()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	online = false
	if session != null:
		session.net_online = false


func is_online() -> bool:
	return online


func peer_count() -> int:
	if not online:
		return 1
	return multiplayer.get_peers().size() + 1


# ---------------------------------------------------------------------------
# Client -> host messages
# ---------------------------------------------------------------------------

## Client helper: send a claim request to the host. Calling the @rpc method
## directly would only run it locally, which is why every rig goes through this.
func submit_claim(machine_id: String) -> void:
	if is_host:
		return
	request_claim.rpc_id(1, machine_id)


func submit_release(machine_id: String) -> void:
	if is_host:
		return
	release_claim.rpc_id(1, machine_id)


@rpc("any_peer", "call_remote", "reliable")
func request_claim(machine_id: String) -> void:
	if not is_host:
		return
	var pid: int = _pid_for_peer(multiplayer.get_remote_sender_id())
	if pid == 0:
		print("COOP_NET claim rejected reason=unknown_sender sender=%d" % multiplayer.get_remote_sender_id())
		return
	if machine_id.length() == 0 or machine_id.length() > 32 or not session.is_known_machine(machine_id):
		print("COOP_NET claim rejected reason=unknown_machine pid=%d machine=%s" % [pid, machine_id])
		return
	var result: Dictionary = session.try_claim(machine_id, pid)
	print("COOP_NET claim pid=%d machine=%s ok=%s reason=%s" % [pid, machine_id, str(result.get("ok", false)), str(result.get("reason", ""))])
	claim_answer.rpc_id(multiplayer.get_remote_sender_id(), machine_id, bool(result.get("ok", false)), str(result.get("reason", "")))


@rpc("authority", "call_remote", "reliable")
func claim_answer(machine_id: String, ok: bool, reason: String) -> void:
	if is_host:
		return
	if not _is_authority_sender(multiplayer.get_remote_sender_id()):
		return
	if machine_id.length() == 0 or machine_id.length() > 32 or reason.length() > 256:
		return
	if ok:
		session.clear_pending_claim(machine_id)
		session.grant_local_claim(machine_id, local_pid)
	else:
		session.deny_local_claim(machine_id, reason)


@rpc("any_peer", "call_remote", "reliable")
func release_claim(machine_id: String) -> void:
	if not is_host:
		return
	var pid: int = _pid_for_peer(multiplayer.get_remote_sender_id())
	if pid != 0 and machine_id.length() <= 32:
		session.release_claim(machine_id, pid)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_axis(machine_id: String, axis: float) -> void:
	if not is_host:
		return
	var pid: int = _pid_for_peer(multiplayer.get_remote_sender_id())
	if pid == 0 or machine_id.length() > 32 or not is_finite(axis):
		return
	if session.is_known_machine(machine_id):
		session.set_axis(machine_id, pid, clampf(axis, -1.0, 1.0))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_state(state: Dictionary) -> void:
	if not is_host:
		return
	var pid: int = _pid_for_peer(multiplayer.get_remote_sender_id())
	if pid == 0:
		return
	var reason: String = _validate_act5_player_state(state)
	if reason != "":
		var now: int = Time.get_ticks_msec()
		if now - _last_snapshot_reject_ms >= 1000:
			_last_snapshot_reject_ms = now
			print("ACT5_STATE_REJECT pid=%d reason=%s" % [pid, reason])
		return
	var clean: Dictionary = state.duplicate(true)
	clean["pid"] = pid
	clean["t"] = Time.get_ticks_msec()
	session.set_player_state(pid, clean)
	_update_remote_visual(pid, clean)
	_credit_from_state(pid, clean)


@rpc("any_peer", "call_remote", "reliable")
func request_action(action: String) -> void:
	if not is_host:
		return
	var pid: int = _pid_for_peer(multiplayer.get_remote_sender_id())
	if pid == 0:
		return
	if not ACT5_ACTION_IDS.has(action):
		print("ACT5_ACTION_REJECT pid=%d reason=unknown_action action=%s" % [pid, action])
		return
	_host_apply_action(pid, action)


## Client helper: ask the host to perform an instant mechanical action. The host
## validates the player's streamed position and the machine's state first.
func submit_action(action: String) -> void:
	if is_host:
		return
	request_action.rpc_id(1, action)


func _host_apply_action(pid: int, action: String) -> void:
	var pos: Vector3 = _player_position(pid)
	match action:
		"isolation_pin":
			if pos.distance_to(level.isolation.global_position + Vector3(0, 1.2, 0)) > 5.2:
				return
			if level.core == null or not level.core.is_locked():
				return
			if level.isolation.pin_out:
				return
			level.isolation.pin_out = true
			level.isolation.pin_anim = 0.0
			level.isolation.pin_pulled.emit()
			level.isolation.message.emit("安全销已拔出。液压滑架解锁。")
			if audio != null:
				audio.play_sfx("pin_pull", level.isolation.global_position, -4.0)
			session.credit(pid, "isolation_pin", 1.0, "拔出联轴器安全销（远程）")
		"lock":
			if pos.distance_to(Vector3(0, 1.1, 8.6)) > 3.4:
				return
			if level.core == null or level.core.is_locked() or level.core.is_locking():
				return
			var result: Dictionary = level.core.request_lock()
			if bool(result.get("ok", false)):
				session.credit(pid, "lock_assist", 1.0, "启动液压锁爪（远程）")
			else:
				level.lock_rig.lock_attempt_failed.emit(str(result.get("reason", "锁定失败")))
		"data":
			if pos.distance_to(Vector3(-3.0, 1.0, -10.0)) > 3.2:
				return
			if not level.data_plinth.revealed_flag or level.data_plinth.taken:
				return
			level.data_plinth.taken = true
			level.data_plinth.area.collision_layer = 0
			if audio != null:
				audio.play_sfx("data_take", level.data_plinth.global_position, -2.0)
			level.data_plinth.data_taken.emit()
			session.credit(pid, "data_take", 1.0, "取出深空航行数据（远程）")


func _player_position(pid: int) -> Vector3:
	if pid == local_pid and player != null:
		return player.global_position
	var state: Dictionary = session.player_state(pid)
	return state.get("pos", Vector3(0, -100, 0))


@rpc("any_peer", "call_remote", "reliable")
func request_reset() -> void:
	if not is_host:
		return
	var pid: int = _pid_for_peer(multiplayer.get_remote_sender_id())
	if pid == 0 or session.status_of(pid) != ParticipationLedger.STATUS_ACTIVE:
		print("ACT5_RESET_REJECT reason=sender_or_status sender=%d pid=%d" % [
			multiplayer.get_remote_sender_id(), pid])
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_reset_request_ms < 3000:
		print("ACT5_RESET_REJECT reason=rate_limit pid=%d" % pid)
		return
	_last_reset_request_ms = now
	reset_seq += 1
	_host_reset()
	do_reset.rpc(reset_seq)


@rpc("authority", "call_remote", "reliable")
func do_reset(seq: int) -> void:
	if not _is_authority_sender(multiplayer.get_remote_sender_id()):
		print("ACT5_RESET_REJECT reason=authority_sender seq=%d" % seq)
		return
	if seq < 0 or seq > 1000000:
		print("ACT5_RESET_REJECT reason=seq_range seq=%d" % seq)
		return
	reset_seq = seq
	if player != null:
		player.force_exit_operate()
		player.stop_grab()
		player.external_hold = false
		player.clear_impaired()
	if story != null:
		story.apply_network_reset()
	if surge != null:
		surge.reset_state()
	if hud != null:
		hud.toast("主机已重置到检查点", 2.2)


# ---------------------------------------------------------------------------
# Host -> client
# ---------------------------------------------------------------------------

## Legacy single-packet path. New hosts use `sync_snapshot_part`; this remains
## for one-release compatibility and applies the same shape/sequence guards.
@rpc("authority", "call_remote", "unreliable_ordered")
func sync_snapshot(snap: Dictionary) -> void:
	if is_host:
		return
	if not _is_authority_sender(multiplayer.get_remote_sender_id()):
		_snapshot_reject("legacy_sender", -1)
		return
	if not _snapshot_shape_ok(snap):
		_snapshot_reject("legacy_shape", int(snap.get("seq", -1)))
		return
	var seq: int = int(snap.get("seq", -1))
	if seq < _last_snapshot_seq:
		_snapshot_stats["stale"] = int(_snapshot_stats["stale"]) + 1
		return
	_last_snapshot_seq = seq
	_apply_snapshot(snap)


## Legacy reliable join path. New hosts use `sync_snapshot_bootstrap_part`.
@rpc("authority", "call_remote", "reliable")
func sync_bootstrap(snap: Dictionary) -> void:
	if is_host:
		return
	if not _is_authority_sender(multiplayer.get_remote_sender_id()):
		_snapshot_reject("legacy_bootstrap_sender", -1)
		return
	if not _snapshot_shape_ok(snap):
		_snapshot_reject("legacy_bootstrap_shape", int(snap.get("seq", -1)))
		return
	var seq: int = int(snap.get("seq", -1))
	if seq < _last_snapshot_seq:
		_snapshot_stats["stale"] = int(_snapshot_stats["stale"]) + 1
		return
	_last_snapshot_seq = seq
	_snapshot_stats["bootstrap_apply"] = int(_snapshot_stats["bootstrap_apply"]) + 1
	_apply_snapshot(snap)


## Live Act05 snapshot packet (unreliable_ordered). The packet is compressed and
## sub-MTU; an incomplete sequence is discarded and the next 15 Hz tick recovers.
@rpc("authority", "call_remote", "unreliable_ordered")
func sync_snapshot_part(packet: Dictionary) -> void:
	if is_host:
		return
	if not _is_authority_sender(multiplayer.get_remote_sender_id()):
		_snapshot_reject("part_sender", int(packet.get("seq", -1)))
		return
	_accept_snapshot_packet(packet, false)


## Reliable Act05 join/resync packet. Each part travels reliably; the assembler
## still tolerates duplicate/out-of-order delivery and verifies integrity.
@rpc("authority", "call_remote", "reliable")
func sync_snapshot_bootstrap_part(packet: Dictionary) -> void:
	if is_host:
		return
	if not _is_authority_sender(multiplayer.get_remote_sender_id()):
		_snapshot_reject("bootstrap_part_sender", int(packet.get("seq", -1)))
		return
	_accept_snapshot_packet(packet, true)


## Client -> host: a partial snapshot timed out. The host re-sends the current
## authoritative state reliably to this peer. Rate-limited by the client.
@rpc("any_peer", "call_remote", "reliable")
func request_act5_snapshot_resync() -> void:
	if not is_host:
		return
	var enet_id: int = multiplayer.get_remote_sender_id()
	var pid: int = _pid_for_peer(enet_id)
	_snapshot_stats["resync_requests"] = int(_snapshot_stats["resync_requests"]) + 1
	if pid == 0 or level == null or not is_instance_valid(level):
		print("SNAPSHOT_RESYNC_REJECT sender=%d pid=%d reason=unknown_or_unbound" % [enet_id, pid])
		return
	var now: int = Time.get_ticks_msec()
	var last: int = int(_snapshot_resync_rx_ms.get(enet_id, 0))
	if now - last < 1000:
		print("SNAPSHOT_RESYNC_REJECT sender=%d pid=%d reason=rate_limit" % [enet_id, pid])
		return
	_snapshot_resync_rx_ms[enet_id] = now
	_snapshot_stats["resync_served"] = int(_snapshot_stats["resync_served"]) + 1
	print("SNAPSHOT_RESYNC pid=%d enet=%d" % [pid, enet_id])
	_send_snapshot_chunks(build_snapshot(), enet_id, true)


func _accept_snapshot_packet(packet: Dictionary, bootstrap: bool) -> void:
	var now: int = Time.get_ticks_msec()
	var packet_bytes: int = var_to_bytes(packet).size()
	_snapshot_stats["packet_bytes_max"] = maxi(
		int(_snapshot_stats["packet_bytes_max"]), packet_bytes)
	_snapshot_stats["last_packet_bytes"] = packet_bytes
	var assembler = _snapshot_bootstrap_assembler if bootstrap else _snapshot_assembler
	var result: Dictionary = assembler.accept(packet, now)
	match str(result.get("status", "")):
		"complete":
			_handle_complete_snapshot(result, bootstrap)
		"rejected":
			_snapshot_stats["malformed_packets"] = int(_snapshot_stats["malformed_packets"]) + 1
			_snapshot_reject("packet_%s" % str(result.get("reason", "invalid")), int(result.get("seq", -1)))
		"stale":
			_snapshot_stats["stale"] = int(_snapshot_stats["stale"]) + 1
		"timeout":
			_handle_snapshot_timeout(result, bootstrap)
		_:
			pass


func _handle_complete_snapshot(result: Dictionary, bootstrap: bool) -> void:
	var snap: Dictionary = (result.get("snapshot", {}) as Dictionary).duplicate(true)
	var seq: int = int(snap.get("seq", -1))
	if not _snapshot_shape_ok(snap):
		_snapshot_reject("shape", seq)
		return
	if seq < _last_snapshot_seq:
		_snapshot_stats["stale"] = int(_snapshot_stats["stale"]) + 1
		return
	var parts: int = int(result.get("parts", 1))
	_last_snapshot_seq = seq
	_snapshot_resync_count = 0
	_snapshot_next_resync_ms = 0
	_snapshot_stats["apply"] = int(_snapshot_stats["apply"]) + 1
	_snapshot_stats["last_apply_seq"] = seq
	_snapshot_stats["last_parts"] = parts
	if bootstrap:
		_snapshot_stats["bootstrap_apply"] = int(_snapshot_stats["bootstrap_apply"]) + 1
	_snapshot_stats["partial_drops"] = int(_snapshot_assembler.stats["superseded"]) \
		+ int(_snapshot_bootstrap_assembler.stats["superseded"])
	_apply_snapshot(snap)


func _handle_snapshot_timeout(result: Dictionary, bootstrap: bool) -> void:
	_snapshot_stats["timeouts"] = int(_snapshot_stats["timeouts"]) + 1
	var seq: int = int(result.get("seq", -1))
	_snapshot_reject("timeout_seq_%d" % seq, seq)
	if bootstrap or not online or is_host:
		return
	var now: int = Time.get_ticks_msec()
	if _snapshot_resync_count >= SNAPSHOT_RESYNC_MAX or now < _snapshot_next_resync_ms:
		return
	_snapshot_resync_count += 1
	_snapshot_next_resync_ms = now + SNAPSHOT_RESYNC_MIN_INTERVAL_MS
	print("SNAPSHOT_RESYNC_REQUEST seq=%d attempt=%d" % [seq, _snapshot_resync_count])
	request_act5_snapshot_resync.rpc_id(1)


func _snapshot_reject(reason: String, seq: int) -> void:
	_snapshot_stats["rejects"] = int(_snapshot_stats["rejects"]) + 1
	var now: int = Time.get_ticks_msec()
	if now - _last_snapshot_reject_ms < 1000:
		return
	_last_snapshot_reject_ms = now
	print("SNAPSHOT_REJECT reason=%s seq=%d" % [reason, seq])


func _expire_snapshot_assemblers() -> void:
	var now: int = Time.get_ticks_msec()
	var live: Dictionary = _snapshot_assembler.expire(now, SNAPSHOT_TIMEOUT_MS)
	if str(live.get("status", "")) == "timeout":
		_handle_snapshot_timeout(live, false)
	var boot: Dictionary = _snapshot_bootstrap_assembler.expire(now, SNAPSHOT_TIMEOUT_MS)
	if str(boot.get("status", "")) == "timeout":
		_handle_snapshot_timeout(boot, true)


@rpc("authority", "call_remote", "reliable")
func sync_message(text: String, seconds: float) -> void:
	if not _is_authority_sender(multiplayer.get_remote_sender_id()):
		return
	if text.length() > 512 or not is_finite(seconds) or seconds < 0.0 or seconds > 30.0:
		return
	if hud != null:
		hud.toast(text, seconds)


# ---------------------------------------------------------------------------
# Host loop
# ---------------------------------------------------------------------------

func bind_act4(p_game: Node) -> void:
	# Act 4 (ResonanceGame) attaches its world to the shared peer. The ENet
	# socket and CoopSession survive on SessionHub; only the scene-local game
	# changes. While bound, Act 4's own act4_sync snapshot is used instead of
	# the Act 5 snapshots, and the Act 5 loops stay dormant.
	_reset_snapshot_wire_state()
	act4_game = p_game
	# Reset Act 5 scene refs so nothing Act 5-bound leaks into Act 4.
	level = null
	story = null
	surge = null
	hud = null
	player = null
	# Release the Act 1 binding: only one act may own the peer at a time.
	_unbind_act1_node()
	if p_game != null:
		_clear_remotes()
		remote_root = Node3D.new()
		remote_root.name = "RemotePlayers"
		add_child(remote_root)
	session.net_online = online


## Release the Act 4 handler. Called by ResonanceGame from `_exit_tree()` — the
## authoritative moment the scene leaves the tree — and by bind() when Act 5
## takes the peer over. Only the currently bound world may release the binding,
## so a late teardown from a scene that was already replaced can never clear the
## new act's remote bodies.
func unbind_act4(p_game: Node = null) -> void:
	if p_game != null and act4_game != p_game:
		return
	if act4_game == null:
		return
	if is_instance_valid(act4_game):
		print("COOP_NET unbind_act4 · released the Act 4 world")
	_unbind_act4_node()


func _unbind_act4_node() -> void:
	act4_game = null
	_act4_state_clock = 0.0
	_act4_snap_clock = 0.0
	_clear_remotes()


## True only while the Act 4 handler is a live node that is still inside the
## tree. A node that is being torn down (removed from the tree, not yet freed)
## must never be asked for a snapshot: its children's transforms are already
## invalid, and every read would log `!is_inside_tree()`.
func _act4_bound() -> bool:
	if act4_game == null or not is_instance_valid(act4_game):
		return false
	return act4_game.is_inside_tree()


## True when the underlying ENet peer reports an established connection. Used
## by Act 4 to decide whether the other player's body should exist yet.
func peer_connected_now() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# ---------------------------------------------------------------------------
# Act 1 (Resonance 01) bridge
# ---------------------------------------------------------------------------

## Act01 module's Act1NetFacade registers here when it boots in integrated mode.
## While bound, the unified peer routes act1_* RPCs to the module's stage and
## runs Act 1's own snapshot / state streams; Act 4 / Act 5 loops stay dormant.
func bind_act1(p_facade: Node) -> void:
	# One bound act at a time. Rebinding must release the previous handler and
	# any other act that still believes it owns this peer.
	_unbind_act4_node()
	if p_facade != act1_facade:
		_unbind_act1_node()
	_reset_snapshot_wire_state()
	act1_facade = p_facade
	# Reset other acts so nothing leaks into Act 1.
	level = null
	story = null
	surge = null
	hud = null
	player = null
	if p_facade != null:
		_clear_remotes()
		remote_root = Node3D.new()
		remote_root.name = "RemotePlayers"
		add_child(remote_root)
	_act1_state_clock = 0.0
	_act1_snap_clock = 0.0
	_act1_ready_attempts = 0
	_act1_next_ready_ms = 0
	_act1_last_msg_seq = -1
	_act1_reset_wire_state()
	_act1_registered_pids.clear()
	session.net_online = online
	_act1_on_bound()


## Reset every per-visit wire counter/sequence. Called on bind and on unbind so a
## second Act01 visit can never inherit a sequence from the first one.
func _act1_reset_wire_state() -> void:
	_act1_pose_clock = 0.0
	_act1_dynamic_clock = 0.0
	_act1_state_seq = 0
	_act1_last_state_sig = 0
	_act1_last_state_ms = 0
	_act1_state_dirty = false
	_act1_last_pose_seq = -1
	_act1_last_dynamic_seq = -1
	_act1_last_state_seq = -1
	_act1_last_state_rx_ms = 0
	_act1_last_reset_ms = 0
	_act1_resync_count = 0
	_act1_next_resync_ms = 0


## The Act01 scene is now in the tree. Orchestrate the join from the correct
## side: the host serves any peer that already declared readiness (it may have
## been waiting while the host was still loading Act01); the client asks for its
## seat as soon as its facade exists.
func _act1_on_bound() -> void:
	if not _act1_bound():
		return
	if is_host:
		var now: int = Time.get_ticks_msec()
		for enet_id in multiplayer.get_peers():
			var stamp: int = int(_act1_ready_peers.get(enet_id, 0))
			if stamp > 0 and now - stamp <= ACT1_READY_TTL_MS:
				_act1_serve_join(enet_id)
		return
	_act1_welcomed = false
	_act1_bootstrapped = false
	_act1_welcome_pid = 0
	_act1_ready_attempts = 0
	_act1_next_ready_ms = 0
	# Anything that was buffered while this scene was still loading: welcome
	# first, then the state it belongs to.
	_act1_apply_pending_join()
	_act1_request_ready()


## Host: register the peer's Act01 seat exactly once per visit, then send the
## seat id (welcome) and the authoritative bootstrap in that order. Called by
## `act1_client_ready`, by `bind_act1` (when readiness arrived earlier), and by
## `act1_resend_join` (diagnostics / manual repair).
func _act1_serve_join(enet_id: int) -> bool:
	if not is_host or not _act1_bound() or enet_id == 0:
		return false
	var pid: int = _pid_for_peer(enet_id)
	if pid == 0:
		return false
	_act1_ready_peers[enet_id] = Time.get_ticks_msec()
	var stage: Node = act1_facade.get("stage") as Node
	if stage == null or not stage.has_method("build_snapshot"):
		return false
	if not _act1_registered_pids.has(pid):
		# Register the seat before the bootstrap is built so the first snapshot
		# already contains this player's entry.
		if stage.has_method("host_add_player"):
			stage.call("host_add_player", pid)
		_act1_registered_pids[pid] = true
		_act1_stat("seats_registered")
	var full: Dictionary = stage.call("build_snapshot", _seq) as Dictionary
	_act1_stat("welcome_sends")
	# Reliable + same channel: welcome is applied before the bootstrap payload.
	act1_welcome.rpc_id(enet_id, pid)
	_act1_send_bootstrap_payload(enet_id, _act1_bootstrap_payload(stage, full))
	return true


## Build the authoritative join/resync payload. v2 is a bundle of the three
## channels plus the full flags dictionary; a stage without the split helpers
## falls back to the v1 full snapshot.
func _act1_bootstrap_payload(stage: Node, full: Dictionary) -> Dictionary:
	var payload: Dictionary = full
	if not (stage.has_method("split_snapshot") and stage.has_method("pack_flags")):
		return payload
	var split: Dictionary = stage.call("split_snapshot", full) as Dictionary
	var state: Dictionary = (split.get("state", {}) as Dictionary).duplicate(true)
	# Re-use the current authoritative state sequence. If a change is pending
	# (rate-limited), bump once so the bootstrap is newer than what the client
	# has; otherwise a repeat bootstrap keeps the same seq and is recognised as a
	# duplicate instead of being re-imported as a new state.
	if _act1_state_dirty:
		_act1_state_seq += 1
		_act1_state_dirty = false
	state["state_seq"] = _act1_state_seq
	# Keep the full flags dictionary in the bootstrap: it is the recovery path
	# for a packed-flag layout mismatch, and bootstrap is one-shot.
	state["flags"] = (full.get("flags", {}) as Dictionary).duplicate(true)
	return {
		"protocol": ACT1_PROTOCOL_VERSION,
		"seq": int(full.get("seq", _seq)),
		"state_seq": _act1_state_seq,
		"state": state,
		"pose": split.get("pose", {}),
		"dynamic": split.get("dynamic", {}),
		"flags_full": (full.get("flags", {}) as Dictionary).duplicate(true),
	}


func _act1_send_bootstrap_payload(enet_id: int, payload: Dictionary) -> void:
	_act1_stat("bootstrap_sends")
	_act1_trace_line("ACT1_NET_SEND ch=join enet=%d bootstrap_bytes=%d v2=%s" % [
		enet_id, var_to_bytes(payload).size(), str(payload.has("state") and payload.has("pose"))])
	act1_bootstrap.rpc_id(enet_id, payload)


## Host: re-send only the authoritative bootstrap after a resync request. The
## client already has its seat, so no duplicate welcome is sent.
func _act1_send_bootstrap(enet_id: int) -> bool:
	if not is_host or not _act1_bound() or enet_id == 0:
		return false
	var pid: int = _pid_for_peer(enet_id)
	if pid == 0 or not _act1_registered_pids.has(pid):
		return false
	var stage: Node = act1_facade.get("stage") as Node
	if stage == null or not stage.has_method("build_snapshot"):
		return false
	var full: Dictionary = stage.call("build_snapshot", _seq) as Dictionary
	_act1_send_bootstrap_payload(enet_id, _act1_bootstrap_payload(stage, full))
	return true


## Client: ask the host for the Act01 seat. Retried (bounded) until a welcome
## arrives, so a ready lost with the old connection state cannot strand the
## client in the "seat never assigned" state. Cheap (two ints) and idempotent on
## the host side.
func _act1_request_ready(force: bool = false) -> void:
	if is_host or not _act1_bound():
		return
	if _act1_welcomed and not force:
		return
	if _act1_ready_attempts >= ACT1_READY_MAX_ATTEMPTS:
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	# R8A: a solo session keeps the SceneTree's OfflineMultiplayerPeer and is its
	# own server, so there is no remote host to ask for a seat. Without this
	# guard `rpc_id(1, ...)` targets ourselves and the engine raises
	# "RPC 'act1_client_ready' on yourself is not allowed by selected mode" on
	# every Act01 solo entry. Nothing joins in solo, so the handshake must not be
	# sent at all (it is a no-op, not a disabled feature).
	if peer is OfflineMultiplayerPeer or multiplayer.is_server():
		return
	var now: int = Time.get_ticks_msec()
	if _act1_next_ready_ms > 0 and now < _act1_next_ready_ms:
		return
	_act1_ready_attempts += 1
	if _act1_ready_attempts > 1:
		_act1_stat("ready_retries")
	_act1_next_ready_ms = now + (ACT1_READY_RETRY_MS if _act1_ready_attempts <= 10 else ACT1_READY_RETRY_SLOW_MS)
	_act1_trace_line("ACT1_NET_SEND ch=ready attempt=%d protocol=%d" % [_act1_ready_attempts, ACT1_PROTOCOL_VERSION])
	act1_client_ready.rpc_id(1, ACT1_PROTOCOL_VERSION)


## Client: apply a seat assignment (idempotent). Act1App.set_local_pid also
## clears a remote avatar for our own pid, so a duplicate welcome can never
## produce a second body.
func _act1_apply_welcome(pid: int) -> void:
	if pid <= 0:
		return
	# The host-assigned seat is the authoritative identity for this process.
	# `start_client()` can only guess pid 2 before the handshake, so a 3rd/4th
	# client would otherwise keep local_pid=2 while Act1App.local_pid is 3/4.
	# Every seat-addressed grant is checked against this field, so the mismatch
	# made clients 3/4 reject their own grab/cart/ride grants.
	local_pid = pid
	if session != null:
		session.local_pid = pid
	_act1_welcome_pid = pid
	_act1_welcomed = true
	_act1_ready_attempts = 0
	_act1_next_ready_ms = 0
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("set_local_pid"):
		stage.call("set_local_pid", pid)
	if act1_facade != null and act1_facade.has_method("on_unified_sync"):
		act1_facade.call("on_unified_sync")
	_act1_apply_pending_bootstrap()


func _act1_apply_pending_join() -> void:
	var now: int = Time.get_ticks_msec()
	if _act1_pending_welcome != 0:
		var fresh: bool = now - _act1_pending_welcome_ms <= ACT1_JOIN_BUFFER_TTL_MS
		var pid: int = _act1_pending_welcome
		_act1_pending_welcome = 0
		if fresh:
			_act1_apply_welcome(pid)


func _act1_apply_pending_bootstrap() -> void:
	if _act1_pending_bootstrap.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var snap: Dictionary = _act1_pending_bootstrap
	_act1_pending_bootstrap = {}
	if now - _act1_pending_bootstrap_ms > ACT1_JOIN_BUFFER_TTL_MS:
		return
	_act1_apply_bootstrap(snap)


## Client: apply the authoritative bootstrap. Two payload shapes are accepted:
##   v2 `{state, pose, dynamic, state_seq, seq, flags_full}` (split protocol)
##   v1  full snapshot (fallback)
## A stale or duplicate bootstrap must not overwrite newer state.
func _act1_apply_bootstrap(snap: Dictionary) -> void:
	if snap.is_empty() or not _act1_bound():
		return
	if snap.has("state") and snap.has("pose"):
		_act1_apply_bootstrap_v2(snap)
		return
	var seq: int = int(snap.get("seq", -1))
	if _act1_bootstrapped and seq <= _act1_last_msg_seq:
		_act1_stat("bootstrap_duplicates")
		return
	_act1_bootstrapped = true
	_act1_last_msg_seq = maxi(_act1_last_msg_seq, seq)
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("client_apply_snapshot"):
		stage.call("client_apply_snapshot", snap)
	_act1_apply_pending_bootstrap()


## v2 bootstrap: apply the reliable state, the continuous dynamics and the pose,
## each behind its own monotonic guard, then mark the client bootstrapped.
func _act1_apply_bootstrap_v2(bundle: Dictionary) -> void:
	var stage: Node = act1_facade.get("stage") as Node
	if stage == null:
		return
	var seq: int = int(bundle.get("seq", -1))
	var st_seq: int = int(bundle.get("state_seq", -1))
	var state: Dictionary = (bundle.get("state", {}) as Dictionary).duplicate(true)
	if bundle.has("flags_full"):
		state["flags"] = (bundle["flags_full"] as Dictionary).duplicate(true)
		# R8B-F1: the packed flag mask is unpacked against the *live* key order of
		# the local `flags` dictionary. When the host introduces a runtime flag
		# (`gust_done` / `crate_fell`) the client's key layout no longer matches,
		# so every `unpack_flags` returns {} and `client_apply_state` reports a
		# mismatch. The self-heal then asks for a fresh bootstrap — but that
		# bundle carries the state_seq the client has already applied, so the
		# `fresh_state` guard below throws it away and the mirror stays frozen
		# forever (measured: 11 flags_mismatch / 12 bootstrap_duplicates / the
		# client never saw vent_complete). `flags_full` is key-order independent
		# and always the host's present, so adopt it unconditionally.
		if stage.has_method("client_apply_state"):
			stage.call("client_apply_state", {"flags": (bundle["flags_full"] as Dictionary).duplicate(true)})
	var fresh_state: bool = (not _act1_bootstrapped) or st_seq > _act1_last_state_seq
	var fresh_pose: bool = (not _act1_bootstrapped) or seq > _act1_last_pose_seq
	if fresh_state:
		_act1_last_state_seq = maxi(_act1_last_state_seq, st_seq)
		_act1_last_state_rx_ms = Time.get_ticks_msec()
		if stage.has_method("client_apply_state"):
			var ok: bool = bool(stage.call("client_apply_state", state))
			if not ok:
				_act1_stat("flags_mismatch")
	if stage.has_method("client_apply_dynamic") and bundle.has("dynamic"):
		stage.call("client_apply_dynamic", bundle["dynamic"])
		_act1_last_dynamic_seq = maxi(_act1_last_dynamic_seq, int((bundle["dynamic"] as Dictionary).get("seq", -1)))
	if stage.has_method("client_apply_pose") and bundle.has("pose") and fresh_pose:
		stage.call("client_apply_pose", bundle["pose"])
		_act1_last_pose_seq = maxi(_act1_last_pose_seq, seq)
	_act1_last_msg_seq = maxi(_act1_last_msg_seq, seq)
	if _act1_bootstrapped and not fresh_state:
		_act1_stat("bootstrap_duplicates")
	_act1_bootstrapped = true
	_act1_last_state_rx_ms = maxi(_act1_last_state_rx_ms, Time.get_ticks_msec()) if fresh_state else _act1_last_state_rx_ms
	_act1_apply_pending_bootstrap()


## Release the Act 1 handler. Called by Act1NetFacade from `_exit_tree()` — the
## authoritative moment the Act01 scene leaves the tree. Only the facade that
## is currently bound may release the binding, so a late teardown from an Act01
## scene that was already replaced can never clear a newer act's binding.
func unbind_act1(p_facade: Node = null) -> void:
	if p_facade != null and act1_facade != p_facade:
		return
	_unbind_act1_node()


func _unbind_act1_node() -> void:
	if act1_facade != null and is_instance_valid(act1_facade):
		print("COOP_NET unbind_act1 · released the Act 1 world")
	act1_facade = null
	_act1_state_clock = 0.0
	_act1_snap_clock = 0.0
	# A real unbind ends this Act01 visit: queued join traffic must not leak into
	# the next one.
	_act1_ready_peers.clear()
	_act1_registered_pids.clear()
	_act1_welcomed = false
	_act1_bootstrapped = false
	_act1_welcome_pid = 0
	_act1_ready_attempts = 0
	_act1_next_ready_ms = 0
	_act1_pending_welcome = 0
	_act1_pending_bootstrap = {}
	_act1_last_msg_seq = -1
	_act1_reset_wire_state()


## True only while the Act 1 facade and its stage are live nodes still inside
## the tree. A scene that is being torn down (removed from the tree, not yet
## freed) must never be asked for a snapshot: every transform read on its
## children logs `!is_inside_tree()`. Mirrors `_act4_bound()`.
func _act1_bound() -> bool:
	if act1_facade == null or not is_instance_valid(act1_facade):
		return false
	if not (act1_facade as Node).is_inside_tree():
		return false
	var stage: Node = (act1_facade as Node).get("stage") as Node
	if stage == null or not is_instance_valid(stage):
		return false
	return stage.is_inside_tree()


## Client -> host: "my Act01 facade exists, give me a seat and the authoritative
## state". This is the join-ready handshake that replaces the old
## `peer_connected`-time push. `protocol` must match ACT1_PROTOCOL_VERSION.
@rpc("any_peer", "call_remote", "reliable")
func act1_client_ready(protocol: int) -> void:
	if not is_host:
		return
	var enet_id: int = multiplayer.get_remote_sender_id()
	var pid: int = _pid_for_peer(enet_id)
	_act1_stat("ready_recv")
	_act1_trace_line("ACT1_NET_RECV ch=ready enet=%d pid=%d protocol=%d bound=%s" % [
		enet_id, pid, protocol, str(_act1_bound())])
	if protocol != ACT1_PROTOCOL_VERSION:
		_act1_trace_line("ACT1_NET_READY_REJECT protocol=%d expected=%d" % [protocol, ACT1_PROTOCOL_VERSION])
		if pid != 0:
			act1_sync_message.rpc_id(enet_id, "联机协议版本不一致，无法加入本章", 5.0)
		return
	if pid == 0:
		return
	if int(_act1_ready_peers.get(enet_id, 0)) > 0:
		_act1_stat("ready_duplicates")
	_act1_ready_peers[enet_id] = Time.get_ticks_msec()
	if _act1_bound():
		_act1_serve_join(enet_id)


## Client -> host: an Act 01 interaction intent (press / begin / end / grab_end).
@rpc("any_peer", "call_remote", "reliable")
func act1_submit_interaction(id: String, kind: String) -> void:
	if not is_host:
		return
	var pid: int = _pid_for_peer(multiplayer.get_remote_sender_id())
	if pid == 0:
		return
	if not _act1_bound():
		return
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("host_handle_interaction_request"):
		stage.call("host_handle_interaction_request", pid, id, kind)


## Client -> host: an Act 01 player transform stream (20 Hz).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func act1_submit_state(state: Dictionary) -> void:
	if not is_host:
		return
	var pid: int = _pid_for_peer(multiplayer.get_remote_sender_id())
	if pid == 0:
		return
	if not _act1_bound():
		return
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("host_receive_state"):
		stage.call("host_receive_state", pid, state)


## Client -> host: an Act 01 reset request.
@rpc("any_peer", "call_remote", "reliable")
func act1_submit_reset() -> void:
	if not is_host:
		return
	var enet_id: int = multiplayer.get_remote_sender_id()
	var pid: int = _pid_for_peer(enet_id)
	if not _act1_bound() or pid == 0 or not _act1_registered_pids.has(pid):
		print("ACT1_RESET_REJECT reason=seat sender=%d pid=%d" % [enet_id, pid])
		return
	var now: int = Time.get_ticks_msec()
	if now - _act1_last_reset_ms < 3000:
		print("ACT1_RESET_REJECT reason=rate_limit pid=%d" % pid)
		return
	_act1_last_reset_ms = now
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("host_reset_run"):
		stage.call("host_reset_run", enet_id)


## Host -> client: an Act 01 hold grant (ride / push / grab).
## Wire args are `(id, pid, payload)`: `rpc_id` carries the target peer, `pid`
## is the addressed recipient, and `payload` is authored by the host.
@rpc("authority", "call_remote", "reliable")
func act1_grant_hold(id: String, pid: int, payload: Dictionary) -> void:
	if is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _is_authority_sender(sender):
		print("ACT1_GRANT_REJECT side=net reason=sender id=%s sender=%d" % [id, sender])
		return
	if pid != local_pid:
		print("ACT1_GRANT_REJECT side=net reason=recipient id=%s pid=%d local=%d sender=%d" % [
			id, pid, local_pid, sender])
		return
	if not _act1_bound():
		return
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("client_apply_grant"):
		stage.call("client_apply_grant", id, payload, sender, pid)


## Explicit layer-2 check for host->client authority messages. The @rpc
## annotation remains the engine layer-1 boundary; this makes an accidental
## mode/annotation regression fail closed instead of silently trusting a peer.
func _is_authority_sender(sender: int) -> bool:
	return online and sender == 1 and not multiplayer.is_server()


## Host -> client: Act 01 high-frequency pose (15 Hz, unreliable_ordered).
## Players + cart operator + gust only; never carries task/machine authority, so
## a lost packet costs one tick of visible motion and nothing else.
@rpc("authority", "call_remote", "unreliable_ordered")
func act1_pose(pose: Dictionary) -> void:
	if is_host:
		return
	var bytes: int = var_to_bytes(pose).size()
	_act1_note_recv(bytes)
	_act1_stat("pose_recv")
	_act1_stat_max("pose_recv_bytes_max", bytes)
	var seq: int = int(pose.get("seq", -1))
	_act1_trace_line("ACT1_NET_RECV ch=pose seq=%d bytes=%d bound=%s bootstrapped=%s" % [
		seq, bytes, str(_act1_bound()), str(_act1_bootstrapped)])
	if not _act1_bound() or not _act1_bootstrapped:
		_act1_stat("unwelcomed_drops")
		return
	if seq <= _act1_last_pose_seq:
		_act1_stat("pose_stale")
		return
	_act1_last_pose_seq = seq
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("client_apply_pose"):
		stage.call("client_apply_pose", pose)


## Host -> client: continuous machine motion (10 Hz, unreliable_ordered).
@rpc("authority", "call_remote", "unreliable_ordered")
func act1_dynamic(dyn: Dictionary) -> void:
	if is_host:
		return
	var bytes: int = var_to_bytes(dyn).size()
	_act1_note_recv(bytes)
	_act1_stat("dynamic_recv")
	var seq: int = int(dyn.get("seq", -1))
	_act1_trace_line("ACT1_NET_RECV ch=dynamic seq=%d bytes=%d bound=%s bootstrapped=%s" % [
		seq, bytes, str(_act1_bound()), str(_act1_bootstrapped)])
	if not _act1_bound() or not _act1_bootstrapped:
		_act1_stat("unwelcomed_drops")
		return
	if seq <= _act1_last_dynamic_seq:
		_act1_stat("dynamic_recv_stale")
		return
	_act1_last_dynamic_seq = seq
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("client_apply_dynamic"):
		stage.call("client_apply_dynamic", dyn)


## Host -> client: reliable discrete Act01 state (change-driven + keyframe).
## `state_seq` is monotonic per host visit, so a late packet can never roll the
## task state back to an older phase.
@rpc("authority", "call_remote", "reliable")
func act1_state(state: Dictionary) -> void:
	if is_host:
		return
	var bytes: int = var_to_bytes(state).size()
	_act1_note_recv(bytes)
	_act1_stat("state_recv")
	_act1_stat_max("state_bytes_max", bytes)
	var st_seq: int = int(state.get("state_seq", -1))
	_act1_trace_line("ACT1_NET_RECV ch=state state_seq=%d bytes=%d bound=%s bootstrapped=%s" % [
		st_seq, bytes, str(_act1_bound()), str(_act1_bootstrapped)])
	if not _act1_bound() or not _act1_bootstrapped:
		_act1_stat("unwelcomed_drops")
		return
	if st_seq <= _act1_last_state_seq:
		_act1_stat("state_dup_stale")
		return
	_act1_last_state_seq = st_seq
	_act1_last_state_rx_ms = Time.get_ticks_msec()
	_act1_resync_count = 0
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("client_apply_state"):
		var ok: bool = bool(stage.call("client_apply_state", state))
		if not ok:
			_act1_stat("flags_mismatch")
			_act1_request_ready(true)


## Client -> host: request a fresh authoritative state keyframe after a detected
## gap. Host-authoritative: the client can only ask, never supply state.
@rpc("any_peer", "call_remote", "reliable")
func act1_resync_request() -> void:
	if not is_host:
		return
	var enet_id: int = multiplayer.get_remote_sender_id()
	var pid: int = _pid_for_peer(enet_id)
	_act1_stat("resync_requests")
	if not _act1_bound() or pid == 0 or not _act1_registered_pids.has(pid):
		return
	_act1_stat("resync_served")
	_act1_send_bootstrap(enet_id)


## Host -> client: Act 01 authoritative snapshot (15 Hz). Legacy channel kept
## for one release as a fallback; the v2 host loop no longer uses it.
@rpc("authority", "call_remote", "unreliable_ordered")
func act1_sync_snapshot(snap: Dictionary) -> void:
	if is_host:
		return
	var bytes: int = var_to_bytes(snap).size()
	_act1_note_recv(bytes)
	_act1_stat("legacy_snapshot_recv")
	var seq: int = int(snap.get("seq", -1))
	_act1_trace_line("ACT1_NET_RECV ch=snapshot seq=%d bytes=%d welcomed=%s" % [
		seq, bytes, str(_act1_welcomed)])
	if not _act1_bound():
		return
	if not _act1_welcomed:
		# Never apply authoritative state before the seat exists: with the seat
		# still at the default pid the client would treat the host as itself and
		# spawn a remote avatar for its own pid.
		_act1_stat("unwelcomed_drops")
		return
	if seq <= _act1_last_msg_seq:
		_act1_stat("stale_snapshot_drops")
		return
	_act1_last_msg_seq = seq
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("client_apply_snapshot"):
		stage.call("client_apply_snapshot", snap)


## Host -> new client: reliable bootstrap snapshot on join.
@rpc("authority", "call_remote", "reliable")
func act1_bootstrap(snap: Dictionary) -> void:
	if is_host:
		return
	var bytes: int = var_to_bytes(snap).size()
	_act1_note_recv(bytes)
	_act1_stat("bootstrap_recv")
	_act1_trace_line("ACT1_NET_RECV ch=bootstrap seq=%d bytes=%d bound=%s welcomed=%s" % [
		int(snap.get("seq", -1)), bytes, str(_act1_bound()), str(_act1_welcomed)])
	if not _act1_bound() or not _act1_welcomed:
		# Bounded buffer: exactly one bootstrap per Act01 visit, expires after
		# ACT1_JOIN_BUFFER_TTL_MS. It is applied after the seat assignment.
		_act1_pending_bootstrap = snap.duplicate(true)
		_act1_pending_bootstrap_ms = Time.get_ticks_msec()
		return
	_act1_apply_bootstrap(snap)


## Host -> client: Act 01 completion broadcast (ride started / hand-off).
@rpc("authority", "call_remote", "reliable")
func act1_ride(payload: Dictionary) -> void:
	if is_host:
		return
	if not _act1_bound():
		return
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("begin_scene_handoff"):
		stage.call("begin_scene_handoff", payload)
	act1_facade.call("notify_ride_started", _pid_for_peer(multiplayer.get_remote_sender_id()), payload)


## Host -> client: welcome / seat assignment.
@rpc("authority", "call_remote", "reliable")
func act1_welcome(pid: int) -> void:
	if is_host:
		return
	_act1_stat("welcome_recv")
	_act1_trace_line("ACT1_NET_RECV ch=welcome pid=%d bound=%s welcomed=%s" % [
		pid, str(_act1_bound()), str(_act1_welcomed)])
	if not _act1_bound():
		_act1_pending_welcome = pid
		_act1_pending_welcome_ms = Time.get_ticks_msec()
		return
	if _act1_welcomed and _act1_welcome_pid == pid:
		# Duplicate delivery over real ENet: count it, re-apply idempotently
		# (cleans a self avatar if one appeared) and do not touch the ledger.
		_act1_stat("welcome_duplicates")
		_act1_apply_welcome(pid)
		return
	_act1_apply_welcome(pid)


## Host -> client: toast / message broadcast.
@rpc("authority", "call_remote", "reliable")
func act1_sync_message(text: String, seconds: float) -> void:
	if is_host:
		return
	if not _is_authority_sender(multiplayer.get_remote_sender_id()):
		return
	if text.length() > 512 or not is_finite(seconds) or seconds < 0.0 or seconds > 30.0:
		return
	if not _act1_bound():
		return
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("show_network_message"):
		stage.call("show_network_message", text, seconds)


## Client helper: send an Act 01 interaction intent from this process.
func act1_submit_interaction_local(id: String, kind: String) -> void:
	if is_host:
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	act1_submit_interaction.rpc_id(1, id, kind)


## Client helper: send an Act 01 player state stream from this process.
func act1_submit_state_local(state: Dictionary) -> void:
	if is_host:
		return
	act1_submit_state.rpc_id(1, state)


## Client helper: request an Act 01 reset.
func act1_submit_reset_local() -> void:
	if is_host:
		return
	act1_submit_reset.rpc_id(1)


## Host helper: send an Act 01 hold grant to one client. `act1_grant_hold` is an
## authority RPC that returns early on the host, so the host must send it through
## `rpc_id` (this helper) instead of calling the method locally.
func act1_send_grant(enet_id: int, id: String, pid: int, payload: Dictionary) -> void:
	if not is_host:
		return
	if enet_id == 0 or pid <= 0:
		return
	if not _act1_bound():
		print("ACT1_GRANT_REJECT side=host_send reason=unbound id=%s pid=%d" % [id, pid])
		return
	var stage: Node = act1_facade.get("stage") as Node
	if stage != null and stage.has_method("grant_payload_valid"):
		var check: Dictionary = stage.call("grant_payload_valid", id, payload) as Dictionary
		if not bool(check.get("ok", false)):
			print("ACT1_GRANT_REJECT side=host_send reason=%s id=%s pid=%d" % [
				str(check.get("reason", "invalid")), id, pid])
			return
	act1_grant_hold.rpc_id(enet_id, id, pid, payload)


## Host helper: re-send the Act01 join bundle (welcome + authoritative
## bootstrap) to one peer. Used by the duplicate/idempotency regression and as a
## manual repair path; `_act1_serve_join` never registers a second seat.
func act1_resend_join(enet_id: int) -> bool:
	return _act1_serve_join(enet_id)


## Host helper: enet id for a pid (test/diagnostic surface; returns 0 if absent).
func act1_enet_for_pid(pid: int) -> int:
	for enet_id in _peer_pid.keys():
		if int(_peer_pid[enet_id]) == pid:
			return int(enet_id)
	return 0


## Host helper: send an Act 01 snapshot / bootstrap to the given client(s).
func act1_send_snapshot(snap: Dictionary, to_enet: int = 0) -> void:
	if not is_host:
		return
	if to_enet == 0:
		act1_sync_snapshot.rpc(snap)
	else:
		act1_sync_snapshot.rpc_id(to_enet, snap)


## Act 1 host loop (split protocol v2):
##   * pose    — 15 Hz, unreliable_ordered, bodies + continuous scalars, budgeted
##   * dynamic — 10 Hz, unreliable_ordered, continuous machine motion, budgeted
##   * state   — reliable, sent on change (rate limited) + a 1 s keyframe
## A stage without `split_snapshot` falls back to the v1 full-snapshot
## broadcaster instead of going silent.
func _act1_host_process(delta: float) -> void:
	if not _act1_bound():
		return
	var stage: Node = act1_facade.get("stage") as Node
	if stage == null or not stage.has_method("build_snapshot"):
		return
	if not stage.has_method("split_snapshot") or not stage.has_method("pack_flags"):
		_act1_host_process_legacy(delta, stage)
		return
	_act1_pose_clock -= delta
	_act1_dynamic_clock -= delta
	var pose_due: bool = _act1_pose_clock <= 0.0
	var dynamic_due: bool = _act1_dynamic_clock <= 0.0
	if not pose_due and not dynamic_due:
		return
	if pose_due:
		_act1_pose_clock = 1.0 / ACT1_POSE_HZ
	if dynamic_due:
		_act1_dynamic_clock = 1.0 / ACT1_DYNAMIC_HZ
	var targets: Array = _act1_target_peers()
	if targets.is_empty():
		# Nobody has declared Act01 readiness yet: sending a world snapshot here
		# would only be dropped by a peer that is still in the launcher.
		return
	var stage_in_tree: bool = stage.is_inside_tree()
	if not stage_in_tree:
		_act1_stat("stale_builds")
	var full: Dictionary = stage.call("build_snapshot", _seq) as Dictionary
	var split: Dictionary = stage.call("split_snapshot", full) as Dictionary
	var now: int = Time.get_ticks_msec()
	if pose_due:
		_act1_broadcast_pose(split.get("pose", {}) as Dictionary, targets, stage_in_tree, now)
	if dynamic_due:
		_act1_broadcast_dynamic(split.get("dynamic", {}) as Dictionary, targets, now)
	# Reliable discrete state.
	var state: Dictionary = (split.get("state", {}) as Dictionary).duplicate(true)
	var packed: Dictionary = stage.call("pack_flags") as Dictionary
	state.erase("flags")
	for key in packed.keys():
		state[key] = packed[key]
	var sig: int = _act1_state_signature(state)
	var keyframe_due: bool = now - _act1_last_state_ms >= ACT1_STATE_KEYFRAME_MS
	var changed: bool = sig != _act1_last_state_sig
	if changed:
		_act1_state_dirty = true
	var interval_ok: bool = now - _act1_last_state_ms >= ACT1_STATE_MIN_INTERVAL_MS
	if (changed or keyframe_due or _act1_state_dirty) and interval_ok:
		_act1_state_seq += 1
		state["state_seq"] = _act1_state_seq
		_act1_broadcast_state(state, targets, keyframe_due and not changed, now)
		_act1_last_state_sig = sig
		_act1_last_state_ms = now
		_act1_state_dirty = false
	_seq += 1


## v1 fallback: one full authoritative snapshot per tick (legacy Act01 module).
func _act1_host_process_legacy(delta: float, stage: Node) -> void:
	_act1_snap_clock -= delta
	if _act1_snap_clock > 0.0:
		return
	_act1_snap_clock = 1.0 / SNAPSHOT_HZ
	var stage_in_tree: bool = stage.is_inside_tree()
	if not stage_in_tree:
		_act1_stat("stale_builds")
	var snap: Dictionary = stage.call("build_snapshot", _seq) as Dictionary
	var bytes: int = var_to_bytes(snap).size()
	var now: int = Time.get_ticks_msec()
	var last: int = int(_act1_stats.get("last_send_ms", 0))
	var gap: int = now - last if last > 0 else 0
	_act1_stat("legacy_snapshot_sends")
	_act1_stat_max("legacy_snapshot_bytes_max", bytes)
	_act1_stat("send_packets")
	_act1_stats["send_bytes_total"] = int(_act1_stats["send_bytes_total"]) + bytes
	_act1_stat_max("send_bytes_max", bytes)
	_act1_stats["last_send_ms"] = now
	_act1_trace_line("ACT1_NET_SEND ch=snapshot seq=%d bytes=%d wire=%d gap_ms=%d peers=%d stage_in_tree=%s" % [
		_seq, bytes, bytes + 4, gap, multiplayer.get_peers().size(), str(stage_in_tree)])
	if multiplayer.get_peers().size() > 0:
		_act1_stats["last_send_stage_in_tree"] = stage_in_tree
		if not stage_in_tree:
			_act1_stat("sends_after_exit")
		act1_sync_snapshot.rpc(snap)
	_seq += 1


## Peers that declared Act01 readiness recently. Only these receive Act01
## traffic, so a peer still in the launcher never gets a world snapshot.
func _act1_target_peers() -> Array:
	var out: Array = []
	var now: int = Time.get_ticks_msec()
	for enet_id in multiplayer.get_peers():
		var pid: int = _pid_for_peer(int(enet_id))
		# A peer that was seated in this visit stays a target for the whole
		# visit. The ready timestamp only gates the pre-seat window (a ready that
		# arrived while the host was still loading Act01 must not expire an
		# already-running session after 15 s).
		var active: bool = pid != 0 and _act1_registered_pids.has(pid)
		var stamp: int = int(_act1_ready_peers.get(enet_id, 0))
		if active or (stamp > 0 and now - stamp <= ACT1_READY_TTL_MS):
			out.append(int(enet_id))
	return out


func _act1_send_to_targets(pose_or_state: Dictionary, targets: Array, channel: String) -> void:
	match channel:
		"pose":
			if targets.size() == multiplayer.get_peers().size():
				act1_pose.rpc(pose_or_state)
			else:
				for enet_id in targets:
					act1_pose.rpc_id(int(enet_id), pose_or_state)
		"dynamic":
			if targets.size() == multiplayer.get_peers().size():
				act1_dynamic.rpc(pose_or_state)
			else:
				for enet_id in targets:
					act1_dynamic.rpc_id(int(enet_id), pose_or_state)
		"state":
			if targets.size() == multiplayer.get_peers().size():
				act1_state.rpc(pose_or_state)
			else:
				for enet_id in targets:
					act1_state.rpc_id(int(enet_id), pose_or_state)


func _act1_broadcast_pose(pose: Dictionary, targets: Array, stage_in_tree: bool, now: int) -> void:
	var bytes: int = var_to_bytes(pose).size()
	var wire: int = bytes + 4
	_act1_stat("pose_sends")
	_act1_stats["pose_bytes_total"] = int(_act1_stats["pose_bytes_total"]) + bytes * targets.size()
	_act1_stat_max("pose_bytes_max", bytes)
	if wire > ACT1_MAX_UNRELIABLE_BYTES:
		_act1_stat("pose_over_budget")
	var last: int = int(_act1_stats.get("last_send_ms", 0))
	var gap: int = now - last if last > 0 else 0
	_act1_stats["last_send_ms"] = now
	_act1_stats["last_send_stage_in_tree"] = stage_in_tree
	_act1_stat("send_packets", targets.size())
	_act1_stats["send_bytes_total"] = int(_act1_stats["send_bytes_total"]) + wire * targets.size()
	_act1_stat_max("send_bytes_max", wire)
	if not stage_in_tree:
		_act1_stat("sends_after_exit")
	var players: Dictionary = pose.get("players", {}) as Dictionary
	_act1_trace_line("ACT1_NET_SEND ch=pose seq=%d bytes=%d wire=%d gap_ms=%d peers=%d players=%d stage_in_tree=%s" % [
		int(pose.get("seq", -1)), bytes, wire, gap, targets.size(), players.size(), str(stage_in_tree)])
	if wire <= ACT1_MAX_UNRELIABLE_BYTES:
		_act1_send_to_targets(pose, targets, "pose")
		return
	# Budget exceeded (4-player roster with future fields): one player per packet
	# so a single lost fragment can never drop the whole roster.
	for pid in players.keys():
		var one: Dictionary = pose.duplicate(true)
		one["players"] = {pid: players[pid]}
		_act1_stat("pose_split_sends")
		_act1_send_to_targets(one, targets, "pose")


func _act1_broadcast_dynamic(dyn: Dictionary, targets: Array, now: int) -> void:
	var bytes: int = var_to_bytes(dyn).size()
	var wire: int = bytes + 4
	_act1_stat("dynamic_sends")
	_act1_stat_max("dynamic_bytes_max", bytes)
	_act1_stat("send_packets", targets.size())
	_act1_stats["send_bytes_total"] = int(_act1_stats["send_bytes_total"]) + wire * targets.size()
	_act1_stats["last_send_ms"] = now
	_act1_trace_line("ACT1_NET_SEND ch=dynamic seq=%d bytes=%d wire=%d peers=%d" % [
		int(dyn.get("seq", -1)), bytes, wire, targets.size()])
	if wire <= ACT1_MAX_UNRELIABLE_BYTES:
		_act1_send_to_targets(dyn, targets, "dynamic")
		return
	for key in ["door", "cart", "vent", "crate", "mine"]:
		if dyn.has(key):
			var part: Dictionary = {"seq": int(dyn.get("seq", 0)), key: dyn[key]}
			_act1_send_to_targets(part, targets, "dynamic")


func _act1_broadcast_state(state: Dictionary, targets: Array, keyframe: bool, now: int) -> void:
	var bytes: int = var_to_bytes(state).size()
	var wire: int = bytes + 4
	_act1_stat("state_sends")
	_act1_stat_max("state_bytes_max", bytes)
	if keyframe:
		_act1_stat("state_keyframes")
	_act1_stat("send_packets", targets.size())
	_act1_stats["send_bytes_total"] = int(_act1_stats["send_bytes_total"]) + wire * targets.size()
	_act1_trace_line("ACT1_NET_SEND ch=state seq=%d bytes=%d wire=%d keyframe=%s peers=%d" % [
		int(state.get("state_seq", -1)), bytes, wire, str(keyframe), targets.size()])
	_act1_send_to_targets(state, targets, "state")


func _act1_state_signature(state: Dictionary) -> int:
	var copy: Dictionary = state.duplicate(true)
	copy.erase("state_seq")
	return hash(var_to_bytes(copy))


## Act 1 client loop: stream the local player state at 20 Hz. Act 1's module
## may not expose `local_player_state` in the same shape as Act 5 (its own
## facade forwards interaction intents; the body pose is mirrored through
## snapshots). If the method is absent we skip the stream instead of erroring.
func _act1_client_process(delta: float) -> void:
	if not _act1_bound():
		return
	if not _act1_welcomed:
		# Retry the join-ready handshake until the host assigns the seat. No
		# business request (body state) is sent before the seat exists, so the
		# host cannot attribute anonymous state to the wrong pid.
		_act1_request_ready()
		return
	if not _act1_bootstrapped:
		# Welcome arrived but the reliable bootstrap has not been applied yet.
		# Ask again (bounded) instead of streaming into an unknown world state.
		_act1_request_ready(true)
		return
	var stage: Node = act1_facade.get("stage") as Node
	if stage == null or not stage.has_method("local_player_state"):
		return
	var now: int = Time.get_ticks_msec()
	if _act1_resync_count < ACT1_RESYNC_MAX and _act1_last_state_rx_ms > 0 \
			and now - _act1_last_state_rx_ms > ACT1_STATE_STALE_MS and now >= _act1_next_resync_ms:
		# Reliable state has been silent for too long: ask the host for a fresh
		# authoritative bundle. Bounded (5 per visit, 2 s apart).
		_act1_resync_count += 1
		_act1_next_resync_ms = now + ACT1_RESYNC_MIN_INTERVAL_MS
		_act1_trace_line("ACT1_NET_SEND ch=resync_request count=%d silent_ms=%d" % [
			_act1_resync_count, now - _act1_last_state_rx_ms])
		act1_resync_request.rpc_id(1)
	_act1_state_clock -= delta
	if _act1_state_clock > 0.0:
		return
	_act1_state_clock = 1.0 / STATE_HZ
	act1_submit_state.rpc_id(1, stage.call("local_player_state") as Dictionary)


# ---------------------------------------------------------------------------
# Act 4 (Resonance 04) loop
# ---------------------------------------------------------------------------

## Act 4 host loop: every snapshot tick the game builds its own act4 snapshot
## (freight platform, crystals, cradles, memories, stage, gate, players) and
## broadcasts it to the client just like Act 5 does, but without touching any
## Act 5 state.
func _act4_host_process(delta: float) -> void:
	if not _act4_bound():
		return
	_act4_snap_clock -= delta
	if _act4_snap_clock > 0.0:
		return
	_act4_snap_clock = 1.0 / SNAPSHOT_HZ
	if multiplayer.get_peers().size() > 0:
		var snap: Dictionary = act4_game.build_act4_snapshot()
		var cmp: Dictionary = snap.duplicate(true)
		cmp.erase("seq")
		var now_ms: int = Time.get_ticks_msec()
		if cmp == _last_act4_snap and (now_ms - _act4_last_sent_ms) < 1000:
			return
		_last_act4_snap = cmp
		_act4_last_sent_ms = now_ms
		var packets: Array[Dictionary] = SnapshotWireScript.encode_packets(_seq, snap, false)
		if not packets.is_empty():
			for pkt: Dictionary in packets:
				act4_sync_packet.rpc(pkt)
		else:
			act4_sync.rpc(snap)
	_seq += 1


func _act4_client_process(delta: float) -> void:
	if not _act4_bound():
		return
	# Act 4 can be entered before the ENet handshake completes (both processes
	# start from the launcher, or a client waits for its host). Never fire the
	# state stream into a peer that is not connected: it only logs "Trying to
	# call an RPC via a multiplayer peer which is not connected." every tick.
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_act4_state_clock -= delta
	if _act4_state_clock > 0.0:
		return
	_act4_state_clock = 1.0 / STATE_HZ
	act4_submit_state.rpc_id(1, act4_game.local_act4_player_state())


func _process(delta: float) -> void:
	# A binding whose scene already left the tree is stale by definition. Drop
	# it here as a last-resort self-heal; the authoritative release is
	# Act1NetFacade._exit_tree() -> unbind_act1().
	if act1_facade != null and not _act1_bound():
		unbind_act1()
	if not online:
		return
	if not is_host:
		_expire_snapshot_assemblers()
	if _act1_bound():
		if is_host:
			_act1_host_process(delta)
		else:
			_act1_client_process(delta)
		return
	if _act4_bound():
		if is_host:
			_act4_host_process(delta)
		else:
			_act4_client_process(delta)
		return
	if is_host:
		_host_process(delta)
	else:
		_client_process(delta)


# ---------------------------------------------------------------------------
# Act 4 RPC surface (distinctively namespaced, Act 5 untouched)
# ---------------------------------------------------------------------------

## Client -> host: one Act 4 player transform stream (pos/yaw/vel/carry/grab).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func act4_submit_state(state: Dictionary) -> void:
	if not is_host:
		return
	var pid: int = _pid_for_peer(multiplayer.get_remote_sender_id())
	if pid == 0:
		return
	if _act4_bound():
		act4_game.on_act4_remote_state(pid, state)


## Host -> client: compressed, checksummed Act 4 snapshot chunk over CoopSnapshotWire.
@rpc("authority", "call_remote", "unreliable_ordered")
func act4_sync_packet(packet: Dictionary) -> void:
	if is_host:
		return
	var result: Dictionary = _act4_snapshot_assembler.accept(packet, Time.get_ticks_msec())
	if str(result.get("status", "")) == "complete" and _act4_bound():
		var snap: Dictionary = result.get("snapshot", {}) as Dictionary
		if not snap.is_empty():
			act4_game.apply_act4_snapshot(snap)


## Host -> client: full Act 4 authoritative snapshot (bootstrap / fallback).
@rpc("authority", "call_remote", "unreliable_ordered")
func act4_sync(snap: Dictionary) -> void:
	if is_host:
		return
	if _act4_bound():
		act4_game.apply_act4_snapshot(snap)


## Client -> host: an Act 4 gameplay action request (pickup, drop, seat, strike).
## `kind` names the action, `detail` is machine/crystal id, `value` a strength.
@rpc("any_peer", "call_remote", "reliable")
func act4_request_action(kind: String, detail: String, value: float) -> void:
	if not is_host:
		return
	var pid: int = _pid_for_peer(multiplayer.get_remote_sender_id())
	if pid == 0:
		if kind == "hammer_strike":
			print("ACT4 ACTION_DROPPED reason=unknown_sender kind=%s sender=%d" % [
				kind, multiplayer.get_remote_sender_id()])
		return
	if _act4_bound():
		act4_game.on_act4_remote_action(pid, kind, detail, value)
	elif kind == "hammer_strike":
		# The host must never silently swallow a real strike while its Act 4
		# world is not bound; leave a line that names the reason.
		print("ACT4 ACTION_DROPPED reason=act4_unbound pid=%d kind=%s" % [pid, kind])


## Client helper: ask the host to apply an Act 4 action from this client process.
func act4_submit_action(kind: String, detail: String = "", value: float = 0.0) -> void:
	if is_host:
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		if kind == "hammer_strike":
			print("ACT4 client action dropped reason=peer_not_connected kind=%s peer=%s" % [
				kind, peer.get_class() if peer != null else "null"])
		return
	act4_request_action.rpc_id(1, kind, detail, value)


## FreightPlatform (non-authority side) calls this directly with its own kinds
## (drive / brake / clamp / grab / call / winch). Route it into the same
## host-authoritative Act 4 action handler.
@rpc("any_peer", "call_remote", "reliable")
func act4_freight_action(kind: String, dock_id: String) -> void:
	if not is_host:
		return
	var pid: int = _pid_for_peer(multiplayer.get_remote_sender_id())
	if pid == 0:
		return
	if _act4_bound():
		act4_game.on_act4_freight_action(pid, kind, dock_id)


## Host -> client: reliable high-value event (memory trigger, gate state, toast).
@rpc("authority", "call_remote", "reliable")
func act4_event(kind: String, payload: Dictionary) -> void:
	if is_host:
		return
	if _act4_bound():
		act4_game.on_act4_net_event(kind, payload)


## Client -> host: "my Act 4 world is bound, send me the initial state". A
## client that connected before the host bound Act 4 never receives the join
## bootstrap, so it pulls one once its own scene is ready. Reliable, one shot.
@rpc("any_peer", "call_remote", "reliable")
func act4_request_sync() -> void:
	if not is_host or not _act4_bound():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var pid: int = _pid_for_peer(sender)
	print("COOP_NET act4 initial state requested by enet=%d pid=%d" % [sender, pid])
	act4_game.on_act4_sync_request(pid)
	act4_event.rpc_id(sender, "bootstrap", act4_game.build_act4_snapshot(true))


## Client helper: ask the host for one authoritative Act 4 bootstrap.
func act4_request_sync_now() -> void:
	if is_host:
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	act4_request_sync.rpc_id(1)


## Client helper: send an Act 4 event to the client (host side).
func act4_send_event(kind: String, payload: Dictionary) -> void:
	if not is_host:
		return
	act4_event.rpc(kind, payload)


func _on_peer_connected(id: int) -> void:
	var pid: int = _next_pid
	_next_pid += 1
	_peer_pid[id] = pid
	session.add_player(pid, "队友%d" % (pid - 1))
	online = true
	session.net_online = true
	print("COOP_NET peer_connected enet=%d pid=%d peers=%d" % [id, pid, peer_count()])
	if hud != null:
		hud.toast("队友 %d 已连接" % pid, 2.5)
	peer_joined.emit(pid)
	if _act1_bound():
		# Act 01 join is now client-driven: the peer sends `act1_client_ready`
		# once its facade is bound. Sending welcome/bootstrap here — on the ENet
		# handshake — is exactly what used to be dropped by a client that was
		# still in the launcher. Keep this branch only for a peer that is already
		# known to be ready (e.g. a reconnect racing the same frame).
		if int(_act1_ready_peers.get(id, 0)) > 0:
			_act1_serve_join(id)
		return
	if _act4_bound():
		act4_game.on_act4_peer_connected(pid)
		# Act 4 has its own reliable bootstrap snapshot.
		act4_send_event("bootstrap", act4_game.build_act4_snapshot(true))
		return
	# Push a full snapshot immediately so the client sees the real machines
	# before its first frame of input. Bootstrap chunks are reliable. While the
	# host scene is still loading, don't send the minimal fallback dictionary:
	# it is not a valid Act05 snapshot and would only exercise the reject path.
	if level == null or not is_instance_valid(level):
		print("COOP_NET bootstrap deferred until Act05 level binds (peer=%d)" % id)
		return
	_send_snapshot_chunks(build_snapshot(), id, true)


func _host_process(delta: float) -> void:
	if level == null or not is_instance_valid(level):
		return
	_snap_clock -= delta
	if _snap_clock > 0.0:
		return
	_snap_clock = 1.0 / SNAPSHOT_HZ
	# Host's own state goes into the session mirror so the duty board and the
	# ledger behave the same for the local body.
	if player != null and is_instance_valid(player):
		session.set_player_state(local_pid, _state_of(player))
		_credit_from_state(local_pid, _state_of(player))
	var snap: Dictionary = build_snapshot()
	if multiplayer.get_peers().size() > 0:
		_send_snapshot_chunks(snap)
	_seq += 1


## Compress/split one authoritative snapshot and send bounded packets. Live
## snapshots are unreliable_ordered (latest tick wins); join/resync snapshots are
## reliable. A packet budget failure is loud and never truncates the snapshot.
func _send_snapshot_chunks(snap: Dictionary, to_enet: int = 0, bootstrap: bool = false) -> void:
	var seq: int = int(snap.get("seq", _seq))
	var packets: Array[Dictionary] = SnapshotWireScript.encode_packets(seq, snap, bootstrap)
	if packets.is_empty():
		_snapshot_stats["rejects"] = int(_snapshot_stats["rejects"]) + 1
		push_error("SNAPSHOT_ENCODE_FAIL seq=%d bytes=%d" % [seq, var_to_bytes(snap).size()])
		return
	_snapshot_stats["snapshots_sent"] = int(_snapshot_stats["snapshots_sent"]) + 1
	_snapshot_stats["raw_bytes_max"] = maxi(
		int(_snapshot_stats["raw_bytes_max"]), var_to_bytes(snap).size())
	for packet in packets:
		var packet_bytes: int = var_to_bytes(packet).size()
		_snapshot_stats["packets_sent"] = int(_snapshot_stats["packets_sent"]) + 1
		_snapshot_stats["packet_bytes_max"] = maxi(
			int(_snapshot_stats["packet_bytes_max"]), packet_bytes)
		_snapshot_stats["packed_bytes_max"] = maxi(
			int(_snapshot_stats["packed_bytes_max"]), int(packet.get("packed_size", 0)))
		_snapshot_stats["last_packet_bytes"] = packet_bytes
		if int(packet.get("count", 1)) > 1:
			_snapshot_stats["chunks_sent"] = int(_snapshot_stats["chunks_sent"]) + 1
		if to_enet != 0:
			if bootstrap:
				sync_snapshot_bootstrap_part.rpc_id(to_enet, packet)
			else:
				sync_snapshot_part.rpc_id(to_enet, packet)
		else:
			if bootstrap:
				sync_snapshot_bootstrap_part.rpc(packet)
			else:
				sync_snapshot_part.rpc(packet)


func build_snapshot() -> Dictionary:
	if level == null or not is_instance_valid(level):
		return {"seq": _seq, "time": Time.get_ticks_msec(), "peer_count": peer_count()}
	var players: Dictionary = {}
	for pid in session.player_states.keys():
		var state: Dictionary = session.player_states[pid] as Dictionary
		players[int(pid)] = {
			"pos": state.get("pos", Vector3.ZERO),
			"yaw": float(state.get("yaw", 0.0)),
			"grab": bool(state.get("grab", false)),
			"op": bool(state.get("op", false)),
		}
	if player != null:
		players[local_pid] = {
			"pos": player.global_position,
			"yaw": player.yaw,
			"grab": player.grabbing,
			"op": player.operating,
		}
	var stabs: Array = []
	for stab in level.stabilizers:
		stabs.append(stab.snapshot())
	var snap: Dictionary = {
		"seq": _seq,
		"time": Time.get_ticks_msec(),
		"core": level.core.network_snapshot(),
		"carts": {"left": level.left_cart.get_p(), "right": level.right_cart.get_p()},
		"lever": {"left": level.left_station.lever_angle, "right": level.right_station.lever_angle},
		"active": {
			"cart_left": session.claim_owner("cart_left"),
			"cart_right": session.claim_owner("cart_right"),
			"stabilizer_w": session.claim_owner("stabilizer_w"),
			"stabilizer_e": session.claim_owner("stabilizer_e"),
			"brake": session.claim_owner("brake"),
			"brake_assist": session.claim_owner("brake_assist"),
			"damper": session.claim_owner("damper"),
			"isolation_carriage": session.claim_owner("isolation_carriage"),
			"catwalk_lock": session.claim_owner("catwalk_lock"),
			"winch": session.claim_owner("winch"),
		},
		"stabs": stabs,
		"catwalk": level.catwalk.snapshot(),
		# Entrance shutter: the host physically pushes this open, and without
		# publishing it every client stayed behind a closed door and could never
		# reach the hall (observed with 3 players: pid2/pid3 wedged at z=24.5).
		"shutter": (level.push_door.snapshot() if level.push_door != null else {}),
		"brake": level.brake.snapshot(),
		"damper": level.damper.snapshot(),
		"iso": level.isolation.snapshot(),
		"stage": story.stage,
		"checkpoint": story.checkpoint,
		"surge": surge.snapshot(),
		"ledger": session.ledger_snapshot(),
		"claims": _claims_copy(),
		"players": players,
		"completed": story.completed_flag(),
		"completion": story.completion_text(),
		"reset_seq": reset_seq,
		"peer_count": peer_count(),
	}
	return snap


func _claims_copy() -> Dictionary:
	var out: Dictionary = {}
	for machine_id in session.claims.keys():
		out[str(machine_id)] = session.claim_owner(str(machine_id))
	return out


func _state_of(p: PlayerController) -> Dictionary:
	return {
		"pos": p.global_position,
		"yaw": p.yaw,
		"grab": p.grabbing,
		"op": p.operating,
		"impaired": p.impaired_timer,
		"op_machine": session.local_operating_machine if session != null else "",
	}


## Host-side schema/range check for the 20 Hz Act05 body mirror. The client owns
## its transform by design; this is not anti-cheat, but it prevents NaN/world-
## escaping/oversized state from becoming interaction proximity evidence.
func _validate_act5_player_state(state: Dictionary) -> String:
	if state.is_empty() or state.size() > ACT5_STATE_MAX_FIELDS:
		return "shape"
	if not (state.get("pos") is Vector3):
		return "pos_type"
	var pos: Vector3 = state["pos"]
	if not pos.is_finite() or absf(pos.x) > 200.0 or absf(pos.z) > 200.0 \
			or pos.y < -10.0 or pos.y > 40.0:
		return "pos_range"
	for key in ["yaw", "impaired"]:
		if state.has(key) and not _finite_number(state[key]):
			return "%s_range" % key
	if state.has("impaired") and (float(state["impaired"]) < 0.0 or float(state["impaired"]) > 30.0):
		return "impaired_bounds"
	for key in ["grab", "op"]:
		if state.has(key) and not (state[key] is bool):
			return "%s_type" % key
	if state.has("op_machine"):
		var machine: String = str(state["op_machine"])
		if machine.length() > 32:
			return "op_machine_length"
		if machine != "" and not session.is_known_machine(machine):
			return "op_machine_unknown"
	return ""


## Host-side validation: actions only earn credit from the state the host can
## actually verify (a held rail while a warning runs, a real climb up the ladder).
func _credit_from_state(pid: int, state: Dictionary) -> void:
	if not is_host:
		return
	if session.status_of(pid) != ParticipationLedger.STATUS_ACTIVE:
		return
	var grab: bool = bool(state.get("grab", false))
	session.set_grab_state(pid, grab)
	# Climbing the emergency ladder back up from the drop pad, while impaired,
	# is a real self-rescue.
	var pos: Vector3 = state.get("pos", Vector3.ZERO)
	var impaired: float = float(state.get("impaired", 0.0))
	var ladder_top: Vector3 = level.catwalk.to_global(Vector3(6.45, CatwalkRig.PIVOT_HEIGHT, 3.05))
	var near_ladder: bool = Vector2(pos.x - ladder_top.x, pos.z - ladder_top.z).length() < 2.2
	if impaired > 0.0 and near_ladder and pos.y > 1.2:
		session.credit(pid, "self_rescue", 1.0, "受伤后沿爬梯自救")
	# Reporting that they are operating a machine at a machine's location.
	var op_machine: String = str(state.get("op_machine", ""))
	if op_machine != "":
		session.refresh_claim(op_machine, pid)


# ---------------------------------------------------------------------------
# Client loop
# ---------------------------------------------------------------------------

func _client_process(delta: float) -> void:
	if not online or player == null or not is_instance_valid(player):
		return
	# The host may quit or drop between frames; never fire RPCs into a dead peer.
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_state_clock -= delta
	if _state_clock > 0.0:
		return
	_state_clock = 1.0 / STATE_HZ
	submit_state.rpc_id(1, _state_of(player))
	var machine: String = session.local_operating_machine
	if machine != "" and player.operating:
		var axis: float = Input.get_axis("move_back", "move_forward")
		submit_axis.rpc_id(1, machine, axis)


## Structural/range guard for an authoritative Act05 snapshot. The host is the
## only sender, but a malformed/compromised snapshot must not be able to inject
## NaN transforms, unbounded arrays, an unknown story stage or a fifth player.
func _snapshot_shape_ok(snap: Dictionary) -> bool:
	if snap.is_empty() or snap.size() > 64:
		return false
	if not _finite_tree(snap, 0):
		return false
	var players_variant: Variant = snap.get("players", {})
	if not (players_variant is Dictionary):
		return false
	var players: Dictionary = players_variant as Dictionary
	if players.size() > 4:
		return false
	for key in players.keys():
		var pid: int = int(key)
		if pid < 1 or pid > 4:
			return false
		var state_variant: Variant = players[key]
		if not (state_variant is Dictionary):
			return false
		var state: Dictionary = state_variant as Dictionary
		if not (state.get("pos") is Vector3):
			return false
		var pos: Vector3 = state["pos"]
		if not pos.is_finite() or absf(pos.x) > 200.0 or absf(pos.z) > 200.0 \
				or pos.y < -20.0 or pos.y > 100.0:
			return false
		for scalar in ["yaw"]:
			if state.has(scalar) and not _finite_number(state[scalar]):
				return false
	var stabs_variant: Variant = snap.get("stabs", [])
	if not (stabs_variant is Array) or (stabs_variant as Array).size() > 8:
		return false
	for entry in (stabs_variant as Array):
		if not (entry is Dictionary):
			return false
	var stage: int = int(snap.get("stage", -1))
	if stage < 0 or stage > StoryDirector.Stage.COMPLETED:
		return false
	var checkpoint: int = int(snap.get("checkpoint", -1))
	if checkpoint < 0 or checkpoint >= StoryDirector.CP_POSITIONS.size():
		return false
	var carts_variant: Variant = snap.get("carts", {})
	if not (carts_variant is Dictionary):
		return false
	var carts: Dictionary = carts_variant as Dictionary
	for side in ["left", "right"]:
		if carts.has(side):
			if not _finite_number(carts[side]) or float(carts[side]) < 0.0 or float(carts[side]) > 1.0:
				return false
	var claims_variant: Variant = snap.get("claims", {})
	if not (claims_variant is Dictionary) or (claims_variant as Dictionary).size() > 32:
		return false
	var ledger_variant: Variant = snap.get("ledger", {})
	if not (ledger_variant is Dictionary) or (ledger_variant as Dictionary).size() > 8:
		return false
	var text: String = str(snap.get("completion", ""))
	if text.length() > 512:
		return false
	var peer_count: int = int(snap.get("peer_count", 1))
	if peer_count < 1 or peer_count > CoopSession.MAX_PLAYERS:
		return false
	return true


func _finite_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(value)
	return false


func _finite_tree(value: Variant, depth: int) -> bool:
	if depth > 6:
		return false
	if value is Object:
		return false
	if value is float:
		return is_finite(value)
	if value is Vector2:
		return (value as Vector2).is_finite()
	if value is Vector3:
		return (value as Vector3).is_finite()
	if value is Array:
		var array: Array = value as Array
		if array.size() > 64:
			return false
		for item in array:
			if not _finite_tree(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		if dictionary.size() > 64:
			return false
		for key in dictionary.keys():
			if not _finite_tree(dictionary[key], depth + 1):
				return false
		return true
	if value is String:
		return str(value).length() <= 2048
	return true


func _apply_snapshot(snap: Dictionary) -> void:
	if not _snapshot_shape_ok(snap):
		_snapshot_reject("apply_shape", int(snap.get("seq", -1)))
		return
	_last_snapshot_ms = Time.get_ticks_msec()
	if level == null:
		return
	level.core.apply_network_snapshot(snap.get("core", {}) as Dictionary)
	var carts: Dictionary = snap.get("carts", {})
	level.left_cart.set_p(float(carts.get("left", level.left_cart.get_p())))
	level.right_cart.set_p(float(carts.get("right", level.right_cart.get_p())))
	var lever: Dictionary = snap.get("lever", {})
	level.left_station.lever_angle = float(lever.get("left", 0.0))
	level.right_station.lever_angle = float(lever.get("right", 0.0))
	if level.left_station.lever_node != null:
		level.left_station.lever_node.rotation.x = level.left_station.lever_angle
	if level.right_station.lever_node != null:
		level.right_station.lever_node.rotation.x = level.right_station.lever_angle
	var stabs: Array = snap.get("stabs", [])
	for i in range(level.stabilizers.size()):
		if i < stabs.size():
			level.stabilizers[i].apply_snapshot(stabs[i] as Dictionary)
	level.catwalk.apply_snapshot(snap.get("catwalk", {}) as Dictionary)
	# Entrance shutter mirror: without this a client stays inside a closed door
	# the host already pushed open.
	if level.push_door != null:
		level.push_door.apply_snapshot(snap.get("shutter", {}) as Dictionary)
	level.brake.apply_snapshot(snap.get("brake", {}) as Dictionary)
	level.damper.apply_snapshot(snap.get("damper", {}) as Dictionary)
	level.isolation.apply_snapshot(snap.get("iso", {}) as Dictionary)
	surge.apply_snapshot(snap.get("surge", {}) as Dictionary)
	story.apply_network_stage(int(snap.get("stage", 0)), int(snap.get("checkpoint", 0)))
	session.ledger.apply_snapshot(snap.get("ledger", {}) as Dictionary)
	_apply_claims(snap.get("claims", {}) as Dictionary)
	var players: Dictionary = snap.get("players", {})
	for key in players.keys():
		var pid: int = int(key)
		if pid == local_pid:
			continue
		_update_remote_visual(pid, players[key] as Dictionary)
	if int(snap.get("reset_seq", 0)) != reset_seq:
		reset_seq = int(snap.get("reset_seq", 0))
		player.teleport(StoryDirector.CP_POSITIONS[0], 0.0, -0.05)
	if bool(snap.get("completed", false)):
		var text: String = str(snap.get("completion", ""))
		if text != "":
			story.apply_network_completion(text)
	if hud != null:
		hud.update_net_status("客户端 · 玩家%d · 主机快照 #%d · 在线 %d" % [local_pid, int(snap.get("seq", 0)), int(snap.get("peer_count", 1))], true)


func _apply_claims(claims: Dictionary) -> void:
	for key in claims.keys():
		var pid: int = int(claims[key])
		if pid == 0:
			session.claims.erase(str(key))
		else:
			session.claims[str(key)] = {"pid": pid, "t": session.clock, "axis": 0.0}


func _update_remote_visual(pid: int, state: Dictionary) -> void:
	if pid == local_pid:
		return
	var remote: RemotePlayer = remotes.get(pid) as RemotePlayer
	if remote == null:
		remote = RemotePlayer.new()
		remote.setup(pid, session.ledger.display_name(pid))
		remote_root.add_child(remote)
		remotes[pid] = remote
	remote.apply_state(state)


# ---------------------------------------------------------------------------
# Connection bookkeeping
# ---------------------------------------------------------------------------

func _on_peer_disconnected(id: int) -> void:
	var pid: int = int(_peer_pid.get(id, 0))
	session.release_all_for(pid, "disconnect")
	session.remove_player(pid, "disconnect")
	_peer_pid.erase(id)
	online = multiplayer.get_peers().size() > 0
	session.net_online = online
	print("COOP_NET peer_disconnected enet=%d pid=%d" % [id, pid])
	if hud != null:
		hud.toast("队友 %d 已断开，机械占用已释放" % pid, 3.0)
	peer_left.emit(pid)
	if _act4_bound():
		act4_game.on_act4_peer_disconnected(pid)
	if _act1_bound() and pid != 0:
		# Release the Act01 seat and its avatar so a disconnect cannot leave a
		# ghost body / a stale credit record in the host's ledger for the rest of
		# the chapter.
		_act1_ready_peers.erase(id)
		_act1_registered_pids.erase(pid)
		var stage: Node = act1_facade.get("stage") as Node
		if stage != null and stage.has_method("host_remove_player"):
			stage.call("host_remove_player", pid)
			_act1_stat("seats_released")


func _on_connected() -> void:
	_reset_snapshot_wire_state()
	online = true
	session.net_online = true
	local_pid = 2
	session.setup(2, false)
	if not session.ledger.players.has(1):
		session.ledger.add_player(1, "七号")
	session.ledger.add_player(2, "队友")
	print("COOP_NET connected to server pid=%d" % local_pid)
	connected_changed.emit(true)
	if hud != null:
		hud.toast("已连接主机 · 你是玩家 2", 3.0)
	if _act1_bound():
		# The socket may connect after the client already entered Act01: ask for
		# the seat now instead of waiting for the next frame's retry.
		_act1_request_ready()
	if _act4_bound():
		# The connection may complete after Act 4 is already in the tree; the
		# scene's own bind covers the opposite order (see ResonanceGame._setup_coop).
		act4_game.on_act4_connected()


func _on_connection_failed() -> void:
	_reset_snapshot_wire_state()
	online = false
	session.net_online = false
	if hud != null:
		hud.toast("连接主机失败", 3.0)
	print("COOP_NET connection failed")


func _on_server_lost() -> void:
	_reset_snapshot_wire_state()
	online = false
	session.net_online = false
	if hud != null:
		hud.toast("与主机断开 — 退回单人状态", 4.0)
	print("COOP_NET server lost")


func _pid_for_peer(enet_id: int) -> int:
	return int(_peer_pid.get(enet_id, 0))


func _host_reset() -> void:
	if story != null:
		story.reset_to_checkpoint()
	if player != null:
		player.teleport(StoryDirector.CP_POSITIONS[story.checkpoint], StoryDirector.CP_YAWS[story.checkpoint], -0.05)
	for machine_id in session.claims.keys():
		session.release_claim(str(machine_id), 0)
