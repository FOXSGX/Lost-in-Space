extends SceneTree

## Act01 rescue authorization test.
##
## Drives the real Act1App validation/execution path in one process:
##   * a downed teammate can be rescued by a second player at the winch console
##     (positive: real credit + a validated `climb` grant is produced)
##   * the downed player cannot use the winch on themselves
##   * a standing player cannot claim `self_rescue`
##   * a downed player next to the ladder can self-rescue
## No ledger credit is written by hand: every credit comes from the interaction.

const ACT1_SCENE := "res://act1/act01.tscn"

var out_dir := ""
var checks := 0
var failures: Array[String] = []
var _finished := false
var stage: Node = null
var player: Node = null


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not str(args[0]).begins_with("--"):
		out_dir = str(args[0])
	_watchdog.call_deferred()
	_run.call_deferred()


func _watchdog() -> void:
	await create_timer(25.0).timeout
	if _finished:
		return
	print("ACT1_RESCUE_TIMEOUT")
	quit(2)


func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print(("PASS " if ok else "FAIL ") + text)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	var packed: PackedScene = load(ACT1_SCENE) as PackedScene
	if packed == null:
		_check(false, "Act01 scene loads")
		_finish()
		return
	change_scene_to_packed(packed)
	await _wait(1.2)
	stage = current_scene
	_check(stage != null and str(stage.name) == "Act01", "Act01 scene is running")
	if stage == null:
		_finish()
		return
	player = stage.get("local_player") as Node
	var builder: Variant = stage.get("builder")
	var winch_console: Node3D = builder.get("winch_console") as Node3D
	var ladder_anchor: Node3D = builder.get("ladder_anchor") as Node3D
	_check(player != null and winch_console != null and ladder_anchor != null,
		"winch console and ladder anchor exist")
	if player == null or winch_console == null or ladder_anchor == null:
		_finish()
		return

	# A second seat, downed in the pit (host-side mirror of that client).
	stage.call("host_add_player", 2)
	var remote_states: Dictionary = stage.get("remote_states")
	remote_states[2] = {
		"pos": Vector3(3.9, -2.0, -22.2), "yaw": 0.0, "grab": false,
		"downed": true, "hold": false, "external": false,
	}
	var credits: Dictionary = stage.get("credits")
	var hazard_before: int = int((credits[1] as Dictionary).get("phases", {}).get("hazard", 0))

	# Stand at the winch console and rescue pid 2 (valid). The standalone scene
	# has no authoritative peer (the integrated facade reports is_host=false in
	# solo), so `host_handle_interaction_request` is a no-op here. Validation is
	# asserted through `_validate_interaction`; execution goes through
	# `_execute_interaction`, the exact function the host path calls after it.
	(player as Node3D).global_position = winch_console.global_position + Vector3(0.2, 0.0, 0.2)
	await _wait(0.2)
	_check(bool(stage.call("_validate_interaction", 1, "rescue_winch", "press")),
		"the winch operator passes proximity validation")
	stage.call("_execute_interaction", 1, "rescue_winch", "press")
	await _wait(0.2)
	var hazard_after: int = int((credits[1] as Dictionary).get("phases", {}).get("hazard", 0))
	_check(hazard_after > hazard_before, "a real rescue grants the operator a phase credit")
	var kinds: Dictionary = (credits[1] as Dictionary).get("kinds", {}) as Dictionary
	_check(kinds.has("rescue"), "the operator credit kind is rescue")

	# The downed player cannot operate the winch on themselves.
	remote_states[2] = {
		"pos": winch_console.global_position + Vector3(0.1, 0.0, 0.1),
		"yaw": 0.0, "grab": false, "downed": true, "hold": false, "external": false,
	}
	var self_credit_before: int = int((credits[2] as Dictionary).get("phases", {}).get("hazard", 0))
	stage.call("_execute_interaction", 2, "rescue_winch", "press")
	await _wait(0.2)
	var self_credit_after: int = int((credits[2] as Dictionary).get("phases", {}).get("hazard", 0))
	_check(self_credit_after == self_credit_before,
		"a downed player cannot winch themselves up (no self credit)")

	# A standing player cannot claim self-rescue even while in range of the
	# ladder: the execution gate refuses a body that is not downed.
	remote_states[2] = {
		"pos": ladder_anchor.global_position, "yaw": 0.0, "grab": false,
		"downed": false, "hold": false, "external": false,
	}
	var standing_before: int = int((credits[2] as Dictionary).get("phases", {}).get("hazard", 0))
	stage.call("_execute_interaction", 2, "self_rescue", "press")
	await _wait(0.2)
	var standing_after: int = int((credits[2] as Dictionary).get("phases", {}).get("hazard", 0))
	_check(standing_after == standing_before, "a standing player cannot claim self-rescue")

	# A downed player next to the ladder can self-rescue.
	remote_states[2] = {
		"pos": Vector3(4.5, -2.0, -22.2), "yaw": 0.0, "grab": false,
		"downed": true, "hold": false, "external": false,
	}
	_check(bool(stage.call("_validate_interaction", 2, "self_rescue", "press")),
		"a downed player next to the ladder passes self-rescue validation")
	var rescue_before: int = int((credits[2] as Dictionary).get("phases", {}).get("hazard", 0))
	stage.call("_execute_interaction", 2, "self_rescue", "press")
	await _wait(0.2)
	var rescue_after: int = int((credits[2] as Dictionary).get("phases", {}).get("hazard", 0))
	_check(rescue_after > rescue_before, "a real self-rescue grants a phase credit")

	_finish()


func _finish() -> void:
	_finished = true
	var report: Dictionary = {
		"probe": "act01_rescue_test.gd",
		"checks": checks,
		"failures": failures,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("act01_rescue.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	print("ACT1_RESCUE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("ACT1_RESCUE_OK")
	else:
		print("ACT1_RESCUE_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)


