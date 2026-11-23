class_name CoopSession
extends Node

## Host-authoritative co-op session state for Resonance 05 V2.
##
## The same class runs the solo game (one local participant, authority on) and
## the two-instance ENet slice (host authority + client mirror). It owns:
##   * the participant list and the ParticipationLedger,
##   * per-machine control claims (one operator per machine, released on
##     disconnect / timeout / explicit release),
##   * the remote axis stream used by the host to drive a machine that a client
##     claimed,
##   * the completion gate: the finale only completes for players who actually
##     took part in phases A / B / C.

signal participants_changed()
signal claim_changed(machine_id: String, pid: int)
signal credit_awarded(pid: int, kind: String, phase: String)
signal local_claim_granted(machine_id: String)
signal local_claim_denied(machine_id: String, reason: String)
signal status_changed(pid: int, status: String)

const MAX_PLAYERS := 4
const CLAIM_IDLE_TIMEOUT := 10.0
const AWAY_AFTER_SECONDS := 150.0
const MACHINE_IDS: Array[String] = [
	"cart_left", "cart_right", "stabilizer_w", "stabilizer_e",
	"brake", "brake_assist", "damper", "isolation_carriage",
	"catwalk_lock", "winch",
]

var is_host: bool = true
var local_pid: int = 1
var ledger: ParticipationLedger = ParticipationLedger.new()
var claims: Dictionary = {}        # machine_id -> {pid, t, axis}
var remote_axes: Dictionary = {}   # machine_id -> float (host side)
var connected_peers: Array[int] = []
var net_online: bool = false
var clock: float = 0.0
# Which machine the local body is currently operating. The client pumps this to
# the host so a remote operator's W/S still drives the machine.
var local_operating_machine: String = ""
var local_player_ref: PlayerController = null
var grab_states: Dictionary = {}       # pid -> bool
var player_states: Dictionary = {}     # pid -> last streamed state (host mirror)
var rescue_hauls: Dictionary = {}      # pid -> {start, progress}
var _pending_claims: Dictionary = {}  # machine_id -> true (client awaiting grant)


func setup(p_local_pid: int = 1, p_is_host: bool = true) -> void:
	local_pid = p_local_pid
	is_host = p_is_host


func _ready() -> void:
	name = "CoopSession"
	set_process(true)


func _process(delta: float) -> void:
	clock += delta
	ledger.tick(delta)
	if local_player_ref != null and is_instance_valid(local_player_ref):
		grab_states[local_pid] = local_player_ref.grabbing
	if not is_host:
		return
	# Idle claims expire so a player who walks away (or an old peer id) can
	# never hold a machine forever. The machine itself keeps its last state.
	var expired: Array[String] = []
	for machine_id in claims.keys():
		var entry: Dictionary = claims[machine_id] as Dictionary
		if clock - float(entry.get("t", 0.0)) > CLAIM_IDLE_TIMEOUT:
			expired.append(str(machine_id))
	for machine_id in expired:
		var owner: int = claim_owner(machine_id)
		release_claim(machine_id, owner)
	# Status hints: a player who has not touched anything for a long while is
	# reported as "away" in the ledger so the HUD can ask the team about them.
	# This never removes them from the participant list and never grants credit.
	for pid in ledger.player_ids():
		if ledger.status_of(pid) != ParticipationLedger.STATUS_ACTIVE:
			continue
		var record: Dictionary = ledger.get_record(pid)
		var last: float = float(record.get("last_action", -1.0))
		if last > 0.0 and clock - last > AWAY_AFTER_SECONDS:
			pass  # shown in HUD; status change is an explicit team decision


func is_authority() -> bool:
	return is_host


func is_online() -> bool:
	return net_online


func add_player(pid: int, display_name: String, local: bool = false) -> void:
	if not is_host:
		return
	if ledger.players.size() >= MAX_PLAYERS and not ledger.players.has(pid):
		return
	ledger.add_player(pid, display_name, local)
	participants_changed.emit()


