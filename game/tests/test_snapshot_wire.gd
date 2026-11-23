extends SceneTree

## Pure wire-format tests for CoopSnapshotWire + CoopSnapshotAssembler.
## No scene, no ENet port, no authority-ledger writes. Proves the packet budget,
## reassembly under reorder/duplicate, loss/timeout recovery, and integrity
## rejection before the production snapshot path is exercised.

const Wire := preload("res://scripts/coop/snapshot_wire.gd")
const Assembler := preload("res://scripts/coop/snapshot_assembler.gd")

var out_dir := ""
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not str(args[0]).begins_with("--"):
		out_dir = str(args[0])
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print(("PASS " if ok else "FAIL ") + text)


func _fixture() -> Dictionary:
	var players: Dictionary = {}
	for pid in [1, 2]:
		players[pid] = {
			"pos": Vector3(2.0 * pid, 0.05, -4.0 * pid),
			"yaw": 0.25 * pid,
			"grab": false,
			"op": pid == 2,
		}
	return {
		"seq": 41,
		"time": 123456,
		"core": {"net": 0.72, "angle": 1.2, "omega": 0.05, "locked": true,
			"locking": false, "capturable": true, "left_p": 0.4, "right_p": 0.6,
			"surge_timer": 12.5, "surge_strength": 0.2, "data_mode": 1},
		"carts": {"left": 0.25, "right": 0.75},
		"lever": {"left": 0.1, "right": 0.2},
		"active": {"cart_left": 1, "cart_right": 2},
		"stabs": [
			{"ext": 0.3, "press": 0.51, "latched": false, "active": 1},
			{"ext": 0.4, "press": 0.52, "latched": true, "active": 2},
			{"ext": 0.5, "press": 0.53, "latched": false, "active": 0},
			{"ext": 0.6, "press": 0.54, "latched": false, "active": 0},
		],
		"catwalk": {"tilt": 0.12, "pins": 2, "preload_state": 0.35, "reel": 0.0, "lock": 0.0},
		"brake": {"press": 0.45, "latched": false, "active": 1, "assist": 0},
		"damper": {"press": 0.15, "latched": true, "active": 2},
		"iso": {"pin": true, "progress": 0.8, "separated": false, "active": 2},
		"stage": 5,
		"checkpoint": 2,
		"surge": {"timer": 8.0, "strength": 0.3, "state": "warning"},
		"ledger": {
			"1": {"id": 1, "name": "七号", "status": "active", "phases": {"A": true},
				"kinds": ["stabilizer_lock", "surge_response"], "ready": true, "last_action": 123.0},
			"2": {"id": 2, "name": "队友", "status": "active", "phases": {"A": true},
				"kinds": ["brake_charge", "isolation_pin"], "ready": true, "last_action": 124.0},
		},
		"claims": {"cart_left": 1, "cart_right": 2},
		"players": players,
		"completed": false,
		"completion": "",
		"reset_seq": 0,
		"peer_count": 2,
	}


func _chunk_fixture(seq: int) -> Dictionary:
	var snap: Dictionary = _fixture()
	snap["seq"] = seq
	# Deterministic, weakly-compressible filler forces the multi-packet branch
	# without relying on a particular Zstd ratio for gameplay fields.
	var noise := PackedByteArray()
	var state: int = 0x13579BDF
	for _i in range(4096):
		state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
		noise.append(state & 0xFF)
	snap["wire_noise"] = noise
	return snap


