extends SceneTree

## Act05 rescue validation test.
##
## Exercises `CatwalkRig._find_downed_near_pad()` — the only selector that
## decides who the winch may hoist — plus the `catwalk_lock` claim id used by the
## same rig. The scenario places the real players of a two-seat Act05 host on
## the real scene: one healthy at the deck, one downed at the drop pad.
## Nothing is credited by hand and no completion flag is written.

const ACT5_SCENE := "res://scenes/main.tscn"

var out_dir := ""
var checks := 0
var failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not str(args[0]).begins_with("--"):
		out_dir = str(args[0])
	_watchdog.call_deferred()
	_run.call_deferred()


func _watchdog() -> void:
	await create_timer(30.0).timeout
	if _finished:
		return
	print("ACT5_RESCUE_TIMEOUT")
	quit(2)


func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print(("PASS " if ok else "FAIL ") + text)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	var packed: PackedScene = load(ACT5_SCENE) as PackedScene
	if packed == null:
		_check(false, "Act05 scene loads")
		_finish()
		return
	change_scene_to_packed(packed)
	await _wait(2.0)
	var app: Node = current_scene
	_check(app != null and str(app.name) == "Main", "Act05 scene is running")
	if app == null:
		_finish()
		return
	var level: Node = app.get("level") as Node
	var catwalk: Node = level.get("catwalk") as Node
	var player: Node3D = app.get("player") as Node3D
	var session: Node = app.get("session") as Node
	_check(catwalk != null and player != null and session != null,
		"catwalk rig, local body and session exist")
	if catwalk == null or player == null or session == null:
		_finish()
		return

	var pad: Vector3 = catwalk.call("to_global", Vector3(6.6, 0.2, 0.0))
	var group: Array = get_nodes_in_group("player")
	_check(group.size() >= 1, "the player group is populated (%d)" % group.size())

	# Healthy operator at the deck: nobody is downed at the pad.
	player.global_position = catwalk.call("to_global", Vector3(6.55, 4.85, 2.45))
	player.set("impaired_timer", 0.0)
	await _wait(0.2)
	_check(catwalk.call("_find_downed_near_pad") == null,
		"a healthy player at the deck is not a rescue target")

	# Same body downed at the drop pad is selectable.
	player.global_position = pad + Vector3(0.0, 0.1, 0.0)
	player.set("impaired_timer", 4.0)
	await _wait(0.2)
	var target: Variant = catwalk.call("_find_downed_near_pad")
	_check(target == player, "a downed body at the pad becomes the rescue target")

	# A body that is far from the pad is never selected.
	player.global_position = pad + Vector3(40.0, 0.0, 0.0)
	await _wait(0.2)
	_check(catwalk.call("_find_downed_near_pad") == null,
		"a body far from the pad is not a rescue target")

	# The winch claim id stays inside the CoopSession allow-list.
	_check(session.call("is_known_machine", "winch"), "winch is a known machine id")
	_check(session.call("is_known_machine", "catwalk_lock"), "catwalk_lock is a known machine id")
	_check(not session.call("is_known_machine", "winch_2"), "unknown machine ids stay rejected")
	var claim: Dictionary = session.call("try_claim", "winch", 1) as Dictionary
	_check(bool(claim.get("ok", false)), "the host can claim the winch")
	session.call("release_claim", "winch", 1)

	_finish()


func _finish() -> void:
	_finished = true
	var report: Dictionary = {
		"probe": "act05_rescue_test.gd",
		"checks": checks,
		"failures": failures,
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("act05_rescue.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	print("ACT5_RESCUE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("ACT5_RESCUE_OK")
	else:
		print("ACT5_RESCUE_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
