extends SceneTree

## Negative settlement-contract test: writing completion flags into the test
## object must NOT be accepted as a finished chapter.
##
##   godot --headless --path . --script res://tests/test_act05_settlement_negative.gd
##
## The scenario:
##   1. load Act 5 normally (no hand-off) — no Act-5 completion may appear;
##   2. forge `story.run_completed` with no real progress — rejected;
##   3. additionally set the object flags a careless test would write
##      (`app.completed`, `story._completed`, `story.data_taken`) and forge the
##      signal again — still rejected, because the participation ledger has no
##      verified credits and the scene must not switch to the finale;
##   4. no SessionHub chapter record and no scene change happened.

var failures: int = 0
var checks: Array[Dictionary] = []
var hub: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	hub = root.get_node_or_null("/root/SessionHub")
	check("SessionHub autoload is alive", hub != null)
	if hub == null:
		_finish()
		return
	hub.set("chapter_progress", {})
	hub.set("pending_spawn", {})
	var hist: Dictionary = (hub.get("chapter_history") as Dictionary).duplicate(true)
	for key in hist.keys():
		hist[key] = {}
	hub.set("chapter_history", hist)
	hub.set("current_chapter", "act05")

	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(90)

	var app: Node = scene
	var story: StoryDirector = scene.get("story") as StoryDirector
	var session: CoopSession = scene.get("session") as CoopSession
	check("act05 booted", story != null and session != null)
	check("ledger starts without verified credits", not session.can_finish())

	# 1) a plain forged signal with no progress at all
	story.run_completed.emit({"elapsed": 1.0, "participants": {}})
	await _frames(45)
	check("forged run_completed is rejected", _act05_record().is_empty(), str(_act05_record()))

	# 2) the exact shortcut the brief forbids: write completed=true into the
	#    test object, then claim the run finished.
	app.set("completed", true)
	story.set("_completed", true)
	story.set("data_taken", true)
	story.run_completed.emit({"elapsed": 2.0, "participants": {}})
	await _frames(90)
	check("completed=true on the test object is not a settlement", _act05_record().is_empty(), str(_act05_record()))
	check("no participation credits were invented", not session.can_finish(), str(session.completion_report()))
	check("scene stayed in Act 5", current_scene != null and current_scene.name == "Main", str(current_scene.name if current_scene != null else "null"))
	check("hub did not receive a finale chapter", not (hub.get("chapter_history") as Dictionary).has("finale"), str((hub.get("chapter_history") as Dictionary).get("finale", {})))
	_finish()


func _act05_record() -> Dictionary:
	return ((hub.get("chapter_history") as Dictionary).get("act05", {}) as Dictionary)


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func check(label: String, ok: bool, detail: String = "") -> void:
	checks.append({"check": label, "ok": ok, "detail": detail})
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + (("  |  " + detail) if detail != "" else ""))


func _finish() -> void:
	var report: Dictionary = {"checks": checks.size(), "failures": failures, "passed": failures == 0, "results": checks}
	print("ACT05_SETTLEMENT_NEGATIVE_RESULT " + JSON.stringify(report))
	var dir: String = ProjectSettings.globalize_path("res://evidence/tests")
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(dir.path_join("act05_settlement_negative.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	quit(0 if failures == 0 else 1)
