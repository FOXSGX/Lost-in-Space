extends SceneTree

## Act05 snapshot real-scene test.
## Loads the real Act05 scene, seeds a second participant in the in-memory
## session mirror (not a completion/ledger claim), builds the same dictionary
## the host broadcasts, verifies the sub-MTU wire envelope and the receive-side
## shape guards. It never sends on the official port and never edits machine or
## story state.

const ACT5_SCENE := "res://scenes/main.tscn"
const Wire := preload("res://scripts/coop/snapshot_wire.gd")
const Assembler := preload("res://scripts/coop/snapshot_assembler.gd")

var out_dir := ""
var checks := 0
var failures: Array[String] = []


func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print(("PASS " if ok else "FAIL ") + text)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not str(args[0]).begins_with("--"):
		out_dir = str(args[0])
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	var packed: PackedScene = load(ACT5_SCENE) as PackedScene
	if packed == null:
		print("SNAPSHOT_AUDIT_FAIL scene_load")
		quit(1)
		return
	change_scene_to_packed(packed)
	await _wait(2.0)
	var app: Node = current_scene
	if app == null:
		print("SNAPSHOT_AUDIT_FAIL no_scene")
		quit(1)
		return
	var hub: Node = root.get_node_or_null("/root/SessionHub")
	var session: Node = hub.get("session") as Node
	var net: Node = hub.get("net") as Node
	if session == null or net == null:
		print("SNAPSHOT_AUDIT_FAIL no_session")
		quit(1)
		return
	# A second participant is already how the real two-process host would look.
	# This only populates the session mirror; no credit/phase/completion changes.
	session.add_player(2, "审计队友")
	session.set_player_state(2, {
		"pos": Vector3(4.0, 0.05, -4.0),
		"yaw": 0.4,
		"grab": false,
		"op": false,
		"impaired": 0.0,
		"op_machine": "",
	})
	var snap: Dictionary = net.build_snapshot()
	var raw: PackedByteArray = var_to_bytes(snap)
	var comp: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
	var packets: Array[Dictionary] = Wire.encode_packets(int(snap.get("seq", 0)), snap, false)
	var max_packet := 0
	for packet in packets:
		max_packet = maxi(max_packet, var_to_bytes(packet).size())
	var assembler = Assembler.new()
	var reassembled: Dictionary = {}
	for packet in packets:
		var result: Dictionary = assembler.accept(packet, 1000)
		if str(result.get("status", "")) == "complete":
			reassembled = (result.get("snapshot", {}) as Dictionary).duplicate(true)
	_check((snap.get("players", {}) as Dictionary).size() == 2, "two-player real snapshot built")
	_check(raw.size() > 1392, "raw snapshot is larger than MTU (measured %d B)" % raw.size())
	_check(not packets.is_empty(), "snapshot encodes to at least one packet")
	_check(max_packet > 0 and max_packet < 1392, "wire packet is below MTU (%d B)" % max_packet)
	_check(not reassembled.is_empty(), "packets reassemble to a snapshot")
	_check(Wire.checksum(var_to_bytes(reassembled)) == Wire.checksum(raw),
		"reassembled snapshot preserves all fields")
	_check(bool(net.call("_snapshot_shape_ok", reassembled)), "real snapshot passes the receive shape guard")
	# Apply the decoded snapshot through the production client path (the test
	# process exits immediately afterwards; no ledger credit/completion is
	# written). This proves the authoritative fields reach the local mirrors.
	var expected_cart: float = float((reassembled["carts"] as Dictionary)["left"])
	var expected_core_net: float = float((reassembled["core"] as Dictionary)["net"])
	net.call("_apply_snapshot", reassembled)
	var level: Node = app.get("level") as Node
	_check(is_equal_approx(float(level.get("left_cart").call("get_p")), expected_cart),
		"decoded snapshot drives the cart mirror")
	_check(is_equal_approx(float(level.get("core").get("remote_net")), expected_core_net),
		"decoded snapshot drives the core mirror")

	var bad_players: Dictionary = reassembled.duplicate(true)
	(bad_players["players"] as Dictionary)[5] = {"pos": Vector3.ZERO, "yaw": 0.0}
	_check(not bool(net.call("_snapshot_shape_ok", bad_players)), "fifth player is rejected")
	var bad_pos: Dictionary = reassembled.duplicate(true)
	((bad_pos["players"] as Dictionary)[1] as Dictionary)["pos"] = Vector3(NAN, 0.0, 0.0)
	_check(not bool(net.call("_snapshot_shape_ok", bad_pos)), "NaN player position is rejected")
	var bad_stage: Dictionary = reassembled.duplicate(true)
	bad_stage["stage"] = 99
	_check(not bool(net.call("_snapshot_shape_ok", bad_stage)), "unknown story stage is rejected")
	var bad_checkpoint: Dictionary = reassembled.duplicate(true)
	bad_checkpoint["checkpoint"] = 4
	_check(not bool(net.call("_snapshot_shape_ok", bad_checkpoint)), "out-of-range checkpoint is rejected")
	var bad_stabs: Dictionary = reassembled.duplicate(true)
	var nine: Array = []
	for i in range(9):
		nine.append({})
	bad_stabs["stabs"] = nine
	_check(not bool(net.call("_snapshot_shape_ok", bad_stabs)), "oversized stabilizer array is rejected")
	var bad_cart: Dictionary = reassembled.duplicate(true)
	(bad_cart["carts"] as Dictionary)["left"] = 2.5
	_check(not bool(net.call("_snapshot_shape_ok", bad_cart)), "out-of-range cart progress is rejected")
	var bad_text: Dictionary = reassembled.duplicate(true)
	bad_text["completion"] = "x".repeat(513)
	_check(not bool(net.call("_snapshot_shape_ok", bad_text)), "oversized completion text is rejected")

	var report: Dictionary = {
		"probe": "net_snapshot_audit.gd",
		"checks": checks,
		"failures": failures,
		"players": (snap.get("players", {}) as Dictionary).size(),
		"ledger_players": session.ledger.player_ids().size() if session.ledger != null else -1,
		"raw_bytes": raw.size(),
		"zstd_bytes": comp.size(),
		"mtu": 1392,
		"over_mtu": raw.size() > 1392,
		"wire_packets": packets.size(),
		"wire_max_packet_bytes": max_packet,
		"wire_under_mtu": max_packet > 0 and max_packet < 1392,
		"reassembled": not reassembled.is_empty(),
		"reassembled_equal": Wire.checksum(var_to_bytes(reassembled)) == Wire.checksum(raw),
		"shape_ok": bool(net.call("_snapshot_shape_ok", reassembled)),
		"keys": snap.keys(),
	}
	print("SNAPSHOT_AUDIT " + JSON.stringify(report))
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var path := out_dir.path_join("snapshot_size.json")
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	if failures.is_empty():
		print("ACT5_SNAPSHOT_OK checks=%d" % checks)
	else:
		print("ACT5_SNAPSHOT_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
