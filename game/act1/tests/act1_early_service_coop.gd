extends Node

## Two-process Act 01 "advance maintenance" co-op probe (LIS-GAMEPLAY-001).
##
## Launched by Act1App with `--early-coop=<host|client>`; lives under /root so it
## survives the Act01 -> handoff transition.
##
## What it proves with two REAL Godot processes sharing one session:
##   * a client can pull the rotor lock and engage the coupling while
##     `power_ready` is still false (advance maintenance is networked);
##   * the host's authoritative flags reflect that work (state channel), and the
##     credit lands on the acting pid, not the host;
##   * an unpowered `start_fan` request is refused on the host, so no client can
##     spin a dead fan;
##   * once power is restored the prepared machine starts — across the network;
##   * early vent credit does not shortcut the two-phase participation gate.
##
## Usage (two processes, host first):
##   godot --headless --path game --port 9871 --host \
##     res://act1/act01.tscn -- --early-coop=host  --out=<dir>
##   godot --headless --path game --port 9871 --client \
##     res://act1/act01.tscn -- --early-coop=client --out=<dir>

var stage: Node3D
var player: Node
var role := ""
var out_dir := ""
var failures: Array[String] = []
var lines: Array[String] = []
var checks := 0

const ROTOR_LOCK_APPROACH := Vector3(7.70, 0.05, -22.30)
const COUPLING_APPROACH := Vector3(8.10, 0.05, -28.15)
const START_FAN_APPROACH := Vector3(-7.80, 0.05, -23.00)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--early-coop="):
			role = s.substr("--early-coop=".length())
		elif s.begins_with("--out="):
			out_dir = s.substr("--out=".length())
	call_deferred("_run")


func log_line(text: String) -> void:
	print("EARLYCOOP[%s] %s" % [role, text])
	lines.append(text)


func check(ok: bool, text: String) -> void:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)


func _flags() -> Dictionary:
	return stage.get("flags") as Dictionary


func _flag(key: String) -> bool:
	return bool(_flags().get(key, false))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_flag(key: String, seconds: float, want := true) -> bool:
	var waited := 0.0
	while waited < seconds:
		if _flag(key) == want:
			return true
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	return _flag(key) == want


