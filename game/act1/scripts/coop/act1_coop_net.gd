class_name Act1CoopNet
extends Node

## Host-authoritative ENet transport for Act 01 — STANDALONE backend.
##
## This is the Act01 project's original CoopNet, renamed `Act1CoopNet` so it can
## never collide with the 04-05 base project's global `CoopNet` (which lives at
## /root/SessionHub/CoopNet inside the integrated project).
##
## IMPORTANT INTEGRATION CONTRACT
## ------------------------------
## A single Godot process permits only ONE `multiplayer.multiplayer_peer`. The
## integrated five-act session owns that peer via the unified `CoopNet`. This
## class therefore MUST NOT be instantiated inside the integrated session:
## * Act1App routes all networking through `Act1NetFacade`.
## * `Act1NetFacade` creates THIS node ONLY in standalone mode (no `/root/SessionHub`),
##   i.e. the module test host / module-local two-process verification.
## * When `/root/SessionHub` exists, `Act1NetFacade` binds to the unified net and
##   this backend is never created — no second ENet peer.
##
## Authority model (unchanged from the source):
## * Host owns every machine, world flag and participation credit.
## * Each client owns its own body transform and streams it to the host.
## * A client interaction request is applied to that client's pid, never to the
##   host's local player.
## * Disconnect releases holds, claims and spectates the body without granting
##   completion.

signal peer_joined(pid: int)
signal peer_left(pid: int)
signal connected_changed(online: bool)
signal ride_started(pid: int, completion: Dictionary)

const DEFAULT_PORT := 24568
const STATE_HZ := 20.0
const SNAPSHOT_HZ := 15.0

var stage: Node
var online := false
var is_host := false
var local_pid := 1
var mode := "solo"
var port := DEFAULT_PORT
var _peer: ENetMultiplayerPeer
var _peer_pid: Dictionary = {}
var _next_pid := 2
var _state_clock := 0.0
var _snap_clock := 0.0
var _seq := 0
var _last_snapshot_ms := 0
var _ride_sent := false


func setup(p_stage: Node) -> void:
	stage = p_stage
	name = "Act1CoopNet"
	var args := OS.get_cmdline_args()
	var pidx := args.find("--port")
	if pidx >= 0 and pidx + 1 < args.size():
		port = int(args[pidx + 1])
	if "--host" in args:
		start_host()
	elif "--client" in args:
		var ip := "127.0.0.1"
		var ipidx := args.find("--host-ip")
		if ipidx >= 0 and ipidx + 1 < args.size():
			ip = str(args[ipidx + 1])
		start_client(ip)


func start_host() -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 3)
	if err != OK:
		push_error("Act1CoopNet ENet host failed: %d" % err)
		mode = "solo"
		return err
	_peer = peer
	multiplayer.multiplayer_peer = _peer
	is_host = true
	online = true
	mode = "host"
	local_pid = 1
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("ACT1_COOP_NET host port=%d pid=1" % port)
	connected_changed.emit(true)
	return OK


func start_client(address: String) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("Act1CoopNet ENet client failed: %d" % err)
		mode = "solo"
		return err
	_peer = peer
	multiplayer.multiplayer_peer = _peer
	is_host = false
	online = true
	mode = "client"
	local_pid = 2
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	print("ACT1_COOP_NET client dial=%s:%d pid=2" % [address, port])
	return OK


func shutdown() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	online = false


func is_online() -> bool:
	return online


func peer_count() -> int:
	if not online:
		return 1
	return multiplayer.get_peers().size() + 1


func is_authority() -> bool:
	return not online or is_host


func enet_for_pid(pid: int) -> int:
	for enet in _peer_pid.keys():
		if int(_peer_pid[enet]) == pid:
			return int(enet)
	return 0


func peer_pids() -> Array[int]:
	var out: Array[int] = []
	for key in _peer_pid.keys():
		out.append(int(_peer_pid[key]))
	out.sort()
	return out


func submit_interaction(id: String, kind: String) -> void:
	if is_host:
		return
	if not _network_ready():
		return
	request_interaction.rpc_id(1, id, kind)


func submit_reset() -> void:
	if is_host:
		return
	if _network_ready():
		request_reset.rpc_id(1)


func notify_ride(completion: Dictionary) -> void:
	if is_host or not online:
		return
	# The host owns the completion packet; clients wait for its reliable RPC.


func _network_ready() -> bool:
	if not online or multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _process(delta: float) -> void:
	if not online:
		return
	if is_host:
		_host_tick(delta)
	elif _network_ready():
		_client_tick(delta)


func _host_tick(delta: float) -> void:
	_snap_clock -= delta
	if _snap_clock > 0.0:
		return
	_snap_clock = 1.0 / SNAPSHOT_HZ
	_seq += 1
	if multiplayer.get_peers().size() > 0:
		sync_snapshot.rpc(stage.call("build_snapshot", _seq))


func _client_tick(delta: float) -> void:
	_state_clock -= delta
	if _state_clock > 0.0:
		return
	_state_clock = 1.0 / STATE_HZ
	request_state.rpc_id(1, stage.call("get_local_state"))


@rpc("any_peer", "call_remote", "reliable")
func request_interaction(id: String, kind: String) -> void:
	if not is_host:
		return
	var enet_id := multiplayer.get_remote_sender_id()
	var pid := int(_peer_pid.get(enet_id, 0))
	if pid == 0:
		print("ACT1_COOP_NET interaction rejected reason=unknown_sender enet=%d" % enet_id)
		return
	stage.call("host_handle_interaction_request", pid, id, kind)


