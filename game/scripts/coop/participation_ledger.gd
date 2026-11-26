class_name ParticipationLedger
extends RefCounted

## Server-authoritative record of what each player actually did.
##
## This is NOT a score. Every credit kind below is issued only by the machine
## that owns the mechanic, after that machine has verified a real world-state
## change (cart moved and the core moment changed, stabiliser latch closed,
## brake pressure actually built, pin re-seated, carriage really advanced,
## rescue really lifted a body). A player becomes "ready" for a phase when they
## have at least one verified credit in that phase.
##
## The ledger is also used to keep an idle player from being carried: a player
## who never touches a machine never gets phase credits, so the finale will not
## mark them as having completed the co-op run. The HUD/in-world duty board
## tells them exactly which physical station still needs them.

const PHASE_A := "A"  # core stabilisation
const PHASE_B := "B"  # accident response / recovery
const PHASE_C := "C"  # final isolation + data
# Act 4 (Resonance 04) uses its own participation phase. The exit gate of Act 4
# checks these kinds directly (each active participant needs at least one), so
# they never enter the Act 5 A/B/C readiness loop.
const PHASE_04 := "04"

const STATUS_ACTIVE := "active"
const STATUS_AWAY := "away"
const STATUS_SPECTATOR := "spectator"
const STATUS_DISCONNECTED := "disconnected"

## kind -> {phase, label, world, min_weight}
## `min_weight` is the minimum measured effect (metres, pressure units, seconds)
## the machine must report before the credit counts at all.
const KINDS := {
	"stabilizer_lock": {
		"phase": PHASE_A,
		"label": "展开并锁定机械稳定支腿",
		"world": "稳定支腿",
		"min_weight": 0.9,
	},
	"counterweight_effect": {
		"phase": PHASE_A,
		"label": "用配重实际减小核心偏心力矩",
		"world": "配重控制台",
		"min_weight": 0.03,
	},
	"brake_charge": {
		"phase": PHASE_A,
		"label": "给应急制动蓄压",
		"world": "应急制动",
		"min_weight": 0.45,
	},
	"catwalk_pin_seat": {
		"phase": PHASE_A,
		"label": "复位维修栈桥安全销",
		"world": "维修栈桥",
		"min_weight": 0.9,
	},
	"surge_response": {
		"phase": PHASE_B,
		"label": "在共振反冲预兆中采取实际防护动作",
		"world": "栈桥抓扶 / 制动 / 支腿",
		"min_weight": 0.5,
	},
	"brace_hold": {
		"phase": PHASE_B,
		"label": "冲击中抓住栏杆并撑住",
		"world": "栈桥抓扶横杆",
		"min_weight": 1.0,
	},
	"pin_reseat": {
		"phase": PHASE_B,
		"label": "在冲击后重新固定松脱的机械保险",
		"world": "栈桥安全销",
		"min_weight": 0.9,
	},
	"rescue": {
		"phase": PHASE_B,
		"label": "用救援卷扬机把队友拉回栈桥",
		"world": "救援卷扬机",
		"min_weight": 1.0,
	},
	"self_rescue": {
		"phase": PHASE_B,
		"label": "沿备用爬梯自救返回",
		"world": "维修爬梯",
		"min_weight": 1.0,
	},
	"lock_assist": {
		"phase": PHASE_C,
		"label": "参与液压锁爪的锁止准备",
		"world": "锁爪控制台 / 稳定支腿",
		"min_weight": 1.0,
	},
	"damper_latch": {
		"phase": PHASE_C,
		"label": "锁定采掘回路阻尼器",
		"world": "回路阻尼器",
		"min_weight": 0.85,
	},
	"damper_hold": {
		"phase": PHASE_C,
		"label": "持续压住回路阻尼器",
		"world": "回路阻尼器",
		"min_weight": 1.5,
	},
	"isolation_pin": {
		"phase": PHASE_C,
		"label": "拔出联轴器安全销",
		"world": "采掘联轴器",
		"min_weight": 1.0,
	},
	"carriage_push": {
		"phase": PHASE_C,
		"label": "推动滑架分离采掘联轴器",
		"world": "采掘联轴器",
		"min_weight": 0.25,
	},
	"data_take": {
		"phase": PHASE_C,
		"label": "取出深空航行数据",
		"world": "导航数据基座",
		"min_weight": 1.0,
	},
	# --- Act 4 (Resonance 04) participation kinds --------------------------
	# Issued by the Act 4 game (host side) when a real mechanic happens, to the
	# player who actually performed it. `phase` is the Act-4 phase so these
	# never collide with Act 5's A/B/C gate. Act 4's own exit gate requires
	# every active participant to hold at least one of these kinds.
	"act4_hammer_strike": {
		"phase": PHASE_04,
		"label": "拉响撞钟引发共振",
		"world": "共振撞钟",
		"min_weight": 0.56,
	},
	"act4_crystal_carry": {
		"phase": PHASE_04,
		"label": "搬运 / 安放共振晶体",
		"world": "便携晶体 / 支架",
		"min_weight": 1.0,
	},
	"act4_platform_drive": {
		"phase": PHASE_04,
		"label": "驾驶悬吊货运平台",
		"world": "货运平台",
		"min_weight": 1.0,
	},
	"act4_brake": {
		"phase": PHASE_04,
		"label": "拉下货运平台安全制动",
		"world": "货运平台制动",
		"min_weight": 1.0,
	},
	"act4_grab": {
		"phase": PHASE_04,
		"label": "抓住货运平台扶手",
		"world": "货运平台扶手",
		"min_weight": 1.0,
	},
	"act4_rescue": {
		"phase": PHASE_04,
		"label": "放下救援绞盘协助队友",
		"world": "救援绞盘",
		"min_weight": 1.0,
	},
}

