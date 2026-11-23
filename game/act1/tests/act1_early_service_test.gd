extends SceneTree

## Act 01 "advance maintenance" regression probe (LIS-GAMEPLAY-001).
##
## Verifies the parallel-preparation rule against the REAL interaction path
## (`Act1App.request_interaction` -> validation -> `_execute_interaction`) and
## the REAL machine/HUD, with no direct flag writes before they are asserted:
##
##   1. `rotor_lock` is a mechanical pin, so it may be pulled while
##      `power_ready` is still false (advance maintenance).
##   2. `coupling` still depends on the rotor lock (refused before it).
##   3. `start_fan` refuses while `power_ready` is false even when the rotor lock
##      and coupling are already prepared — an unpowered fan never spins.
##   4. As soon as power is restored the prepared machine starts, i.e. the
##      prepared work is really consumed and not just cosmetic.
##   5. Prompts, HUD hint and objective text explain both states.
##   6. `host_reset_run` returns the machine to the initial lockout state.
##
## Usage:
##   godot --headless --fixed-fps 60 --path game \
##     -s res://act1/tests/act1_early_service_test.gd -- <out_dir>

var stage: Node
var player: Node
var hud: Node
var vent: Node
var checks := 0
var failures: Array[String] = []
var log_lines: Array[String] = []
var out_dir := ""

## Same standing positions the solo full run walks to, so this probe stays on
## real, reachable floor instead of teleporting into geometry.
const ROTOR_LOCK_APPROACH := Vector3(7.70, 0.05, -22.30)
const COUPLING_APPROACH := Vector3(8.10, 0.05, -28.15)
const START_FAN_APPROACH := Vector3(-7.80, 0.05, -23.00)


func _initialize() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0 and not str(user_args[0]).begins_with("--"):
		out_dir = str(user_args[0])
	_run.call_deferred()


func log_line(text: String) -> void:
	print("EARLY " + text)
	log_lines.append(text)


func check(ok: bool, text: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)
	return ok


func _flags() -> Dictionary:
	return stage.get("flags") as Dictionary


func _flag(key: String) -> bool:
	return bool(_flags().get(key, false))


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _warp(pos: Vector3) -> void:
	player.call("teleport", pos, 0.0, 0.0)
	await create_timer(0.15).timeout


## Real press through the stage's own request/validate/execute path.
func _press(id: String) -> void:
	stage.call("request_interaction", id, player, "press")
	await create_timer(0.3).timeout


func _toast_text() -> String:
	if hud == null:
		return ""
	var toast: Variant = hud.get("_toast")
	return (toast as Label).text if toast is Label else ""


func _hud_hint() -> String:
	if hud == null:
		return ""
	var hint: Variant = hud.get("_vent_hint")
	return (hint as Label).text if hint is Label else ""


func _objective_text() -> String:
	var obj: Dictionary = stage.call("_objective_text") as Dictionary
	return str(obj.get("title", "")) + " / " + str(obj.get("sub", ""))


func _prompt(id: String) -> String:
	var point: Object = (stage.get("interactables") as Dictionary).get(id) as Object
	if point == null:
		return ""
	return str(point.call("get_prompt", player))


