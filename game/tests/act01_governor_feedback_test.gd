extends SceneTree

## Act01 governor/pressure feedback regression test.
##
## Runs the real Act1App interaction path (`request_interaction` -> validation
## -> `_execute_interaction`) against the real Act1Ventilation machine and the
## real Act1Hud in the integrated project's offline solo mode. It intentionally
## performs the "one extra press" mistake (62% -> 100% -> 55%) before the six
## second test can complete, checks that the HUD explains the actual pressure,
## the 58% target and the 78% recovery step, then presses once more and verifies
## the test completes. A final block verifies that a client mirror cannot invent
## its own pass.
##
## Usage:
##   godot --headless --fixed-fps 60 --path <project> \
##     -s res://tests/act01_governor_feedback_test.gd -- <out_dir>

const PRESSURE_MIN := 0.58
const HOLD_SECONDS := 6.0
const GOVERNOR_DEFAULT := 0.62
const GOVERNOR_LOW := 0.55
const GOVERNOR_MID := 0.78
const GOVERNOR_HIGH := 1.0

var stage: Node
var vent: Node
var hud: Node
var player: Node
var checks := 0
var failures: Array[String] = []
var log_lines: Array[String] = []
var out_dir := ""
var started_msec := 0


func _initialize() -> void:
	started_msec = Time.get_ticks_msec()
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0 and not str(user_args[0]).begins_with("--"):
		out_dir = str(user_args[0])
	_run.call_deferred()


func log_line(text: String) -> void:
	print("GOVTEST " + text)
	log_lines.append(text)


func check(ok: bool, text: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)
	return ok


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var waited := 0.0
	while waited < timeout_s:
		if bool(cond.call()):
			return true
		await create_timer(0.1).timeout
		waited += 0.1
	return bool(cond.call())


func _warp(pos: Vector3) -> void:
	player.call("teleport", pos, 0.0, 0.0)
	await create_timer(0.15).timeout


func _press(id: String) -> void:
	stage.call("request_interaction", id, player, "press")
	await create_timer(0.25).timeout


func _hud_text() -> String:
	if hud == null:
		return "<no hud>"
	var out := ""
	var wind: Variant = hud.get("_wind_value")
	if wind is Label:
		out += (wind as Label).text
	var hint: Variant = hud.get("_vent_hint")
	if hint is Label:
		var h := (hint as Label).text
		if h != "":
			out += " | " + h
	return out


func _toast_text() -> String:
	if hud == null:
		return ""
	var toast: Variant = hud.get("_toast")
	if toast is Label:
		return (toast as Label).text
	return ""


func _has_property(obj: Object, prop: String) -> bool:
	if obj == null:
		return false
	for p in obj.get_property_list():
		if str(p.get("name")) == prop:
			return true
	return false


func _num(key: String) -> float:
	return float(vent.get(key))


func _start_fan_and_damper() -> bool:
	# Interlock flags the player would have earned at the power clamp and at the
	# rotor lock/coupling are unrelated to this feature; set them so the real
	# start_fan path can run. `power_ready` is part of that precondition set:
	# start_fan deliberately refuses to spin an unpowered fan.
	stage.call("set_flag", "power_ready", true)
	stage.call("set_flag", "coupling_engaged", true)
	await _warp(Vector3(-7.8, 0.2, -24.2))
	await _press("start_fan")
	var started := bool((stage.get("flags") as Dictionary).get("fan_started", false))
	check(started, "main fan started through the real interaction path")
	await _warp(Vector3(8.0, 0.2, -30.6))
	await _press("damper")
	check(bool((stage.get("flags") as Dictionary).get("damper_open", false)), "main duct damper opened")
	var open: bool = await _wait_until(func() -> bool: return float(vent.get("damper")) > 0.72, 8.0)
	check(open, "damper physically past 72%")
	var pressure_ok: bool = await _wait_until(func() -> bool: return float(vent.get("pressure")) > PRESSURE_MIN, 8.0)
	check(pressure_ok, "default governor builds pressure above 58%")
	return started and open and pressure_ok


func _governor_press() -> void:
	await _warp(Vector3(-8.0, 0.2, -21.2))
	await _press("governor")


func _reset_and_rebuild() -> void:
	stage.call("host_reset_run", 0)
	await _wait(0.5)
	player = stage.get("local_player") as Node
	hud = stage.get("hud") as Node
	vent = (stage.get("builder") as Object).get("vent") as Node
	check(absf(_num("governor") - GOVERNOR_DEFAULT) < 0.001, "reset returns the governor to 62%")
	stage.call("set_flag", "power_ready", true)
	stage.call("set_flag", "coupling_engaged", true)
	await _warp(Vector3(-7.8, 0.2, -24.2))
	await _press("start_fan")
	await _warp(Vector3(8.0, 0.2, -30.6))
	await _press("damper")
	var open: bool = await _wait_until(func() -> bool: return float(vent.get("damper")) > 0.72, 8.0)
	check(open, "rebuild opens the damper")
	var pressure_ok: bool = await _wait_until(func() -> bool: return float(vent.get("pressure")) > PRESSURE_MIN, 8.0)
	check(pressure_ok, "rebuild restores pressure")