func remove_player(pid: int, reason: String = "disconnect") -> void:
	if not is_host:
		return
	var record: Dictionary = ledger.get_record(pid)
	if record.is_empty():
		return
	release_all_for(pid, reason)
	# A departed peer must not keep streaming stale state: `grab_states` is read
	# by current_grab_pids() (surge director) and `player_states` is mirrored
	# into every Act05 snapshot, so leaving either behind both grows without
	# bound across joins and reports a dead pid as an active grabber.
	grab_states.erase(pid)
	player_states.erase(pid)
	rescue_hauls.erase(pid)
	ledger.set_status(pid, ParticipationLedger.STATUS_DISCONNECTED)
	# Report the status that was actually stored. Emitting SPECTATOR here made
	# listeners see a disconnected peer as "still watching".
	status_changed.emit(pid, ParticipationLedger.STATUS_DISCONNECTED)
	participants_changed.emit()


func set_status(pid: int, status: String) -> void:
	if not is_host:
		return
	ledger.set_status(pid, status)
	if status != ParticipationLedger.STATUS_ACTIVE:
		release_all_for(pid, status)
	status_changed.emit(pid, status)
	participants_changed.emit()


func status_of(pid: int) -> String:
	return ledger.status_of(pid)


func player_count() -> int:
	return ledger.players.size()


func active_ids() -> Array[int]:
	return ledger.active_ids()


func credit(pid: int, kind: String, effect: float, detail: String = "") -> bool:
	if not is_host:
		return false
	var before_phase: String = ""
	if ParticipationLedger.KINDS.has(kind):
		before_phase = str((ParticipationLedger.KINDS[kind] as Dictionary)["phase"])
	var counted: bool = ledger.credit(pid, kind, effect, detail)
	if counted:
		credit_awarded.emit(pid, kind, before_phase)
		participants_changed.emit()
	return counted


# ---------------------------------------------------------------------------
# Machine control claims
# ---------------------------------------------------------------------------

func claim_owner(machine_id: String) -> int:
	if not claims.has(machine_id):
		return 0
	var entry: Dictionary = claims[machine_id] as Dictionary
	return int(entry.get("pid", 0))


func is_claimed_by_other(machine_id: String, pid: int) -> bool:
	var owner: int = claim_owner(machine_id)
	return owner != 0 and owner != pid


func is_known_machine(machine_id: String) -> bool:
	return MACHINE_IDS.has(machine_id)


func try_claim(machine_id: String, pid: int) -> Dictionary:
	if not is_host:
		return {"ok": false, "reason": "not_authority"}
	if pid <= 0 or not is_known_machine(machine_id):
		return {"ok": false, "reason": "unknown_machine"}
	if ledger.status_of(pid) != ParticipationLedger.STATUS_ACTIVE:
		return {"ok": false, "reason": "当前状态无法操作机械"}
	var owner: int = claim_owner(machine_id)
	if owner != 0 and owner != pid:
		return {"ok": false, "reason": "%s 正在操作" % ledger.display_name(owner)}
	claims[machine_id] = {"pid": pid, "t": clock, "axis": 0.0}
	claim_changed.emit(machine_id, pid)
	return {"ok": true, "reason": ""}


func refresh_claim(machine_id: String, pid: int) -> void:
	if not claims.has(machine_id):
		return
	var entry: Dictionary = claims[machine_id] as Dictionary
	if int(entry.get("pid", 0)) == pid:
		entry["t"] = clock


func release_claim(machine_id: String, pid: int) -> void:
	if not claims.has(machine_id):
		return
	var entry: Dictionary = claims[machine_id] as Dictionary
	if int(entry.get("pid", 0)) != pid and pid != 0:
		return
	claims.erase(machine_id)
	remote_axes.erase(machine_id)
	if local_operating_machine == machine_id:
		local_operating_machine = ""
	claim_changed.emit(machine_id, 0)


func release_all_for(pid: int, _reason: String = "") -> void:
	var owned: Array[String] = []
	for machine_id in claims.keys():
		if claim_owner(str(machine_id)) == pid:
			owned.append(str(machine_id))
	for machine_id in owned:
		release_claim(machine_id, pid)