func _wait_credit(pid: int, kind: String, seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		var rec: Dictionary = (stage.get("credits") as Dictionary).get(pid, {})
		if (rec.get("kinds", {}) as Dictionary).has(kind):
			return true
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	return false


func _warp(pos: Vector3) -> void:
	player.call("teleport", pos, 0.0, 0.0)
	await get_tree().create_timer(0.2).timeout


func _press(id: String) -> void:
	stage.call("request_interaction", id, player, "press")
	await get_tree().create_timer(0.6).timeout


func _toast_text() -> String:
	var hud: Node = stage.get("hud") as Node
	if hud == null:
		return ""
	var toast: Variant = hud.get("_toast")
	return (toast as Label).text if toast is Label else ""


func _hint_text() -> String:
	var hud: Node = stage.get("hud") as Node
	if hud == null:
		return ""
	var hint: Variant = hud.get("_vent_hint")
	return (hint as Label).text if hint is Label else ""


func _prompt(id: String) -> String:
	var point: Object = (stage.get("interactables") as Dictionary).get(id) as Object
	if point == null:
		return ""
	return str(point.call("get_prompt", player))


## Cross-process handshake: the client writes a marker once it has really tried
## the unpowered start, and the host only restores power afterwards. Without it
## the host could restore power first and the "unpowered start is refused" check
## would race the legitimate powered start.
func _marker_path() -> String:
	return out_dir.path_join("early_coop_client_start_attempted")


func _write_marker() -> void:
	var f := FileAccess.open(_marker_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(str(Time.get_ticks_msec()))
		f.close()


func _wait_marker(seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		if FileAccess.file_exists(_marker_path()):
			return true
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	return FileAccess.file_exists(_marker_path())


func _run() -> void:
	while stage == null:
		await get_tree().process_frame
	await _wait(1.6)
	player = stage.get("local_player") as Node
	log_line("start mode=%s pid=%d" % [str(stage.get("net").get("mode")), int(stage.get("local_pid"))])
	if role == "host":
		await _run_host()
	else:
		await _run_client()
	_finish()


func _run_host() -> void:
	var connected := await _wait_peers(45.0)
	check(connected, "host sees the client join the Act01 session")
	var mine := int(stage.get("local_pid"))
	check(mine == 1, "host owns pid 1 (pid=%d)" % mine)
	# The client performs the whole advance-maintenance pass; the host only reads
	# its own authoritative state, exactly like the human host would see it.
	check(await _wait_flag("rotor_lock_released", 90.0),
		"host sees the client's early rotor-lock removal (state channel)")
	check(not _flag("power_ready"), "power is still off while the rotor lock is out")
	check(await _wait_flag("coupling_engaged", 90.0),
		"host sees the client's early coupling engagement (state channel)")
	check(await _wait_credit(2, "fan_lock", 20.0), "rotor-lock credit is booked on pid 2")
	check(await _wait_credit(2, "fan_coupling", 20.0), "coupling credit is booked on pid 2")
	check(not _flag("fan_started"), "the fan never starts while power is off")
	var pid2_phases: Dictionary = ((stage.get("credits") as Dictionary).get(2, {}) as Dictionary).get("phases", {})
	log_line("HOST pid2 phases=%s" % str(pid2_phases.keys()))
	check(pid2_phases.has("vent"), "early maintenance books the vent phase for pid 2")
	check(int(stage.call("get_phase_credit", 2)) == pid2_phases.size(),
		"early maintenance does not double-count the vent phase")
	check(not bool(stage.call("can_participate", 2)),
		"early vent credit alone does not satisfy the two-phase participation gate")
	# The client reaches the start handle before power comes back; only then may
	# the host restore it, so "unpowered start refused" is a real observation.
	check(await _wait_marker(90.0), "client reached the unpowered start attempt")
	check(not _flag("fan_started"), "host refused the client's unpowered start")
	log_line("HOST toast after refused start: %s" % _toast_text())
	# Restore power with the authored authority path: the cart/winch/clamp chain
	# is covered end-to-end by act1_solo_full_run.gd, so stand it in here.
	stage.call("set_flag", "power_ready", true)
	check(await _wait_flag("fan_started", 60.0),
		"the prepared machine starts once power is restored (host authority)")
	var vent: Node = (stage.get("builder") as Object).get("vent") as Node
	await _wait(1.0)
	check(bool(vent.get("running")) and float(vent.get("speed")) > 0.05,
		"host ventilation machine is actually spinning")
	check(await _wait_credit(2, "fan_start", 20.0), "fan-start credit is booked on the acting pid 2")


func _run_client() -> void:
	var connected := await _wait_peers(45.0)
	check(connected, "client joined as pid 2")
	var mine := int(stage.get("local_pid"))
	check(mine == 2, "client owns pid 2 (pid=%d)" % mine)
	check(not _flag("power_ready"), "client mirrors an unpowered control circuit")
	# 1. advance maintenance through the real request -> host validate path
	await _warp(ROTOR_LOCK_APPROACH)
	check(_prompt("rotor_lock").find("提前检修") >= 0,
		"client prompt announces advance maintenance before the press")
	await _press("rotor_lock")
	check(await _wait_flag("rotor_lock_released", 30.0),
		"client pulled the rotor lock while power is off (host accepted)")
	check(not _flag("power_ready"), "pulling the lock did not fake power on the client")
	await _warp(COUPLING_APPROACH)
	await _press("coupling")
	check(await _wait_flag("coupling_engaged", 30.0),
		"client engaged the coupling while power is off (host accepted)")
	# 2. an unpowered start must be refused by the host authority
	await _warp(START_FAN_APPROACH)
	check(_prompt("start_fan").find("未得电") >= 0,
		"client start handle prompt names the missing control power")
	await _press("start_fan")
	await _wait(1.2)
	_write_marker()
	check(not _flag("fan_started"), "client cannot start the unpowered fan")
	# A client's own toast is overwritten by the join/network notices, so the
	# durable, mirrored evidence is the HUD ventilation hint. It is fed by
	# `flags` on both sides, i.e. by the synced state, not by a local guess.
	stage.call("_update_hud", 0.1)
	await _wait(0.2)
	var hint := _hint_text()
	log_line("HUD_HINT_CLIENT " + hint)
	check(hint.find("检修就绪") >= 0 and hint.find("未得电") >= 0,
		"client HUD explains serviced-but-unpowered from the synced state")
	# 3. the host is the authority that restores power; the client waits for it
	check(await _wait_flag("power_ready", 90.0), "client sees auxiliary power restored")
	await _press("start_fan")
	check(await _wait_flag("fan_started", 30.0), "client sees the prepared fan start after power")
	var vent: Node = (stage.get("builder") as Object).get("vent") as Node
	await _wait(1.0)
	check(bool(vent.get("running")), "client mirror shows a running ventilation machine")


func _wait_peers(seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		var net: Object = stage.get("net")
		if net != null and int(net.call("peer_count")) > 1:
			return true
		await get_tree().create_timer(0.4).timeout
		waited += 0.4
	return false


func _finish() -> void:
	var ok := failures.is_empty()
	if out_dir != "":
		var report := {
			"probe": "act1_early_service_coop.gd",
			"role": role,
			"passed": ok,
			"checks": checks,
			"failures": failures,
			"flags": (stage.get("flags") as Dictionary).duplicate(true) if stage != null else {},
			"log": lines,
		}
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("early_coop_%s.json" % role), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	log_line("RESULT checks=%d failures=%d passed=%s" % [checks, failures.size(), str(ok)])
	print("EARLY_COOP_%s %s checks=%d" % [role.to_upper(), "OK" if ok else "FAIL", checks])
	await _wait(1.0)
	get_tree().quit(0 if ok else 1)