const PHASES: Array[String] = [PHASE_A, PHASE_B, PHASE_C]
const PHASE_TITLES := {
	PHASE_A: "阶段 A · 核心稳定",
	PHASE_B: "阶段 B · 事故处理",
	PHASE_C: "阶段 C · 最终隔离",
}

var players: Dictionary = {}   # pid:int -> record:Dictionary
var log_lines: Array[String] = []
var clock: float = 0.0


func _init() -> void:
	pass


func add_player(pid: int, display_name: String, local: bool = false) -> Dictionary:
	if players.has(pid):
		return players[pid] as Dictionary
	var record: Dictionary = {
		"id": pid,
		"name": display_name,
		"local": local,
		"status": STATUS_ACTIVE,
		"joined": clock,
		"last_action": -1.0,
		"credits": {},        # kind -> {count, first, last, effect}
		"phases": {PHASE_A: 0, PHASE_B: 0, PHASE_C: 0},
		"spectator_since": -1.0,
	}
	players[pid] = record
	return record


func player_ids() -> Array[int]:
	var ids: Array[int] = []
	for key in players.keys():
		ids.append(int(key))
	ids.sort()
	return ids


func active_ids() -> Array[int]:
	var ids: Array[int] = []
	for pid in player_ids():
		if status_of(pid) == STATUS_ACTIVE:
			ids.append(pid)
	return ids


func get_record(pid: int) -> Dictionary:
	if not players.has(pid):
		return {}
	return players[pid] as Dictionary


func display_name(pid: int) -> String:
	var record: Dictionary = get_record(pid)
	if record.is_empty():
		return "玩家%d" % pid
	return str(record.get("name", "玩家%d" % pid))


func status_of(pid: int) -> String:
	var record: Dictionary = get_record(pid)
	if record.is_empty():
		return STATUS_DISCONNECTED
	return str(record.get("status", STATUS_ACTIVE))


func set_status(pid: int, status: String) -> void:
	var record: Dictionary = get_record(pid)
	if record.is_empty():
		return
	if str(record["status"]) == status:
		return
	record["status"] = status
	record["spectator_since"] = clock if status == STATUS_SPECTATOR else -1.0
	log_lines.append("[%7.2f] %s -> %s" % [clock, display_name(pid), status])


func tick(delta: float) -> void:
	clock += delta