func set_axis(machine_id: String, pid: int, axis: float) -> void:
	if not is_host:
		return
	if claim_owner(machine_id) != pid:
		return
	var entry: Dictionary = claims[machine_id] as Dictionary
	entry["axis"] = clampf(axis, -1.0, 1.0)
	entry["t"] = clock
	remote_axes[machine_id] = clampf(axis, -1.0, 1.0)


## Axis for a machine. On the host, a locally driven machine reads the local
## keyboard; a remote-owned machine reads the streamed axis.
func axis_for(machine_id: String, local_axis: float) -> float:
	var owner: int = claim_owner(machine_id)
	if owner == 0:
		return local_axis
	if owner == local_pid:
		return local_axis
	return float(remote_axes.get(machine_id, 0.0))


func claimed_by_local(machine_id: String) -> bool:
	return claim_owner(machine_id) == local_pid


func set_grab_state(pid: int, value: bool) -> void:
	if value:
		grab_states[pid] = true
	else:
		grab_states.erase(pid)


func current_grab_pids() -> Array[int]:
	var out: Array[int] = []
	for key in grab_states.keys():
		if bool(grab_states[key]):
			out.append(int(key))
	return out


func set_player_state(pid: int, state: Dictionary) -> void:
	player_states[pid] = state
	set_grab_state(pid, bool(state.get("grab", false)))


func player_state(pid: int) -> Dictionary:
	return player_states.get(pid, {}) as Dictionary


func note_pending_claim(machine_id: String) -> void:
	_pending_claims[machine_id] = true


func clear_pending_claim(machine_id: String) -> void:
	_pending_claims.erase(machine_id)


func is_pending_claim(machine_id: String) -> bool:
	return _pending_claims.has(machine_id)


## Client side: the host answered a claim request.
func clear_operating_machine() -> void:
	local_operating_machine = ""


func grant_local_claim(machine_id: String, owner: int = -1) -> void:
	_pending_claims.erase(machine_id)
	var who: int = local_pid if owner < 0 else owner
	if who != local_pid:
		return
	local_claim_granted.emit(machine_id)


func deny_local_claim(machine_id: String, reason: String) -> void:
	_pending_claims.erase(machine_id)
	local_claim_denied.emit(machine_id, reason)


func clear_pending_claims() -> void:
	_pending_claims.clear()


# ---------------------------------------------------------------------------
# Completion gate
# ---------------------------------------------------------------------------

func can_finish() -> bool:
	if not is_host:
		return false
	return ledger.all_active_ready()


func completion_report() -> Dictionary:
	var ready: Array = []
	var missing: Array = []
	for pid in ledger.active_ids():
		var entry: Dictionary = {
			"id": pid,
			"name": ledger.display_name(pid),
			"ready": ledger.is_ready(pid),
			"missing": ledger.missing_summary(pid),
			"phases": (ledger.get_record(pid).get("phases", {}) as Dictionary).duplicate(true),
		}
		if ledger.is_ready(pid):
			ready.append(entry)
		else:
			missing.append(entry)
	return {
		"can_finish": ledger.all_active_ready(),
		"ready": ready,
		"missing": missing,
		"spectators": _status_entries(ParticipationLedger.STATUS_SPECTATOR),
		"away": _status_entries(ParticipationLedger.STATUS_AWAY),
		"disconnected": _status_entries(ParticipationLedger.STATUS_DISCONNECTED),
	}


func _status_entries(status: String) -> Array:
	var out: Array = []
	for pid in ledger.player_ids():
		if ledger.status_of(pid) != status:
			continue
		out.append({"id": pid, "name": ledger.display_name(pid), "status": status})
	return out


func gate_text() -> String:
	var missing: Array[int] = ledger.unready_active()
	if missing.is_empty():
		return ""
	var parts: Array[String] = []
	for pid in missing:
		var first: String = ""
		var summary: Array[String] = ledger.missing_summary(pid)
		if not summary.is_empty():
			first = summary[0]
		parts.append("%s 还缺：%s" % [ledger.display_name(pid), first])
	return "  |  ".join(parts)


func ledger_snapshot() -> Dictionary:
	return ledger.snapshot()
