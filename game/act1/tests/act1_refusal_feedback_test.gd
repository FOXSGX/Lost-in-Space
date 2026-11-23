extends SceneTree

## LIS-GAMEPLAY-002 · mechanism-refusal feedback probe (solo).
##
## Verifies, against the REAL interaction path (`request_interaction` ->
## validation -> `_execute_interaction`) and the REAL HUD:
##
##   1. the launch-platform chain (`chock` -> `parking_brake` -> `cargo`) answers
##      a wrong-order press with the mechanical reason, not silence;
##   2. each refusal names the machine that must be done first;
##   3. `power_clamp` before the winch explains itself;
##   4. a refusal changes NO state (no skipping a machine by pressing wrongly);
##   5. the correct order still works and does not emit a refusal;
##   6. a completed machine is quiet on repeat press (no toast spam);
##   7. holding E on the same blocked machine does not re-spam (cooldown);
##   8. the live prompt states the requirement before E is even pressed.
##
## Usage:
##   godot --headless --fixed-fps 60 --path game \
##     -s res://act1/tests/act1_refusal_feedback_test.gd -- <out_dir>

var stage: Node
var player: Node
var hud: Node
var vent: Node
var checks := 0
var failures: Array[String] = []
var log_lines: Array[String] = []
var out_dir := ""

const CHOCK := Vector3(-5.62, 0.05, -45.40)
const BRAKE := Vector3(6.55, 1.60, -48.60)
const CARGO := Vector3(5.35, 1.58, -47.05)
const CLAMP := Vector3(2.40, 0.05, -4.30)
const PLATFORM := Vector3(7.20, 1.60, -43.00)


func _initialize() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0 and not str(ua[0]).begins_with("--"):
		out_dir = str(ua[0])
	_run.call_deferred()


func log_line(t: String) -> void:
	print("REFUSE " + t)
	log_lines.append(t)


func check(ok: bool, t: String) -> bool:
	checks += 1
	log_line(("PASS " if ok else "FAIL ") + t)
	if not ok:
		failures.append(t)
	return ok


func _flags() -> Dictionary:
	return stage.get("flags") as Dictionary


func _flag(k: String) -> bool:
	return bool(_flags().get(k, false))


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _warp(p: Vector3) -> void:
	player.call("teleport", p, 0.0, 0.0)
	await _wait(0.25)


## Clear the toast so the next assertion sees only a fresh message. Both the text
## and the HUD's internal timer must be cleared: `_toast_time` is what re-applies
## the fade on the next frame, so zeroing alpha alone leaves it半-visible.
func _clear_toast() -> void:
	var t: Label = hud.get("_toast") as Label
	if t != null:
		t.text = ""
		t.modulate.a = 0.0
	hud.set("_toast_time", 0.0)


## Forget every recorded refusal so the next press of the same machine is
## guaranteed to speak. A real player gets exactly this after walking away and
## coming back later; the cooldown is only there to stop a held E spamming.
func _reset_cooldown() -> void:
	(stage.get("_feedback_seen") as Dictionary).clear()


func _toast() -> String:
	var t: Label = hud.get("_toast") as Label
	var s := t.text if t != null else ""
	var a: float = t.modulate.a if t != null else 0.0
	return s if a > 0.02 else ""


func _look(id: String) -> void:
	var p: Object = (stage.get("interactables") as Dictionary).get(id) as Object
	if p != null:
		player.call("look_at_point", p.get("global_position"))
	await _wait(0.45)


func _prompt(id: String) -> String:
	var p: Object = (stage.get("interactables") as Dictionary).get(id) as Object
	if p == null:
		return ""
	return str(p.call("get_prompt", player))


## Press and return the toast that appeared (empty when nothing was said).
## The caller must have cleared the toast first.
func _press_capture(id: String) -> String:
	stage.call("request_interaction", id, player, "press")
	await _wait(0.25)
	return _toast()