## Issue a verified credit. `effect` is the measured world change; it must clear
## the kind's minimum or nothing is recorded. Returns true when it counted.
func credit(pid: int, kind: String, effect: float, detail: String = "") -> bool:
	if not KINDS.has(kind):
		push_warning("ParticipationLedger: unknown credit kind %s" % kind)
		return false
	if status_of(pid) != STATUS_ACTIVE:
		return false
	var spec: Dictionary = KINDS[kind] as Dictionary
	var min_weight: float = float(spec.get("min_weight", 0.0))
	if effect < min_weight:
		return false
	var record: Dictionary = get_record(pid)
	if record.is_empty():
		return false
	var credits: Dictionary = record["credits"] as Dictionary
	var phase: String = str(spec["phase"])
	var now: float = clock
	if credits.has(kind):
		var entry: Dictionary = credits[kind] as Dictionary
		# Same credit kind is recorded once per player; repeat actions refresh
		# the timestamp but never inflate the phase count.
		entry["count"] = int(entry["count"]) + 1
		entry["last"] = now
		entry["effect"] = maxf(float(entry["effect"]), effect)
		entry["detail"] = detail
		record["last_action"] = now
		return false
	credits[kind] = {
		"count": 1,
		"first": now,
		"last": now,
		"effect": effect,
		"detail": detail,
		"phase": phase,
	}
	var phases: Dictionary = record["phases"] as Dictionary
	phases[phase] = int(phases.get(phase, 0)) + 1
	record["last_action"] = now
	log_lines.append("[%7.2f] %s +%s (%.2f) %s" % [now, display_name(pid), kind, effect, detail])
	if log_lines.size() > 240:
		log_lines.pop_front()
	return true


func has_credit(pid: int, kind: String) -> bool:
	var record: Dictionary = get_record(pid)
	if record.is_empty():
		return false
	var credits: Dictionary = record["credits"] as Dictionary
	if credits.has(kind):
		return true
	# Client mirror: the host sends a kind list instead of the full records.
	var kinds: Array = record.get("kinds", [])
	return kinds.has(kind)


func phase_count(pid: int, phase: String) -> int:
	var record: Dictionary = get_record(pid)
	if record.is_empty():
		return 0
	var phases: Dictionary = record["phases"] as Dictionary
	return int(phases.get(phase, 0))


func ready_for_phase(pid: int, phase: String) -> bool:
	return phase_count(pid, phase) > 0


func is_ready(pid: int) -> bool:
	for phase in PHASES:
		if not ready_for_phase(pid, phase):
			return false
	return true


func missing_kinds(pid: int, phase: String) -> Array[String]:
	var out: Array[String] = []
	for kind in KINDS.keys():
		var spec: Dictionary = KINDS[kind] as Dictionary
		if str(spec["phase"]) != phase:
			continue
		if has_credit(pid, str(kind)):
			continue
		out.append(str(kind))
	return out


func missing_summary(pid: int) -> Array[String]:
	var out: Array[String] = []
	for phase in PHASES:
		if ready_for_phase(pid, phase):
			continue
		var labels: Array[String] = []
		for kind in missing_kinds(pid, phase):
			var spec: Dictionary = KINDS[kind] as Dictionary
			labels.append(str(spec["label"]))
		out.append("%s：%s" % [PHASE_TITLES[phase], " 或 ".join(labels)])
	return out


func all_active_ready() -> bool:
	var ids: Array[int] = active_ids()
	if ids.is_empty():
		return false
	for pid in ids:
		if not is_ready(pid):
			return false
	return true


func unready_active() -> Array[int]:
	var out: Array[int] = []
	for pid in active_ids():
		if not is_ready(pid):
			out.append(pid)
	return out


func snapshot() -> Dictionary:
	var out: Dictionary = {}
	for pid in player_ids():
		out[pid] = _record_snapshot(pid)
	return out


func _record_snapshot(pid: int) -> Dictionary:
	var record: Dictionary = get_record(pid)
	if record.is_empty():
		return {}
	var kinds: Array = []
	for kind in (record["credits"] as Dictionary).keys():
		kinds.append(str(kind))
	return {
		"id": pid,
		"name": str(record["name"]),
		"status": str(record["status"]),
		"phases": (record["phases"] as Dictionary).duplicate(true),
		"kinds": kinds,
		"ready": is_ready(pid),
		"last_action": float(record["last_action"]),
	}


func apply_snapshot(data: Dictionary) -> void:
	# Client-side mirror only. The host is the only writer.
	for key in data.keys():
		var pid: int = int(key)
		var src: Dictionary = data[key] as Dictionary
		if not players.has(pid):
			add_player(pid, str(src.get("name", "玩家%d" % pid)))
		var record: Dictionary = get_record(pid)
		record["name"] = str(src.get("name", record["name"]))
		record["status"] = str(src.get("status", record["status"]))
		record["phases"] = (src.get("phases", {}) as Dictionary).duplicate(true)
		record["ready"] = bool(src.get("ready", false))
		record["kinds"] = (src.get("kinds", []) as Array).duplicate()
		record["last_action"] = float(src.get("last_action", -1.0))
