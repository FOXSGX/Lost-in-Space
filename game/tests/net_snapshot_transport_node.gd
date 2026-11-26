extends Node

## Minimal real-ENet transport probe for the Act05 snapshot wire format.
## Deliberately does not load the Act05 scene: it isolates the same
## CoopSnapshotWire/Assembler packet path and keeps the two-process probe light
## enough to run beside other work. The official port 9877 is never used.

const Wire := preload("res://scripts/coop/snapshot_wire.gd")
const Assembler := preload("res://scripts/coop/snapshot_assembler.gd")
const PORT_DEFAULT := 19879

var role := "host"
var port := PORT_DEFAULT
var out_dir := ""
var assembler_reliable = Assembler.new()
var assembler_live = Assembler.new()
var expected_checksum := 0
var wire_checksum := 0
var wire_parts := 0
var expected_seq := 701
var received_reliable := 0
var received_live := 0
var max_packet_bytes := 0
var sent_parts := 0
var sent_max := 0
var reliable_done := false
var live_done := false
var ack_seen := false
var started_ms := 0
var _finished := false
var _client_peer := 0
var _live_sent := false


func configure(p_role: String, p_port: int, p_out: String) -> void:
	role = p_role
	port = p_port
	out_dir = p_out


func _ready() -> void:
	name = "SnapshotTransport"
	started_ms = Time.get_ticks_msec()
	if role == "host":
		var peer := ENetMultiplayerPeer.new()
		var err: int = peer.create_server(port, 1)
		if err != OK:
			_finish(false, "host_create_%d" % err)
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_on_peer_connected)
		print("NET_TRANSPORT host listening port=%d" % port)
	else:
		var peer2 := ENetMultiplayerPeer.new()
		var err2: int = peer2.create_client("127.0.0.1", port)
		if err2 != OK:
			_finish(false, "client_create_%d" % err2)
			return
		multiplayer.multiplayer_peer = peer2
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(func() -> void: _finish(false, "connect_failed"))
		multiplayer.server_disconnected.connect(func() -> void: _finish(false, "server_lost"))
		print("NET_TRANSPORT client dialing port=%d" % port)
	get_tree().create_timer(25.0).timeout.connect(_on_watchdog)


func _fixture(seq: int) -> Dictionary:
	var players: Dictionary = {
		1: {"pos": Vector3(1, 0.05, -2), "yaw": 0.1, "grab": false, "op": true},
		2: {"pos": Vector3(3, 0.05, -4), "yaw": 0.2, "grab": true, "op": false},
	}
	var noise := PackedByteArray()
	var state: int = 0x2468ACE
	for _i in range(8192):
		state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
		noise.append((state >> 8) & 0xFF)
	return {
		"seq": seq,
		"time": Time.get_ticks_msec(),
		"core": {"net": 0.5, "angle": 0.3, "omega": 0.01, "locked": false,
			"locking": false, "capturable": false, "left_p": 0.2, "right_p": 0.8,
			"surge_timer": 1.0, "surge_strength": 0.0, "data_mode": 0},
		"carts": {"left": 0.1, "right": 0.9},
		"lever": {"left": 0.0, "right": 0.0},
		"active": {},
		"stabs": [],
		"catwalk": {"tilt": 0.0, "pins": 0, "preload_state": 0.0, "reel": 0.0, "lock": 0.0},
		"brake": {"press": 0.0, "latched": false, "active": 0, "assist": 0},
		"damper": {"press": 0.0, "latched": false, "active": 0},
		"iso": {"pin": false, "progress": 0.0, "separated": false, "active": 0},
		"stage": 0, "checkpoint": 0,
		"surge": {"timer": 0.0, "strength": 0.0, "state": "idle"},
		"ledger": {}, "claims": {}, "players": players,
		"completed": false, "completion": "", "reset_seq": 0, "peer_count": 2,
		"transport_noise": noise,
	}


func _on_connected() -> void:
	print("NET_TRANSPORT client connected")
	if role == "client":
		_send_ack.call_deferred()


func _on_peer_connected(id: int) -> void:
	if role != "host":
		return
	_client_peer = id
	var snap: Dictionary = _fixture(expected_seq)
	expected_checksum = Wire.checksum(var_to_bytes(snap))
	var packets: Array[Dictionary] = Wire.encode_packets(expected_seq, snap, true)
	sent_parts = packets.size()
	for packet in packets:
		sent_max = maxi(sent_max, var_to_bytes(packet).size())
		snapshot_reliable.rpc_id(id, packet)
	print("NET_TRANSPORT host sent bootstrap parts=%d max=%d checksum=%d" % [
		sent_parts, sent_max, expected_checksum])
	get_tree().create_timer(0.5).timeout.connect(_send_live)


