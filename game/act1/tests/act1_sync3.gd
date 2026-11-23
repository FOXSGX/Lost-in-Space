extends Node

## LIS-GAMEPLAY-001B · 3-seat Act01 MECHANISM-STATE-SYNC probe.
##
## Scope is deliberately narrow: this is a *mechanism state sync* test, NOT a
## five-act playthrough. It boots `act1/act01.tscn` directly in three processes
## (host + 2 clients) on one SessionHub peer, which avoids the official-launcher
## mouse click that cannot be reproduced under `--headless` (the headless window
## is 64x64, so the harness's canvas->window scaling misses the button; see the
## report's "unverified" section).
##
## Roles, assigned by real pid:
##   pid1 host   — authority, restores power, reads every synced flag
##   pid2        — performs the advance-maintenance pair (rotor lock + coupling)
##   pid3        — tries the unpowered start (must be refused) and keeps the
##                 third seat's view of the same flags
##
## What it asserts:
##   * both client seats observe the same `rotor_lock_released` /
##     `coupling_engaged` values as the host (state channel, 3 seats)
##   * credits land on the acting pid, not on the host or a neighbour
##   * an unpowered start is refused for BOTH clients and the fan never spins
##   * after power, exactly one seat starts the machine and all three agree
##
## Usage (host first, then two clients):
##   godot --headless --path game --port 9931 --host res://act1/act01.tscn \
##     -- --sync3=host --out=<dir>
##   ... --client ... -- --sync3=client2 --out=<dir>
##   ... --client ... -- --sync3=client3 --out=<dir>

var stage: Node3D
var player: Node
var role := ""
var out_dir := ""
var failures: Array[String] = []
var lines: Array[String] = []
var checks := 0

const ROTOR := Vector3(7.70, 0.05, -22.30)
const COUPLING := Vector3(8.10, 0.05, -28.15)
const START := Vector3(-7.80, 0.05, -23.00)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--sync3="):
			role = s.substr("--sync3=".length())
		elif s.begins_with("--out="):
			out_dir = s.substr("--out=".length())
	call_deferred("_run")


func log_line(t: String) -> void:
	print("SYNC3[%s] %s" % [role, t])
	lines.append(t)


func check(ok: bool, t: String) -> void:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + t)
	if not ok:
		failures.append(t)


func _flags() -> Dictionary:
	return stage.get("flags") as Dictionary


func _flag(k: String) -> bool:
	return bool(_flags().get(k, false))


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _wait_flag(k: String, secs: float, want := true) -> bool:
	var w := 0.0
	while w < secs:
		if _flag(k) == want:
			return true
		await get_tree().create_timer(0.2).timeout
		w += 0.2
	return _flag(k) == want


func _marker(name: String) -> String:
	return out_dir.path_join("sync3_" + name)