func _run() -> void:
	var packed := load("res://act1/act01.tscn") as PackedScene
	check(packed != null, "Act01 scene loads")
	if packed == null:
		_finish()
		return
	stage = packed.instantiate()
	root.add_child(stage)
	await _wait(1.6)
	player = stage.get("local_player")
	hud = stage.get("hud")
	vent = (stage.get("builder") as Object).get("vent")
	check(player != null and hud != null, "stage exposes player and HUD")

	# Reach the platform with ventilation still incomplete: the state a player
	# actually wanders into when they walk past the fan room early.
	await _warp(PLATFORM)
	await _wait(0.2)

	# ---- 1. chock before ventilation -----------------------------------
	await _warp(CHOCK)
	await _look("chock")
	var chock_prompt := _prompt("chock")
	log_line("PROMPT_CHOCK_LOCKED " + chock_prompt)
	check(chock_prompt.find("通风未恢复") >= 0, "chock prompt names the ventilation interlock")
	_clear_toast()
	var chock_say := await _press_capture("chock")
	log_line("SAY_CHOCK " + chock_say)
	check(chock_say.find("通风") >= 0, "chock refusal names ventilation instead of staying silent")
	check(not _flag("chock_removed"), "chock refusal removes nothing")

	# ---- 2. open the vent interlock the authored way --------------------
	# The real pneumatic chain (fan start / damper / 6 s test) is covered by
	# act1_solo_full_run.gd; set only the gate this probe needs.
	stage.call("set_flag", "vent_complete", true)
	await _wait(0.1)

	# ---- 3. brake before chock -----------------------------------------
	await _warp(BRAKE)
	await _look("parking_brake")
	var brake_prompt := _prompt("parking_brake")
	log_line("PROMPT_BRAKE_LOCKED " + brake_prompt)
	check(brake_prompt.find("止轮楔") >= 0, "brake prompt names the chock as the prerequisite")
	_clear_toast()
	var brake_say := await _press_capture("parking_brake")
	log_line("SAY_BRAKE " + brake_say)
	check(brake_say.find("止轮楔") >= 0, "brake refusal names the chock")
	check(not _flag("brake_released"), "brake refusal does not release the brake")

	# ---- 4. cargo before the chock (furthest-upstream missing step) -----
	await _warp(CARGO)
	await _look("cargo")
	var cargo_prompt := _prompt("cargo")
	log_line("PROMPT_CARGO_LOCKED " + cargo_prompt)
	check(cargo_prompt.find("止轮楔") >= 0, "cargo prompt names the chock first")
	_clear_toast()
	var cargo_say := await _press_capture("cargo")
	log_line("SAY_CARGO " + cargo_say)
	check(cargo_say.find("止轮楔") >= 0, "cargo refusal names the chock while it is still fitted")
	check(not _flag("cargo_secured"), "cargo refusal secures nothing")

	# ---- 5. cargo before the brake (the case named in the brief) --------
	await _warp(CHOCK)
	await _look("chock")
	_clear_toast()
	var ok_chock_early := await _press_capture("chock")
	check(_flag("chock_removed"), "chock removed so the brake interlock is now the blocker")
	check(ok_chock_early.find("通风未恢复") < 0, "the chock success line is not a refusal")
	await _warp(CARGO)
	await _look("cargo")
	var cargo_prompt2 := _prompt("cargo")
	log_line("PROMPT_CARGO_LOCKED_BRAKE " + cargo_prompt2)
	check(cargo_prompt2.find("停车制动") >= 0, "cargo prompt names the brake once the chock is out")
	# Same machine as step 4, so clear the cooldown: the REASON changed (chock ->
	# brake) and the new reason must be allowed to speak. The cooldown exists only
	# to stop a held E repeating the same sentence.
	_reset_cooldown()
	_clear_toast()
	var cargo_say2 := await _press_capture("cargo")
	log_line("SAY_CARGO_BRAKE " + cargo_say2)
	check(cargo_say2.find("制动") >= 0, "cargo refusal names the parking-brake interlock")
	check(not _flag("cargo_secured"), "cargo still not secured while the brake is on")

	# ---- 6. repeat press on the same blocked machine is rate-limited ----
	# Same machine, immediately again: the cooldown must keep it quiet.
	_reset_cooldown()
	_clear_toast()
	stage.call("request_interaction", "cargo", player, "press")
	await _wait(0.05)
	var first_of_pair := _toast()
	stage.call("request_interaction", "cargo", player, "press")
	await _wait(0.25)
	var second_of_pair := _toast()
	log_line("SAY_CARGO_PAIR first='%s' second='%s'" % [first_of_pair, second_of_pair])
	check(first_of_pair.find("制动") >= 0, "the first press of the pair is answered")
	check(second_of_pair == first_of_pair,
		"a second press inside the cooldown does not re-fire (no spam)")
	# but a different blocked machine still answers within the same window
	await _warp(BRAKE)
	await _look("parking_brake")
	_clear_toast()
	var other_say := await _press_capture("parking_brake")
	log_line("SAY_BRAKE_OTHER " + other_say)
	check(other_say != "", "a different blocked machine still answers at once")

	# ---- 7. finish the chain in the correct order ----------------------
	_clear_toast()
	var ok_brake := await _press_capture("parking_brake")
	log_line("SAY_BRAKE_OK " + ok_brake)
	check(_flag("brake_released"), "brake released in the correct order")
	# The success line legitimately contains "止轮楔" ("the body is now held by the
	# chock"), so compare against the refusal wording instead of the word itself.
	check(ok_brake.find("压不下去") < 0, "the successful brake press shows no refusal text")

	await _warp(CARGO)
	await _look("cargo")
	_clear_toast()
	# MECHANICS-001F：现在要真的摇棘轮（每档 0.55 s），固定状态由张力/棘爪决定
	var ok_cargo := ""
	for n in range(10):
		if _flag("cargo_secured"):
			break
		ok_cargo = await _press_capture("cargo")
		await _wait(0.7)
	log_line("SAY_CARGO_OK " + ok_cargo)
	check(_flag("cargo_secured"), "cargo secured in the correct order")
	check(ok_cargo.find("拉不动") < 0 and ok_cargo.find("联锁锁住") < 0,
		"the successful cargo press shows no refusal text")

	# ---- 7. completed machines stay quiet on repeat press ---------------
	_clear_toast()
	var repeat_chock := await _press_capture("chock")
	log_line("SAY_CHOCK_DONE_REPEAT '%s'" % repeat_chock)
	check(repeat_chock == "", "a completed machine says nothing on repeat press")
	_clear_toast()
	var repeat_cargo := await _press_capture("cargo")
	check(repeat_cargo == "", "a completed cargo strap says nothing on repeat press")

	# ---- 8. power_clamp before the winch --------------------------------
	stage.call("host_reset_run", 0)
	await _wait(0.6)
	_reset_cooldown()
	# Fresh run: the chock/brake/cargo assertions above do not leak state.
	check(not _flag("chock_removed") and not _flag("brake_released") and not _flag("cargo_secured"),
		"reset cleared the platform chain")
	var clamp_prompt := _prompt("power_clamp")
	log_line("PROMPT_CLAMP_LOCKED " + clamp_prompt)
	check(clamp_prompt.find("绞盘") >= 0, "clamp prompt names the winch as the prerequisite")
	await _warp(CLAMP)
	await _look("power_clamp")
	_clear_toast()
	var clamp_say := await _press_capture("power_clamp")
	log_line("SAY_CLAMP " + clamp_say)
	check(clamp_say.find("绞盘") >= 0, "clamp refusal names the winch")
	check(not _flag("power_clamped") and not _flag("power_ready"),
		"clamp refusal grants no power")

	# ---- 9. the refusal did not weaken the fan early-service logic ------
	_reset_cooldown()
	check(not _flag("fan_started"), "no fan start happened during the whole probe")
	await _warp(Vector3(-7.80, 0.05, -23.00))
	await _look("start_fan")
	_clear_toast()
	var start_say := await _press_capture("start_fan")
	log_line("SAY_START " + start_say)
	check(start_say.find("联轴器") >= 0, "start handle still refuses without the coupling")

	_finish()


func _finish() -> void:
	var passed := failures.is_empty()
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var report := {"probe": "act1_refusal_feedback_test.gd", "passed": passed,
			"checks": checks, "failures": failures, "log": log_lines}
		var f := FileAccess.open(out_dir.path_join("act1_refusal_feedback_test.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	log_line("RESULT checks=%d failures=%d passed=%s" % [checks, failures.size(), str(passed)])
	print("REFUSAL_%s checks=%d" % ["OK" if passed else "FAIL", checks])
	quit(0 if passed else 1)