func _run() -> void:
	var packed := load("res://act1/act01.tscn") as PackedScene
	check(packed != null, "Act01 scene loads")
	if packed == null:
		_finish()
		return
	stage = packed.instantiate()
	root.add_child(stage)
	await _wait(1.4)
	player = stage.get("local_player") as Node
	hud = stage.get("hud") as Node
	vent = (stage.get("builder") as Object).get("vent") as Node
	if player == null or hud == null or vent == null:
		check(false, "stage exposes player/HUD/ventilation")
		_finish()
		return
	check(true, "stage exposes player/HUD/ventilation")

	# --- 0. initial lockout state ---------------------------------------
	check(not _flag("power_ready"), "power is not ready at spawn")
	check(not _flag("rotor_lock_released"), "rotor lock is still fitted at spawn")
	check(not _flag("coupling_engaged"), "drive coupling is separated at spawn")
	check(not bool(vent.get("running")), "fan is idle at spawn")

	# --- 1. coupling cannot precede the rotor lock -----------------------
	await _warp(COUPLING_APPROACH)
	await _press("coupling")
	check(not _flag("coupling_engaged"), "coupling press is refused before the rotor lock")
	var coupling_refused_toast := _toast_text()
	log_line("TOAST_COUPLING_REFUSED " + coupling_refused_toast)
	check(coupling_refused_toast.find("转子") >= 0, "refused coupling press names the rotor lock")
	check(_prompt("coupling").find("转子") >= 0, "coupling prompt states the rotor-lock dependency")

	# --- 2. rotor lock is operable without power -------------------------
	var rotor_prompt_before := _prompt("rotor_lock")
	log_line("PROMPT_ROTOR_UNPOWERED " + rotor_prompt_before)
	check(rotor_prompt_before.find("提前检修") >= 0, "unpowered rotor-lock prompt announces advance maintenance")
	await _warp(ROTOR_LOCK_APPROACH)
	await _press("rotor_lock")
	check(_flag("rotor_lock_released"), "rotor lock can be pulled while power_ready is false")
	check(not _flag("power_ready"), "pulling the rotor lock does not fake power")
	var rotor_toast := _toast_text()
	log_line("TOAST_ROTOR " + rotor_toast)
	check(rotor_toast.find("得电") >= 0, "rotor-lock toast says the fan still needs power")
	check(_prompt("rotor_lock").find("已拔出") >= 0, "rotor-lock prompt switches to the fitted state")

	# --- 3. coupling now engages, still without power --------------------
	await _warp(COUPLING_APPROACH)
	var coupling_prompt := _prompt("coupling")
	log_line("PROMPT_COUPLING_UNPOWERED " + coupling_prompt)
	check(coupling_prompt.find("提前检修") >= 0, "unpowered coupling prompt announces advance maintenance")
	await _press("coupling")
	check(_flag("coupling_engaged"), "coupling engages after the rotor lock, still unpowered")
	check(not _flag("power_ready"), "engaging the coupling does not fake power")
	var coupling_toast := _toast_text()
	log_line("TOAST_COUPLING " + coupling_toast)
	check(coupling_toast.find("提前检修") >= 0, "prepared coupling toast names advance maintenance")
	check(_prompt("coupling").find("已接合") >= 0, "coupling prompt switches to the engaged state")
	check(_prompt("start_fan").find("未得电") >= 0, "start handle prompt names the missing power")
	# The objective's ② branch is only reachable after the entry door is open in
	# the real flow. That door sequence (gantry -> latch -> handle) is covered
	# end-to-end by act1_solo_full_run.gd, so this probe drives the same machine
	# callback the door rig calls instead of repeating the 6 s hold.
	stage.call("on_door_opened")
	await _wait(0.2)
	var prepared_objective := _objective_text()
	log_line("OBJECTIVE_PREPARED " + prepared_objective)
	check(prepared_objective.find("把辅助电源送到导轨插座") >= 0 and prepared_objective.find("通风机检修可先做") >= 0,
		"objective still asks for power and notes the prep option")

	# --- 4. start_fan must refuse without power --------------------------
	await _warp(START_FAN_APPROACH)
	await _press("start_fan")
	check(not _flag("fan_started"), "start_fan does not start the fan without power")
	check(not bool(vent.get("running")), "ventilation machine stays idle without power")
	var start_toast := _toast_text()
	log_line("TOAST_START_BLOCKED " + start_toast)
	check(start_toast.find("未得电") >= 0, "blocked start names the missing power")
	await _wait(0.4)
	stage.call("_update_hud", 0.1)
	await _wait(0.1)
	var prepped_hint := _hud_hint()
	log_line("HUD_PREPPED_UNPOWERED " + prepped_hint)
	check(prepped_hint.find("检修就绪") >= 0 and prepped_hint.find("未得电") >= 0,
		"HUD explains that the machine is serviced but has no control power")
	check(float(vent.get("speed")) < 0.01, "unpowered fan rotor has zero speed")

	# --- 5. restoring power releases the prepared start ------------------
	# `set_flag` stands in for the power-cart chain here: the real cart/winch/
	# clamp path is covered end-to-end by act1_solo_full_run.gd.
	stage.call("set_flag", "power_ready", true)
	await _wait(0.2)
	await _press("start_fan")
	check(_flag("fan_started"), "a machine prepared early starts once power arrives")
	check(bool(vent.get("running")), "ventilation machine runs after the powered start")
	await _wait(0.6)
	check(float(vent.get("speed")) > 0.05, "rotor builds speed after the powered start")
	var started_objective := _objective_text()
	log_line("OBJECTIVE_STARTED " + started_objective)
	check(started_objective.find("压力测试") >= 0, "objective advances to the pressure test")

	# --- 6. reset restores the original lockout --------------------------
	stage.call("host_reset_run", 0)
	await _wait(0.6)
	check(not _flag("power_ready") and not _flag("rotor_lock_released")
		and not _flag("coupling_engaged") and not _flag("fan_started"),
		"reset returns every fan interlock to false")
	check(not bool(vent.get("running")) and float(vent.get("speed")) < 0.01,
		"reset stops the ventilation machine")
	check(_prompt("rotor_lock").find("提前检修") >= 0, "reset restores the unpowered rotor-lock prompt")
	# The whole advance-maintenance loop must be replayable after a reset: the
	# rotor lock is operable again and the power gate still holds.
	stage.call("_update_hud", 0.1)
	await _wait(0.1)
	var reset_hint := _hud_hint()
	log_line("HUD_AFTER_RESET " + reset_hint)
	check(reset_hint.find("检修就绪") < 0, "reset drops the serviced-ready HUD state")
	await _warp(ROTOR_LOCK_APPROACH)
	await _press("rotor_lock")
	check(_flag("rotor_lock_released"), "after reset the rotor lock can be serviced again")
	await _warp(COUPLING_APPROACH)
	await _press("coupling")
	check(_flag("coupling_engaged"), "after reset the coupling engages again")
	await _warp(START_FAN_APPROACH)
	await _press("start_fan")
	check(not _flag("fan_started") and not bool(vent.get("running")),
		"after reset the unpowered start is still refused")

	_finish()


func _finish() -> void:
	var passed := failures.is_empty()
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var report := {
			"probe": "act1_early_service_test.gd",
			"passed": passed,
			"checks": checks,
			"failures": failures,
			"log": log_lines,
		}
		var f := FileAccess.open(out_dir.path_join("act1_early_service_test.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	log_line("RESULT checks=%d failures=%d passed=%s" % [checks, failures.size(), str(passed)])
	if passed:
		print("EARLY_SERVICE_OK checks=%d" % checks)
	else:
		print("EARLY_SERVICE_FAIL %s" % str(failures))
	quit(0 if passed else 1)
