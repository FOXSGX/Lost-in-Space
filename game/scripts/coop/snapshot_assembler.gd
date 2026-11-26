class_name CoopSnapshotAssembler
extends RefCounted

## Reassembles CoopSnapshotWire packets without trusting arrival order.
## Partial snapshots are discarded (never applied) on timeout or when a newer
## sequence starts. Duplicate chunks are idempotent; out-of-order chunks are
## accepted by index. The caller owns timeout scheduling so this stays unit-
## testable without SceneTree timers.

const WIRE_VERSION := 1
const DEFAULT_TIMEOUT_MS := 750
const SnapshotWire := preload("res://scripts/coop/snapshot_wire.gd")

var active_seq: int = -1
var active_count: int = 0
var active_raw_size: int = 0
var active_packed_size: int = 0
var active_checksum: int = -1
var active_bootstrap: bool = false
var started_ms: int = 0
var highest_completed_seq: int = -1
var _parts: Dictionary = {}

var stats: Dictionary = {
	"packets": 0,
	"completed": 0,
	"duplicates": 0,
	"stale": 0,
	"rejects": 0,
	"timeouts": 0,
	"superseded": 0,
	"bytes": 0,
}


## Clears the in-flight assembly only. `highest_completed_seq` is deliberately
## kept: `accept()` calls this when a newer seq supersedes a partial one, and
## dropping the replay watermark there would let an old snapshot through.
func reset() -> void:
	active_seq = -1
	active_count = 0
	active_raw_size = 0
	active_packed_size = 0
	active_checksum = -1
	active_bootstrap = false
	started_ms = 0
	_parts.clear()


## Clears the assembly AND the replay watermark. Must be called whenever the
## transport session restarts (rebind / reconnect): the host's seq counter
## starts again at 0, and a stale watermark would reject every packet as
## "stale" until the counter climbs back past the old value (~4700 seq ≈ 5 min
## at 15 Hz), leaving the client frozen on an old world state.
func reset_session() -> void:
	reset()
	highest_completed_seq = -1


## Returns one of:
##   {status: partial|complete|duplicate|stale|rejected|timeout}
## For complete: snapshot is the decoded Dictionary.
func accept(packet: Dictionary, now_ms: int) -> Dictionary:
	stats["packets"] = int(stats["packets"]) + 1
	var validated: Dictionary = SnapshotWire.validate_packet(packet, now_ms)
	if not bool(validated.get("ok", false)):
		stats["rejects"] = int(stats["rejects"]) + 1
		return {"status": "rejected", "reason": str(validated.get("reason", "invalid"))}

	var seq: int = int(validated["seq"])
	if seq <= highest_completed_seq:
		stats["stale"] = int(stats["stale"]) + 1
		return {"status": "stale", "seq": seq}
	if active_seq >= 0 and seq < active_seq:
		stats["stale"] = int(stats["stale"]) + 1
		return {"status": "stale", "seq": seq}
	if active_seq >= 0 and seq > active_seq:
		stats["superseded"] = int(stats["superseded"]) + 1
		reset()
	if active_seq < 0:
		active_seq = seq
		active_count = int(validated["count"])
		active_raw_size = int(validated["raw_size"])
		active_packed_size = int(validated["packed_size"])
		active_checksum = int(validated["checksum"])
		active_bootstrap = bool(validated["bootstrap"])
		started_ms = now_ms
	elif active_count != int(validated["count"]) \
			or active_raw_size != int(validated["raw_size"]) \
			or active_packed_size != int(validated["packed_size"]) \
			or active_checksum != int(validated["checksum"]) \
			or active_bootstrap != bool(validated["bootstrap"]):
		stats["rejects"] = int(stats["rejects"]) + 1
		reset()
		return {"status": "rejected", "reason": "header_mismatch", "seq": seq}

	var part: int = int(validated["part"])
	if _parts.has(part):
		stats["duplicates"] = int(stats["duplicates"]) + 1
		return {"status": "duplicate", "seq": seq, "part": part}
	_parts[part] = (validated["data"] as PackedByteArray).duplicate()
	stats["bytes"] = int(stats["bytes"]) + (validated["data"] as PackedByteArray).size()

	if _parts.size() < active_count:
		return {
			"status": "partial",
			"seq": seq,
			"received": _parts.size(),
			"count": active_count,
		}
	if _parts.size() != active_count:
		stats["rejects"] = int(stats["rejects"]) + 1
		reset()
		return {"status": "rejected", "reason": "part_overflow", "seq": seq}

	var packed: PackedByteArray = PackedByteArray()
	for index in range(active_count):
		if not _parts.has(index):
			stats["rejects"] = int(stats["rejects"]) + 1
			reset()
			return {"status": "rejected", "reason": "part_missing", "seq": seq}
		packed.append_array(_parts[index] as PackedByteArray)
	if packed.size() != active_packed_size:
		stats["rejects"] = int(stats["rejects"]) + 1
		reset()
		return {"status": "rejected", "reason": "packed_size", "seq": seq}

	var snapshot: Dictionary = SnapshotWire.decode(packed, active_raw_size, active_checksum)
	if snapshot.is_empty() or int(snapshot.get("seq", -1)) != active_seq:
		stats["rejects"] = int(stats["rejects"]) + 1
		reset()
		return {"status": "rejected", "reason": "decode", "seq": seq}

	var completed_seq: int = active_seq
	var completed_parts: int = active_count
	var bootstrap: bool = active_bootstrap
	highest_completed_seq = completed_seq
	stats["completed"] = int(stats["completed"]) + 1
	reset()
	return {
		"status": "complete",
		"seq": completed_seq,
		"snapshot": snapshot,
		"bootstrap": bootstrap,
		"parts": completed_parts,
	}


func expire(now_ms: int, timeout_ms: int = DEFAULT_TIMEOUT_MS) -> Dictionary:
	if active_seq < 0:
		return {"status": "idle"}
	if now_ms - started_ms <= timeout_ms:
		return {"status": "partial"}
	var seq: int = active_seq
	reset()
	stats["timeouts"] = int(stats["timeouts"]) + 1
	return {"status": "timeout", "seq": seq}