@rpc("authority", "call_remote", "reliable")
func grant_hold(id: String, pid: int, payload: Dictionary) -> void:
	if is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _authority_sender_ok(sender, "grant_hold"):
		return
	if pid != local_pid:
		print("ACT1_COOP_NET grant rejected reason=recipient id=%s pid=%d local=%d sender=%d" % [
			id, pid, local_pid, sender])
		return
	stage.call("client_apply_grant", id, payload, sender, pid)


func _authority_sender_ok(sender: int, channel: String) -> bool:
	# The @rpc authority annotation is layer 1; this explicit check is layer 2
	# and survives an accidental annotation change or a host proxy mistake.
	if sender == 1 and not multiplayer.is_server():
		return true
	print("ACT1_COOP_NET authority reject channel=%s sender=%d server=%s online=%s" % [
		channel, sender, str(multiplayer.is_server()), str(online)])
	return false


@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_state(state: Dictionary) -> void:
	if not is_host:
		return
	var pid := int(_peer_pid.get(multiplayer.get_remote_sender_id(), 0))
	if pid == 0:
		return
	stage.call("host_receive_state", pid, state)


@rpc("authority", "call_remote", "unreliable_ordered")
func sync_snapshot(snap: Dictionary) -> void:
	if is_host:
		return
	if not _authority_sender_ok(multiplayer.get_remote_sender_id(), "sync_snapshot"):
		return
	_last_snapshot_ms = Time.get_ticks_msec()
	stage.call("client_apply_snapshot", snap)


@rpc("authority", "call_remote", "reliable")
func sync_bootstrap(snap: Dictionary) -> void:
	if is_host:
		return
	if not _authority_sender_ok(multiplayer.get_remote_sender_id(), "sync_bootstrap"):
		return
	_last_snapshot_ms = Time.get_ticks_msec()
	stage.call("client_apply_snapshot", snap)


@rpc("authority", "call_remote", "reliable")
func welcome(pid: int) -> void:
	if is_host:
		return
	if not _authority_sender_ok(multiplayer.get_remote_sender_id(), "welcome"):
		return
	if pid < 1 or pid > 4:
		return
	local_pid = pid
	stage.call("set_local_pid", pid)


@rpc("any_peer", "call_remote", "reliable")
func request_reset() -> void:
	if not is_host:
		return
	var enet_id: int = multiplayer.get_remote_sender_id()
	var pid: int = int(_peer_pid.get(enet_id, 0))
	if pid == 0:
		print("ACT1_COOP_NET reset rejected reason=unknown_sender enet=%d" % enet_id)
		return
	stage.call("host_reset_run", enet_id)


@rpc("authority", "call_remote", "reliable")
func do_reset(seq: int) -> void:
	if is_host:
		return
	if not _authority_sender_ok(multiplayer.get_remote_sender_id(), "do_reset"):
		return
	if seq < 0 or seq > 1000000:
		return
	stage.call("client_reset_run", seq)


@rpc("authority", "call_remote", "reliable")
func start_ride(completion: Dictionary) -> void:
	if is_host:
		return
	if not _authority_sender_ok(multiplayer.get_remote_sender_id(), "start_ride"):
		return
	if completion.size() > 32:
		return
	ride_started.emit(local_pid, completion)
	stage.call("begin_scene_handoff", completion)


@rpc("authority", "call_remote", "reliable")
func sync_message(text: String, seconds: float) -> void:
	if not _authority_sender_ok(multiplayer.get_remote_sender_id(), "sync_message"):
		return
	if text.length() > 512 or not is_finite(seconds) or seconds < 0.0 or seconds > 30.0:
		return
	stage.call("show_network_message", text, seconds)


func _on_peer_connected(enet_id: int) -> void:
	if _next_pid > 4:
		_peer.disconnect_peer(enet_id)
		return
	var pid := _next_pid
	_next_pid += 1
	_peer_pid[enet_id] = pid
	print("ACT1_COOP_NET peer_connected enet=%d pid=%d peers=%d" % [enet_id, pid, multiplayer.get_peers().size()])
	welcome.rpc_id(enet_id, pid)
	stage.call("host_add_player", pid)
	sync_bootstrap.rpc_id(enet_id, stage.call("build_snapshot", _seq))
	peer_joined.emit(pid)


func _on_peer_disconnected(enet_id: int) -> void:
	var pid := int(_peer_pid.get(enet_id, 0))
	_peer_pid.erase(enet_id)
	if pid != 0:
		print("ACT1_COOP_NET peer_disconnected enet=%d pid=%d" % [enet_id, pid])
		stage.call("host_remove_player", pid)
		peer_left.emit(pid)


func _on_connected() -> void:
	online = true
	mode = "client"
	print("ACT1_COOP_NET connected pid=%d" % local_pid)
	connected_changed.emit(true)


func _on_connection_failed() -> void:
	online = false
	mode = "solo"
	print("ACT1_COOP_NET connection_failed")
	connected_changed.emit(false)


func _on_server_disconnected() -> void:
	online = false
	mode = "solo"
	print("ACT1_COOP_NET server_disconnected")
	connected_changed.emit(false)