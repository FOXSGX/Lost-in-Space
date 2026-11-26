extends SceneTree

## Verifies the Act04->Act05 handoff payload is replicated in the reliable
## scene-switch envelope and consumed into chapter_history on the client path.
## No scene is instantiated and no ledger/credit/completion gate is touched: the
## test drives the same SessionHub -> Act05App consumer methods with a fixture.

var checks := 0
var failures: Array[String] = []
var out_dir := ""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not str(args[0]).begins_with("--"):
		out_dir = str(args[0])
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print(("PASS " if ok else "FAIL ") + text)


func _run() -> void:
	var hub: Node = root.get_node_or_null("/root/SessionHub")
	_check(hub != null, "SessionHub autoload exists")
	if hub == null:
		_finish()
		return
	var payload: Dictionary = {
		"chapter": "resonance_04",
		"completed": true,
		"seconds": 42.0,
		"memories": {"0": true, "2": true},
		"strikes": 3,
		"gate_open": true,
		"player_exit_position": Vector3(1, 0, -2),
		"freight_accident_fired": true,
		"freight_cargo_on_platform": true,
		"freight_cargo_clamped": true,
		"freight_platform_x": 2.5,
	}
	var spawn: Dictionary = {
		"chapter": "resonance_04",
		"from_act4": true,
		"completed": true,
		"_chapter_progress": payload.duplicate(true),
		"_chapter_history": {
			"act01": {"completed": true},
			"act23": {"completed": true},
			"act04": payload.duplicate(true),
			"act05": {},
		},
		"_current_chapter": "act05",
	}
	# Client path: SessionHub.do_scene_switch() stores pending_spawn first and
	# then calls _apply_campaign_state().
	hub.set("pending_spawn", spawn.duplicate(true))
	hub.call("_apply_campaign_state", spawn)
	var progress: Dictionary = hub.get("chapter_progress") as Dictionary
	_check(not progress.is_empty(), "client scene-switch applies _chapter_progress")
	_check(str(progress.get("chapter", "")) == "resonance_04",
		"client chapter_progress is the Act04 payload")
	_check(int(progress.get("strikes", -1)) == 3, "payload fields survive the switch")

	# Act05App._consume_handoff() turns the payload into chapter_history.act04.
	var app_script: Script = load("res://scripts/core/app.gd") as Script
	_check(app_script != null, "Act05App script loads")
	if app_script == null:
		_finish()
		return
	var app: Node = app_script.new() as Node
	app.call("_consume_handoff")
	_check(bool(app.get("handoff_from_act04")), "client recognizes the Act04 handoff")
	var history: Dictionary = hub.get("chapter_history") as Dictionary
	var act04: Dictionary = history.get("act04", {}) as Dictionary
	_check(not act04.is_empty(), "client chapter_history.act04 is populated")
	_check(int(act04.get("strikes", -1)) == 3, "client history carries the authoritative strikes")
	_check(str(hub.get("current_chapter")) == "act05", "current chapter advances to act05")
	app.free()

	var report: Dictionary = {
		"probe": "test_chapter_history_sync.gd",
		"checks": checks,
		"failures": failures,
		"act04_history_keys": act04.keys(),
		"act04_history_size": act04.size(),
	}
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("chapter_history.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, "  "))
			f.close()
	_finish()


func _finish() -> void:
	print("CHAPTER_HISTORY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("CHAPTER_HISTORY_OK")
	else:
		print("CHAPTER_HISTORY_FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