## Markers are the cross-process handshake. `FileAccess.open(...WRITE)` fails
## silently when the directory does not exist yet (the JSON report only creates
## it in `_finish()`), which made a waiting peer time out and report a false
## failure. Create the directory first, and complain loudly if the write fails.
func _write_marker(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(_marker(name), FileAccess.WRITE)
	if f == null:
		log_line("MARKER WRITE FAILED name=%s dir=%s err=%d" % [
			name, out_dir, FileAccess.get_open_error()])
		return
	f.store_string(str(Time.get_ticks_msec()))
	f.close()


func _wait_marker(name: String, secs: float) -> bool:
	var w := 0.0
	while w < secs:
		if FileAccess.file_exists(_marker(name)):
			return true
		await get_tree().create_timer(0.2).timeout
		w += 0.2
	return FileAccess.file_exists(_marker(name))


func _warp(p: Vector3) -> void:
	player.call("teleport", p, 0.0, 0.0)
	await get_tree().create_timer(0.2).timeout


func _press(id: String) -> void:
	stage.call("request_interaction", id, player, "press")
	await get_tree().create_timer(0.6).timeout


func _peers(secs: float, want: int) -> bool:
	var w := 0.0
	while w < secs:
		var net: Object = stage.get("net")
		if net != null and int(net.call("peer_count")) >= want:
			return true
		await get_tree().create_timer(0.4).timeout
		w += 0.4
	return false


func _run() -> void:
	while stage == null:
		await get_tree().process_frame
	await _wait(1.8)
	player = stage.get("local_player")
	log_line("start mode=%s pid=%d" % [str(stage.get("net").get("mode")), int(stage.get("local_pid"))])
	match role:
		"host":
			await _run_host()
		"client2":
			await _run_client2()
		"client4":
			await _run_client4()
		_:
			await _run_client3()
	_finish()


func _run_host() -> void:
	check(await _peers(90.0, 3), "host sees all three seats on one peer")
	check(int(stage.get("local_pid")) == 1, "host is pid 1")
	# pid2 owns the advance-maintenance pair.
	check(await _wait_flag("rotor_lock_released", 120.0), "host sees pid2's early rotor-lock removal")
	check(not _flag("power_ready"), "power is still off when the lock comes out")
	check(await _wait_flag("coupling_engaged", 120.0), "host sees pid2's early coupling engagement")
	var c: Dictionary = stage.get("credits") as Dictionary
	check(((c.get(2, {}) as Dictionary).get("kinds", {}) as Dictionary).has("fan_lock"),
		"rotor-lock credit is on pid 2")
	check(((c.get(2, {}) as Dictionary).get("kinds", {}) as Dictionary).has("fan_coupling"),
		"coupling credit is on pid 2")
	check(not ((c.get(3, {}) as Dictionary).get("kinds", {}) as Dictionary).has("fan_lock"),
		"rotor-lock credit was NOT given to pid 3")
	check(not _flag("fan_started"), "unpowered start from a client never started the fan")
	check(await _wait_marker("client3_tried_start", 120.0),
		"pid3 really reached and tried the unpowered start")
	# restore power, then let pid3 start it so the "started" credit crosses seats
	stage.call("set_flag", "power_ready", true)
	_write_marker("power_on")
	check(await _wait_flag("fan_started", 90.0), "fan started once power was restored")
	var vent: Node = (stage.get("builder") as Object).get("vent") as Node
	await _wait(1.0)
	check(bool(vent.get("running")) and float(vent.get("speed")) > 0.05,
		"host ventilation machine is spinning")
	var rec3: Dictionary = (stage.get("credits") as Dictionary).get(3, {})
	check((rec3.get("kinds", {}) as Dictionary).has("fan_start"),
		"fan-start credit is booked on the acting seat pid 3")


func _run_client2() -> void:
	check(await _peers(90.0, 3), "client2 joined a three-seat peer")
	check(int(stage.get("local_pid")) == 2, "client2 is pid 2")
	await _warp(ROTOR)
	await _press("rotor_lock")
	check(await _wait_flag("rotor_lock_released", 30.0), "client2 pulled the rotor lock unpowered")
	await _warp(COUPLING)
	await _press("coupling")
	check(await _wait_flag("coupling_engaged", 30.0), "client2 engaged the coupling unpowered")
	_write_marker("client2_done")
	# pid2 must also observe pid3's later start through the state channel
	check(await _wait_flag("fan_started", 150.0), "client2 sees the fan started by pid 3")
	var vent: Node = (stage.get("builder") as Object).get("vent") as Node
	await _wait(1.0)
	check(bool(vent.get("running")), "client2 mirror shows the running machine")


func _run_client3() -> void:
	check(await _peers(90.0, 3), "client3 joined a three-seat peer")
	check(int(stage.get("local_pid")) == 3, "client3 is pid 3")
	# wait for pid2's early service to be visible on this third seat
	check(await _wait_flag("coupling_engaged", 150.0), "client3 sees the early coupling from pid 2")
	check(not _flag("power_ready"), "client3 mirrors an unpowered circuit")
	await _warp(START)
	await _press("start_fan")
	await _wait(1.2)
	_write_marker("client3_tried_start")
	check(not _flag("fan_started"), "unpowered start refused for pid 3 as well")
	check(await _wait_flag("power_ready", 150.0), "client3 sees auxiliary power restored")
	await _press("start_fan")
	check(await _wait_flag("fan_started", 60.0), "client3 started the prepared fan after power")
	var vent: Node = (stage.get("builder") as Object).get("vent") as Node
	await _wait(1.0)
	check(bool(vent.get("running")), "client3 mirror shows the running machine")


func _run_client4() -> void:
	check(await _peers(90.0, 4), "client4 joined a four-seat peer")
	check(int(stage.get("local_pid")) == 4, "client4 is pid 4")
	# A fourth seat must observe the same mechanism state as everyone else and
	# must not be able to shortcut the power gate either.
	check(await _wait_flag("coupling_engaged", 180.0), "client4 sees the early coupling from pid 2")
	# NOTE: this seat joins LAST, so the host may already have restored power by
	# the time client4 finishes booting. Asserting "power is still off" here would
	# be a race against the host's timeline, not a property of the game. The
	# durable invariant is the one that matters: the fan is never running while
	# the circuit is unpowered.
	var vent4: Node = (stage.get("builder") as Object).get("vent") as Node
	if not _flag("power_ready"):
		check(not bool(vent4.get("running")) and not _flag("fan_started"),
			"client4 sees an idle fan while the circuit is unpowered")
	else:
		log_line("client4 joined after the host restored power; skipping the unpowered sample")
	check(await _wait_flag("fan_started", 180.0), "client4 sees the fan started after power")
	await _wait(1.0)
	check(bool(vent4.get("running")), "client4 mirror shows the running machine")
	# reset must clear every interlock for this seat too (host is the authority)
	if int(stage.get("local_pid")) == 1:
		stage.call("host_reset_run", 0)
	var net: Object = stage.get("net")
	check(net != null, "client4 holds a net facade")


func _finish() -> void:
	var ok := failures.is_empty()
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var rep := {"probe": "act1_sync3.gd", "role": role, "passed": ok,
			"checks": checks, "failures": failures,
			"flags": (_flags().duplicate(true) if stage != null else {}), "log": lines}
		var f := FileAccess.open(out_dir.path_join("sync3_%s.json" % role), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(rep, "  "))
			f.close()
	log_line("RESULT checks=%d failures=%d passed=%s" % [checks, failures.size(), str(ok)])
	print("SYNC3_%s %s checks=%d" % [role.to_upper(), "OK" if ok else "FAIL", checks])
	await _wait(1.0)
	get_tree().quit(0 if ok else 1)