func _send_live() -> void:
	if role != "host" or _client_peer == 0 or _live_sent:
		return
	_live_sent = true
	var snap: Dictionary = _fixture(expected_seq + 1)
	var packets: Array[Dictionary] = Wire.encode_packets(expected_seq + 1, snap, false)
	for packet in packets:
		sent_max = maxi(sent_max, var_to_bytes(packet).size())
		snapshot_live.rpc_id(_client_peer, packet)
	print("NET_TRANSPORT host sent live parts=%d" % packets.size())


@rpc("authority", "call_remote", "reliable")
func snapshot_reliable(packet: Dictionary) -> void:
	if role != "client":
		return
	received_reliable += 1
	wire_checksum = int(packet.get("checksum", 0))
	wire_parts = int(packet.get("count", 1))
	max_packet_bytes = maxi(max_packet_bytes, var_to_bytes(packet).size())
	var result: Dictionary = assembler_reliable.accept(packet, Time.get_ticks_msec())
	if str(result.get("status", "")) == "complete":
		var snap: Dictionary = result["snapshot"] as Dictionary
		reliable_done = Wire.checksum(var_to_bytes(snap)) == wire_checksum
		print("NET_TRANSPORT client reliable complete seq=%d checksum_ok=%s parts=%d" % [
			int(result.get("seq", -1)), str(reliable_done), int(result.get("parts", 0))])
		_send_ack.call_deferred()


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot_live(packet: Dictionary) -> void:
	if role != "client":
		return
	received_live += 1
	max_packet_bytes = maxi(max_packet_bytes, var_to_bytes(packet).size())
	var result: Dictionary = assembler_live.accept(packet, Time.get_ticks_msec())
	if str(result.get("status", "")) == "complete":
		live_done = int(result.get("seq", -1)) == expected_seq + 1
		print("NET_TRANSPORT client live complete seq=%d parts=%d" % [
			int(result.get("seq", -1)), int(result.get("parts", 0))])
		_send_ack.call_deferred()


func _send_ack() -> void:
	if role != "client" or not reliable_done:
		return
	transport_ack.rpc_id(1, reliable_done, wire_checksum, max_packet_bytes, live_done)
	if live_done:
		await get_tree().create_timer(0.5).timeout
		_finish(true, "reliable_and_live")


@rpc("any_peer", "call_remote", "reliable")
func transport_ack(reliable_ok: bool, sum: int, client_max: int, live_ok: bool) -> void:
	if role != "host":
		return
	ack_seen = true
	var sender: int = multiplayer.get_remote_sender_id()
	print("NET_TRANSPORT host ack sender=%d ok=%s checksum=%d client_max=%d live=%s" % [
		sender, str(reliable_ok), sum, client_max, str(live_ok)])
	if not live_ok:
		return
	# Keep the server up briefly so the client can flush its own pass report
	# instead of seeing a server_lost race.
	await get_tree().create_timer(1.0).timeout
	_finish(reliable_ok and sum == expected_checksum and client_max <= 1200,
		"ack" if reliable_ok else "checksum")


func _on_watchdog() -> void:
	if _finished:
		return
	if role == "client":
		_finish(reliable_done, "client_timeout live=%s" % str(live_done))
	else:
		_finish(false, "host_timeout ack=%s" % str(ack_seen))


func _finish(passed: bool, detail: String) -> void:
	if _finished:
		return
	_finished = true
	var report: Dictionary = {
		"probe": "net_snapshot_transport_probe",
		"role": role,
		"port": port,
		"passed": passed,
		"detail": detail,
		"reliable_parts": wire_parts if role == "client" else sent_parts,
		"received_reliable_packets": received_reliable,
		"received_live_packets": received_live,
		"max_packet_bytes": maxi(max_packet_bytes, sent_max),
		"reliable_done": reliable_done,
		"live_done": live_done,
		"ack_seen": ack_seen,
		"elapsed_seconds": float(Time.get_ticks_msec() - started_ms) / 1000.0,
	}
	print("NET_TRANSPORT_RESULT " + JSON.stringify(report))
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("transport_%s.json" % role), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	get_tree().quit(0 if passed else 1)