func _run() -> void:
	var packed := load("res://act1/act01.tscn") as PackedScene
	check(packed != null, "Act01 scene loads")
	if packed == null:
		_finish()
		return
	stage = packed.instantiate()
	root.add_child(stage)
	await _wait(1.4)
	check(stage != null and str(stage.name) == "Act01", "Act01 stage is running")
	player = stage.get("local_player") as Node
	hud = stage.get("hud") as Node
	vent = (stage.get("builder") as Object).get("vent") as Node
	check(player != null and hud != null and vent != null, "stage exposes player/HUD/ventilation")
	if player == null or hud == null or vent == null:
		_finish()
		return

	# --- 1. real three-gear cycle and the default pressure ---------------
	check(absf(_num("governor") - GOVERNOR_DEFAULT) < 0.001, "governor starts at the built-in 62%")
	var ok_fan: bool = await _start_fan_and_damper()
	check(ok_fan, "ventilation reaches the default 62% pressure")
	var hud_ready: String = _hud_text()
	log_line("HUD_READY " + hud_ready)
	check(hud_ready.find("风压") >= 0, "HUD shows the live pressure")
	check(hud_ready.find("58") >= 0, "HUD names the 58% target while pressure is healthy")

	# The test runs by itself at 62%; the extra press has to happen before the
	# six second hold finishes, so do it now.
	await _governor_press()
	check(absf(_num("governor") - GOVERNOR_HIGH) < 0.001, "first press raises the governor to 100%")
	await _wait(1.4)
	# Read the toast synchronously: an unrelated hazard toast (the wind crate
	# falling) can legitimately overwrite a 4 s toast a frame later.
	await _warp(Vector3(-8.0, 0.2, -21.2))
	stage.call("request_interaction", "governor", player, "press")
	var low_toast: String = _toast_text()
	check(absf(_num("governor") - GOVERNOR_LOW) < 0.001, "one extra press drops the governor to 55%")
	check(low_toast.find("58") >= 0 and low_toast.find("78") >= 0, "the governor toast states consequence and recovery")
	await _wait(0.25)
	var low: bool = await _wait_until(func() -> bool: return float(vent.get("pressure")) <= PRESSURE_MIN, 8.0)
	check(low, "pressure falls to/under 58% at the 55% gear")
	await _wait(1.2)
	var low_text: String = _hud_text()
	log_line("HUD_LOW " + low_text)
	log_line("TOAST_LOW " + low_toast)
	check(low_text.find("风压不足") >= 0, "HUD explains the insufficient pressure")
	check(low_text.find("58") >= 0, "HUD repeats the 58% target next to the failure")
	check(low_text.find("78") >= 0, "HUD names the 78% recovery step")
	check(not bool(vent.get("vent_complete")), "the 6 s test does not complete at 55%")
	await _wait(3.0)
	check(not bool(vent.get("vent_complete")), "holding 55% never completes the test")

	# --- 2. correct recovery completes the test --------------------------
	await _governor_press()
	check(absf(_num("governor") - GOVERNOR_MID) < 0.001, "recovery press returns the governor to 78%")
	var done: bool = await _wait_until(func() -> bool: return bool(vent.get("vent_complete")), 25.0)
	check(done, "78% recovery completes the 6 s pressure test")
	check(float(vent.get("pressure")) > PRESSURE_MIN, "authoritative pressure is above 58% after recovery")
	check(float(vent.get("pressure_test_seconds")) >= HOLD_SECONDS - 0.05, "the authority accumulated the full 6 s hold")
	await _wait(0.3)
	var done_text: String = _hud_text()
	log_line("HUD_DONE " + done_text)
	check(done_text.find("通过") >= 0, "HUD reports the passed test")

	# --- 3. a client mirror cannot invent its own pass -------------------
	await _reset_and_rebuild()
	if _has_property(vent, "authority_test"):
		# Act1App syncs `authority_test` from net.is_authority() every frame; pause
		# only its `_process` so this block can stand in for a client mirror
		# without opening a second ENet peer. The vent's physics keeps running.
		stage.set_process(false)
		vent.set("authority_test", false)
		await _wait(8.0)
		check(not bool(vent.get("vent_complete")), "client mirror does not complete the 6 s test on its own")
		stage.call("_update_hud", 0.1)
		await _wait(0.05)
		check(_hud_text().find("通过") < 0, "client HUD does not invent a pass without the authority")
		vent.call("apply_snapshot", {
			"running": true,
			"emergency": false,
			"speed": GOVERNOR_MID,
			"governor": GOVERNOR_MID,
			"damper": 1.0,
			"damper_target": 1.0,
			"pressure": GOVERNOR_MID,
			"gust": 1.0,
			"test": HOLD_SECONDS,
			"complete": true,
		})
		stage.call("_update_hud", 0.1)
		await _wait(0.2)
		check(bool(vent.get("vent_complete")), "client mirror takes the pass from the authority snapshot")
		check(_hud_text().find("通过") >= 0, "client HUD reports the authoritative pass")
		stage.set_process(true)
	else:
		log_line("SKIP authority_test is absent in this build; client-mirror gate not asserted")

	_finish()


func _finish() -> void:
	var passed := failures.is_empty()
	var report := {
		"probe": "act01_governor_feedback_test.gd",
		"passed": passed,
		"checks": checks,
		"failures": failures,
		"elapsed_seconds": float(Time.get_ticks_msec() - started_msec) / 1000.0,
		"log": log_lines,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("governor_feedback_test.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
			log_line("REPORT " + out_dir.path_join("governor_feedback_test.json"))
	log_line("RESULT checks=%d failures=%d passed=%s" % [checks, failures.size(), str(passed)])
	if passed:
		print("GOVTEST_OK checks=%d" % checks)
	else:
		print("GOVTEST_FAIL %s" % str(failures))
	quit(0 if passed else 1)