func _run() -> void:
	var snap: Dictionary = _fixture()
	var packets: Array[Dictionary] = Wire.encode_packets(int(snap["seq"]), snap, false)
	_check(not packets.is_empty(), "fixture encodes to packets")
	var max_bytes := 0
	for packet in packets:
		max_bytes = maxi(max_bytes, var_to_bytes(packet).size())
	_check(max_bytes <= 1200, "every packet stays below 1200 B (max=%d, parts=%d)" % [max_bytes, packets.size()])
	_check(packets[0]["raw_size"] == var_to_bytes(snap).size(),
		"packet reports the raw snapshot size")
	var single: Dictionary = Assembler.new().accept(packets[0], 900)
	_check(str(single.get("status", "")) == "complete", "the normal snapshot fits one sub-MTU packet")

	# Multi-packet path: out-of-order delivery + duplicate before completion.
	var chunk_snap: Dictionary = _chunk_fixture(50)
	var chunk_packets: Array[Dictionary] = Wire.encode_packets(50, chunk_snap, false)
	_check(chunk_packets.size() > 1, "weakly-compressible fixture splits into chunks (%d)" % chunk_packets.size())
	var chunk_max := 0
	for packet in chunk_packets:
		chunk_max = maxi(chunk_max, var_to_bytes(packet).size())
	_check(chunk_max <= 1200, "split chunks stay below 1200 B (max=%d)" % chunk_max)
	var assembler = Assembler.new()
	var duplicate: Dictionary = assembler.accept(chunk_packets[0], 1000)
	_check(str(duplicate["status"]) == "partial", "first chunk is partial")
	var dup: Dictionary = assembler.accept(chunk_packets[0], 1001)
	_check(str(dup["status"]) == "duplicate", "duplicate chunk is counted, not applied")
	var complete: Dictionary = {}
	for i in range(chunk_packets.size() - 1, 0, -1):
		var result: Dictionary = assembler.accept(chunk_packets[i], 1002)
		if i == 1:
			complete = result
	_check(str(complete.get("status", "")) == "complete", "out-of-order chunks reassemble")
	if str(complete.get("status", "")) == "complete":
		var decoded: Dictionary = complete["snapshot"] as Dictionary
		_check(Wire.checksum(var_to_bytes(decoded)) == Wire.checksum(var_to_bytes(chunk_snap)),
			"decoded snapshot preserves every field")
		_check(int(complete.get("parts", 0)) == chunk_packets.size(), "complete reports the packet count")

	# A new sequence supersedes a partial old one; one lost chunk recovers on
	# the next complete sequence.
	var fresh = Assembler.new()
	fresh.accept(chunk_packets[0], 2000)
	var next_snap: Dictionary = _chunk_fixture(51)
	var next_packets: Array[Dictionary] = Wire.encode_packets(51, next_snap, false)
	var recovered: Dictionary = {}
	for packet in next_packets:
		recovered = fresh.accept(packet, 2100)
	_check(str(recovered.get("status", "")) == "complete" and int(recovered.get("seq", -1)) == 51,
		"a lost/incomplete sequence recovers from the next complete sequence")

	# Timeout never yields a partial snapshot.
	var timed = Assembler.new()
	timed.accept(chunk_packets[0], 3000)
	var expired: Dictionary = timed.expire(3000 + Assembler.DEFAULT_TIMEOUT_MS + 1)
	_check(str(expired.get("status", "")) == "timeout", "partial snapshot times out")

	# Integrity: corruption of a compressed byte is rejected.
	var corrupt: Dictionary = (chunk_packets[0] as Dictionary).duplicate(true)
	var data: PackedByteArray = (corrupt["data"] as PackedByteArray).duplicate()
	data[0] = data[0] ^ 0x5A
	corrupt["data"] = data
	var bad = Assembler.new()
	var bad_result: Dictionary = bad.accept(corrupt, 4000)
	if str(bad_result.get("status", "")) == "partial":
		bad_result = bad.accept(chunk_packets[1], 4001)
	_check(str(bad_result.get("status", "")) == "rejected", "corrupt snapshot is rejected at reassembly")

	# Malformed shape/range limits.
	var malformed: Dictionary = chunk_packets[0].duplicate(true)
	malformed["count"] = 33
	_check(str(Assembler.new().accept(malformed, 5000).get("status", "")) == "rejected",
		"oversized chunk count is rejected")
	var bad_version: Dictionary = chunk_packets[0].duplicate(true)
	bad_version["v"] = 999
	_check(str(Assembler.new().accept(bad_version, 5000).get("status", "")) == "rejected",
		"unknown wire version is rejected")

	var report: Dictionary = {
		"probe": "test_snapshot_wire.gd",
		"checks": checks,
		"failures": failures,
		"normal_parts": packets.size(),
		"chunk_parts": chunk_packets.size(),
		"raw_bytes": var_to_bytes(snap).size(),
		"max_packet_bytes": maxi(max_bytes, chunk_max),
		"mtu": 1392,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("snapshot_wire.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	print("SNAPSHOT_WIRE_RESULT checks=%d failures=%d parts=%d max_packet=%d" % [
		checks, failures.size(), packets.size(), max_bytes])
	if failures.is_empty():
		print("SNAPSHOT_WIRE_OK")
	else:
		print("SNAPSHOT_WIRE_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
