extends Node

# -----------------------------------------------------------------------------
# Participation - visible, host-owned record of who actually did work.
#
# This is deliberately NOT a hidden score and it is not a gate on the machinery.
# Every entry is a real action that changed the shared world (departing, braking,
# gripping through the resonance shock, securing a container, hooking the cable,
# working the drum, steering the guide, installing the pin, recovering).
#
# Rules used for the end-of-run verdict:
#   * a slot is CREDITED when it performed at least two different kinds of
#     meaningful work, and at least one of them is core work (a cart control, a
#     cargo handling action, or a rail/winch action);
#   * a connected slot with no meaningful work is reported as WATCHED, never as
#     a co-op completion. It does not block the others: there is no soft lock;
#   * a slot that left is dropped from the roster, so nobody is punished for a
#     disconnected friend.
# -----------------------------------------------------------------------------

const MEANINGFUL: Array[String] = [
	"start", "brake", "grip", "cargo", "recover", "hook", "winch", "console",
	"winch_brake", "winch_release", "guide", "bracket", "align", "lock", "rescue",
]
const CORE: Array[String] = [
	"start", "brake", "cargo", "hook", "winch", "guide", "bracket", "lock",
]

var stage: Node3D
var records: Dictionary = {}       # slot -> {kinds: Dictionary, first: float, count: int}
var completed_verdict: Dictionary = {}

func setup(owner_stage: Node3D) -> void:
	stage = owner_stage

func is_host() -> bool:
	return multiplayer.is_server()

func record(slot: int, kind: String) -> void:
	if slot <= 0 or not is_host():
		return
	# `winch_interact` is the single-E handshake (hook / console / pin socket).
	# It is meaningful on its own only when it is not the release/pin shortcuts;
	# map it to "console" so the record stays readable.
	var key: String = kind
	if key == "winch_interact":
		key = "console"
	if not MEANINGFUL.has(key):
		return
	if not records.has(slot):
		records[slot] = {"kinds": {}, "first": float(stage.get("clock")), "count": 0}
	var entry: Dictionary = records[slot] as Dictionary
	var kinds: Dictionary = entry["kinds"] as Dictionary
	kinds[key] = int(kinds.get(key, 0)) + 1
	entry["count"] = int(entry["count"]) + 1

func kinds_for(slot: int) -> Array:
	if not records.has(slot):
		return []
	return ((records[slot] as Dictionary)["kinds"] as Dictionary).keys()

func credited(slot: int) -> bool:
	if not records.has(slot):
		return false
	var kinds: Array = kinds_for(slot)
	if kinds.size() < 2:
		return false
	var core: bool = false
	for kind: String in kinds:
		if CORE.has(kind):
			core = true
			break
	return core

func summary() -> Dictionary:
	var credited_slots: Array = []
	var watched_slots: Array = []
	var connected: Array = []
	if stage != null:
		connected = (stage.get("coop").call("connected_slots") as Array) if stage.get("coop") != null else [1]
	for slot: int in connected:
		if credited(slot):
			credited_slots.append(slot)
		else:
			watched_slots.append(slot)
	return {"credited": credited_slots, "watched": watched_slots, "connected": connected,
		"records": records.duplicate(), "complete": credited_slots.size() == connected.size()}

func verdict_text() -> String:
	var data: Dictionary = summary()
	var credited: Array = data["credited"] as Array
	var watched: Array = data["watched"] as Array
	if credited.is_empty():
		return "尚未记录有效参与。"
	var text: String = "有效参与：%s" % _slots_text(credited)
	if not watched.is_empty():
		text += " · 未产生有效操作：%s" % _slots_text(watched)
	return text

func _slots_text(list: Array) -> String:
	var parts: Array[String] = []
	for slot: int in list:
		parts.append("玩家 %d" % slot)
	return "、".join(parts)

func snapshot() -> Dictionary:
	return {"records": records.duplicate(), "credited": summary()["credited"],
		"watched": summary()["watched"]}

func apply_net(data: Dictionary) -> void:
	records = data.get("records", {}) as Dictionary

func reset() -> void:
	records.clear()
	completed_verdict.clear()
