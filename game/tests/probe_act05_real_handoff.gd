extends SceneTree

## R6B-2 integration probe: Act 5 must consume the hand-off exactly as the
## **real** Act 4 producer writes it today.
##
##   godot --headless --path . --script res://tests/probe_act05_real_handoff.gd
##
## Difference from `tests/test_act05_handoff.gd` (delivered by task D): that test
## hands over the *contract* shape (`pending_spawn.spawn` + `yaw`). Act 4 still
## leaves through the legacy `SessionHub.request_scene_switch()` path, so its
## actual `pending_spawn` is only:
##
##     {"chapter": "resonance_04", "completed": true, "from_act4": true}
##
## (see `scripts/act4/game.gd:687-706`). This probe reproduces that exact shape
## and asserts the observable results: the payload is consumed, the origin is
## identified, the Act-4 completion is adopted once, the chapter advances, and
## the body falls back to the level spawn because no position was handed over.
## Nothing is written into Act 5's private flags.

var failures: int = 0
var checks: Array[Dictionary] = []
var hub: Node

const REAL_ACT04_SPAWN := {
	"chapter": "resonance_04",
	"completed": true,
	"from_act4": true,
}

const REAL_ACT04_PROGRESS := {
	"chapter": "resonance_04",
	"completed": true,
	"seconds": 77.5,
	"memories": {1: true, 2: true, 3: true},
	"strikes": 2,
	"gate_open": true,
	"player_exit_position": Vector3(6.2, 0.2, -25.0),
	"freight_accident_fired": false,
	"freight_cargo_on_platform": false,
	"freight_cargo_clamped": false,
	"freight_platform_x": -8.8,
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	hub = root.get_node_or_null("/root/SessionHub")
	check("SessionHub autoload is alive", hub != null)
	if hub == null:
		_finish()
		return

	hub.set("chapter_progress", REAL_ACT04_PROGRESS.duplicate(true))
	hub.set("pending_spawn", REAL_ACT04_SPAWN.duplicate(true))
	hub.set("current_chapter", "act01")
	var hist: Dictionary = (hub.get("chapter_history") as Dictionary).duplicate(true)
	for key in hist.keys():
		hist[key] = {}
	hub.set("chapter_history", hist)

	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _i in range(90):
		await physics_frame

	var player: PlayerController = scene.get("player") as PlayerController
	check("act05 booted from the real Act-4 spawn shape", player != null)
	check("payload consumed", _truthy(scene.get("handoff_consumed")))
	check("Act-4 origin recognised without a spawn position", _truthy(scene.get("handoff_from_act04")))
	check("chapter_progress copied to the instance", not _dict(scene.get("handoff_payload")).is_empty(), str(scene.get("handoff_payload")))
	check("pending_spawn copied to the instance", bool(_dict(scene.get("handoff_pending")).get("from_act4", false)), str(scene.get("handoff_pending")))
	check("body falls back to the level spawn (no position handed over)",
		player != null and player.global_position.distance_to(LevelBuilder.SPAWN_POSITION) < 0.35,
		str(player.global_position) if player != null else "null")
	check("chapter advanced to act05", str(hub.get("current_chapter")) == "act05", str(hub.get("current_chapter")))
	var act4: Dictionary = (hub.get("chapter_history") as Dictionary).get("act04", {}) as Dictionary
	check("Act-4 completion adopted exactly once", bool(act4.get("completed", false)), str(act4))
	check("Act-4 payload carried verbatim", is_equal_approx(float(act4.get("seconds", 0.0)), 77.5), str(act4.get("seconds")))
	check("Act05 did not fabricate its own completion", ((hub.get("chapter_history") as Dictionary).get("act05", {}) as Dictionary).is_empty(), str((hub.get("chapter_history") as Dictionary).get("act05", {})))
	scene.queue_free()
	current_scene = null
	for _i in range(12):
		await physics_frame
	check("second boot with the same real shape keeps the same state", await _second_boot_keeps_state())
	_finish()


## A second Act 5 boot (F5-style) must not overwrite the adopted record and must
## still consume the same frozen fields.
func _second_boot_keeps_state() -> bool:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _i in range(30):
		await physics_frame
	var act4: Dictionary = (hub.get("chapter_history") as Dictionary).get("act04", {}) as Dictionary
	var ok: bool = bool(act4.get("completed", false)) and is_equal_approx(float(act4.get("seconds", 0.0)), 77.5)
	scene.queue_free()
	current_scene = null
	for _i in range(12):
		await physics_frame
	return ok


func _truthy(value: Variant) -> bool:
	return value != null and bool(value)


func _dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}


func check(label: String, ok: bool, detail: String = "") -> void:
	checks.append({"check": label, "ok": ok, "detail": detail})
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + (("  |  " + detail) if detail != "" else ""))


func _finish() -> void:
	var report: Dictionary = {"checks": checks.size(), "failures": failures, "passed": failures == 0, "results": checks}
	print("PROBE_ACT05_REAL_HANDOFF_RESULT " + JSON.stringify(report))
	var dir: String = ProjectSettings.globalize_path("res://evidence/tests")
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(dir.path_join("probe_act05_real_handoff.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	quit(0 if failures == 0 else 1)
