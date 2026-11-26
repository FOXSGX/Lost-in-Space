class_name CoopSnapshotWire
extends RefCounted

## Application-level wire format for the host-authoritative Act05 snapshot.
##
## The raw snapshot is a Variant dictionary (~2.6 KB for two players). It is
## serialized once, Zstd-compressed, checksummed with a deterministic 32-bit
## FNV-1a value, then either sent as one sub-MTU packet or split into bounded
## chunks. The receiver never applies a packet that is malformed, oversized,
## from the wrong sequence, or fails the decompressed-size/checksum check.
##
## This is intentionally independent from ENet's own fragmentation: the
## transport still provides reliability for the join/bootstrap path, while the
## live snapshot path can drop an incomplete tick and recover from the next one.

const VERSION := 1
const MAX_PACKET_BYTES := 1200       # below the 1392-byte ENet MTU
const MAX_SNAPSHOT_BYTES := 32768
const MAX_PARTS := 32
const CHUNK_DATA_BYTES := 768


static func checksum(bytes: PackedByteArray) -> int:
	var value: int = 0x811C9DC5
	for byte in bytes:
		value ^= int(byte)
		value = (value * 16777619) & 0xFFFFFFFF
	return value


## Build one or more packet dictionaries for a snapshot. An empty array means
## the snapshot exceeded a hard safety bound or compression failed; callers must
## log and skip that tick rather than truncate fields.
static func encode_packets(seq: int, snapshot: Dictionary, bootstrap: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if snapshot.is_empty() or seq < 0:
		return result
	var raw: PackedByteArray = var_to_bytes(snapshot)
	if raw.is_empty() or raw.size() > MAX_SNAPSHOT_BYTES:
		return result
	var packed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
	if packed.is_empty():
		return result
	var sum: int = checksum(raw)
	var single: Dictionary = _make_packet(seq, 0, 1, raw.size(), packed.size(), sum, packed, bootstrap)
	if var_to_bytes(single).size() <= MAX_PACKET_BYTES:
		result.append(single)
		return result

	var count: int = int(ceil(float(packed.size()) / float(CHUNK_DATA_BYTES)))
	if count <= 1 or count > MAX_PARTS:
		return result
	for index in range(count):
		var start: int = index * CHUNK_DATA_BYTES
		var end: int = mini(start + CHUNK_DATA_BYTES, packed.size())
		var packet: Dictionary = _make_packet(
			seq, index, count, raw.size(), packed.size(), sum, packed.slice(start, end), bootstrap)
		if var_to_bytes(packet).size() > MAX_PACKET_BYTES:
			return []
		result.append(packet)
	return result


static func _make_packet(
		seq: int, part: int, count: int, raw_size: int, packed_size: int,
		sum: int, data: PackedByteArray, bootstrap: bool) -> Dictionary:
	return {
		"v": VERSION,
		"seq": seq,
		"part": part,
		"count": count,
		"raw_size": raw_size,
		"packed_size": packed_size,
		"checksum": sum,
		"bootstrap": bootstrap,
		"data": data,
	}


## Shape/range validation for one packet. The checksum is verified only after
## all chunks have been reassembled, because a single chunk cannot be decoded.
static func validate_packet(packet: Dictionary, now_ms: int = 0) -> Dictionary:
	if packet.is_empty() or packet.size() > 12:
		return {"ok": false, "reason": "empty_or_extra_fields"}
	if int(packet.get("v", -1)) != VERSION:
		return {"ok": false, "reason": "version"}
	var seq: int = int(packet.get("seq", -1))
	var part: int = int(packet.get("part", -1))
	var count: int = int(packet.get("count", 0))
	var raw_size: int = int(packet.get("raw_size", 0))
	var packed_size: int = int(packet.get("packed_size", 0))
	var sum: int = int(packet.get("checksum", -1))
	if seq < 0:
		return {"ok": false, "reason": "seq"}
	if count < 1 or count > MAX_PARTS or part < 0 or part >= count:
		return {"ok": false, "reason": "part_range"}
	if raw_size < 1 or raw_size > MAX_SNAPSHOT_BYTES or packed_size < 1 or packed_size > MAX_SNAPSHOT_BYTES:
		return {"ok": false, "reason": "size"}
	if sum < 0:
		return {"ok": false, "reason": "checksum_missing"}
	if not (packet.get("bootstrap") is bool):
		return {"ok": false, "reason": "bootstrap_type"}
	var data: Variant = packet.get("data")
	if not (data is PackedByteArray):
		return {"ok": false, "reason": "data_type"}
	var bytes: PackedByteArray = data as PackedByteArray
	if bytes.is_empty() or bytes.size() > MAX_PACKET_BYTES:
		return {"ok": false, "reason": "data_size"}
	if var_to_bytes(packet).size() > MAX_PACKET_BYTES:
		return {"ok": false, "reason": "packet_budget"}
	return {
		"ok": true,
		"seq": seq,
		"part": part,
		"count": count,
		"raw_size": raw_size,
		"packed_size": packed_size,
		"checksum": sum,
		"bootstrap": bool(packet.get("bootstrap", false)),
		"data": bytes,
		"now_ms": now_ms,
	}


## Decode a complete compressed snapshot. Returns {} on any integrity failure.
static func decode(packed: PackedByteArray, raw_size: int, expected_checksum: int) -> Dictionary:
	if packed.is_empty() or raw_size < 1 or raw_size > MAX_SNAPSHOT_BYTES:
		return {}
	var raw: PackedByteArray = packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size or checksum(raw) != expected_checksum:
		return {}
	var value: Variant = bytes_to_var(raw)
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
