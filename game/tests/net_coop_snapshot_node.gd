extends Node

## Two-process probe for the REAL CoopNet Act05 snapshot RPCs, without loading
## the heavy Act05 scene. It starts the shared SessionHub ENet peer on an
## isolated port, sends a realistic two-player snapshot through
## `_send_snapshot_chunks`, and checks that the client's production
## `sync_snapshot_*` handlers reassemble/apply it. This exercises the same
## @rpc authority/sender checks, compression, packet budget and assembler used by
## the game; only LevelBuilder-side application is intentionally absent.

const Wire := preload("res://scripts/coop/snapshot_wire.gd")
const PORT_DEFAULT := 19880
const TARGET_SEQ := 701
const LIVE_SEQ := 702

var role := "host"
var port := PORT_DEFAULT
var out_dir := ""
var hub: Node = null
var net: Node = null
var checks := 0
var failures: Array[String] = []
var sent_parts := 0
var sent_max := 0
var peer_ready := false
var ack_stats: Dictionary = {}
var _finished := false
var _acked := false
var _connected_noted := false
var _started_ms := 0


func configure(p_role: String, p_port: int, p_out: String) -> void:
	role = p_role
	port = p_port
	out_dir = p_out


func _ready() -> void:
	name = "SnapshotCoopProbe"
	_started_ms = Time.get_ticks_msec()
	hub = get_tree().root.get_node_or_null("/root/SessionHub")
	_check(hub != null, "SessionHub autoload exists")
	if hub == null:
		_finish(false)
		return
	net = hub.get("net") as Node
	_check(net != null, "CoopNet exists")
	if net == null:
		_finish(false)
		return
	if role == "host":
		multiplayer.peer_connected.connect(_on_peer_connected)
		var err: int = int(hub.call("start", true, port))
		_check(err == OK, "host started on isolated port %d (err=%d)" % [port, err])
	else:
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(func() -> void: _finish(false))
		var err2: int = int(hub.call("start", false, port, "127.0.0.1"))
		_check(err2 == OK, "client started on isolated port %d (err=%d)" % [port, err2])
		_on_connected.call_deferred()
	get_tree().create_timer(25.0).timeout.connect(_on_watchdog)


func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print(("PASS " if ok else "FAIL ") + text)


func _fixture(seq: int) -> Dictionary:
	var players: Dictionary = {
		1: {"pos": Vector3(1.0, 0.05, -2.0), "yaw": 0.1, "grab": false, "op": true},
		2: {"pos": Vector3(3.0, 0.05, -4.0), "yaw": 0.2, "grab": true, "op": false},
	}
	var noise := PackedByteArray()
	var state: int = 0x13572468
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
		"stabs": [
			{"ext": 0.1, "press": 0.2, "latched": false, "active": 0},
			{"ext": 0.2, "press": 0.3, "latched": false, "active": 0},
			{"ext": 0.3, "press": 0.4, "latched": false, "active": 0},
			{"ext": 0.4, "press": 0.5, "latched": false, "active": 0},
		],
		"catwalk": {"tilt": 0.0, "pins": 0, "preload_state": 0.0, "reel": 0.0, "lock": 0.0},
		"brake": {"press": 0.0, "latched": false, "active": 0, "assist": 0},
		"damper": {"press": 0.0, "latched": false, "active": 0},
		"iso": {"pin": false, "progress": 0.0, "separated": false, "active": 0},
		"stage": 0, "checkpoint": 0,
		"surge": {"timer": 0.0, "strength": 0.0, "state": "idle"},
		"ledger": {},
		"claims": {},
		"players": players,
		"completed": false,
		"completion": "",
		"reset_seq": 0,
		"peer_count": 2,
		"transport_noise": noise,
	}


func _on_connected() -> void:
	if role != "client" or _connected_noted:
		return
	_connected_noted = true
	_check(int(net.get("local_pid")) == 2, "client seated as pid 2")
	_check(bool(net.get("online")), "client peer online")


func _on_peer_connected(id: int) -> void:
	if role != "host" or peer_ready:
		return
	peer_ready = true
	await get_tree().create_timer(0.35).timeout
	var snap: Dictionary = _fixture(TARGET_SEQ)
	var packets: Array[Dictionary] = Wire.encode_packets(TARGET_SEQ, snap, true)
	sent_parts = packets.size()
	for packet in packets:
		sent_max = maxi(sent_max, var_to_bytes(packet).size())
	net.call("_send_snapshot_chunks", snap, id, true)
	await get_tree().create_timer(0.25).timeout
	var live_snap: Dictionary = _fixture(LIVE_SEQ)
	net.call("_send_snapshot_chunks", live_snap, id, false)


func _process(_delta: float) -> void:
	if role != "client" or _finished or _acked:
		return
	var stats: Dictionary = net.call("snapshot_stats") as Dictionary
	if int(stats.get("apply", 0)) >= 2:
		_acked = true
		probe_ack.rpc_id(1, stats)
		await get_tree().create_timer(1.0).timeout
		_check(int(stats.get("last_applied_seq", -1)) >= LIVE_SEQ,
			"client applied the live snapshot sequence")
		_finish(failures.is_empty())


@rpc("any_peer", "call_remote", "reliable")
func probe_ack(stats: Dictionary) -> void:
	if role != "host":
		return
	ack_stats = stats.duplicate(true)
	_check(int(stats.get("apply", 0)) >= 2, "client applied both snapshot sequences")
	_check(int(stats.get("last_applied_seq", -1)) >= LIVE_SEQ,
		"client applied the newest sequence (got %d)" % int(stats.get("last_applied_seq", -1)))
	_check(int(stats.get("packet_bytes_max", 99999)) <= 1200,
		"client received only sub-1200 B snapshot packets (max=%d)" % int(stats.get("packet_bytes_max", -1)))
	var rx: Dictionary = stats.get("rx", {}) as Dictionary
	_check(int(rx.get("completed", 0)) >= 1, "production assembler completed the live snapshot")
	_check(sent_parts > 1, "production host sent a multi-packet snapshot (%d parts)" % sent_parts)
	_check(sent_max <= 1200, "host packet budget stayed below 1200 B (max=%d)" % sent_max)
	await get_tree().create_timer(0.8).timeout
	_finish(failures.is_empty())


func _on_watchdog() -> void:
	if _finished:
		return
	_check(false, "watchdog without a complete ack")
	_finish(false)


func _finish(passed: bool) -> void:
	if _finished:
		return
	_finished = true
	var report: Dictionary = {
		"probe": "net_coop_snapshot_probe",
		"role": role,
		"port": port,
		"passed": passed,
		"checks": checks,
		"failures": failures,
		"sent_parts": sent_parts,
		"sent_max_packet_bytes": sent_max,
		"client_stats": ack_stats,
		"elapsed_seconds": float(Time.get_ticks_msec() - _started_ms) / 1000.0,
	}
	print("COOP_SNAPSHOT_RESULT " + JSON.stringify(report))
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("coop_snapshot_%s.json" % role), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	get_tree().quit(0 if passed and failures.is_empty() else 1)
