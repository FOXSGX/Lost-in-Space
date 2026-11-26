extends SceneTree

## Act04 -> Act05 hand-off contract test.
##
##   godot --headless --path . --script res://tests/test_act05_handoff.gd
##
## It reproduces exactly what Act 4 does on completion
## (`SessionHub.chapter_progress = completion_payload()` followed by
## `SessionHub.request_scene_switch("res://scenes/main.tscn", spawn)`) and then
## loads Act 5. It never touches Act 5's private flags: the checks are only on
## observable effects (the body's actual spawn transform, the hub's chapter
## state, the Act-4 ledger record and the on-screen hand-off notice).
##
## Layer distinction (see ACT05_CONTRACT_AUDIT.md):
##   L1 payload handed over      -> asserted on the hub before Act 5 loads
##   L2 payload read by Act 5    -> handoff_consumed / handoff_from_act04
##   L3 payload changes the world-> real body position + yaw + chapter state

const ACT04_PAYLOAD := {
	"chapter": "resonance_04",
	"completed": true,
	"seconds": 123.0,
	"memories": {1: true, 2: true, 3: true},
	"strikes": 3,
	"gate_open": true,
	"player_exit_position": Vector3(6.2, 0.2, -25.0),
	"freight_accident_fired": true,
	"freight_cargo_on_platform": true,
	"freight_cargo_clamped": true,
}

var failures: int = 0
var checks: Array[Dictionary] = []
var hub: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	hub = root.get_node_or_null("/root/SessionHub")
	check("L0 SessionHub autoload is alive", hub != null)
	if hub == null:
		_finish()
		return
	await _case_act04_handoff()
	await _case_second_payload()
	await _case_direct_entry()
	_finish()


# ---------------------------------------------------------------------------
# Case 1 — the real Act-4 hand-off shape
# ---------------------------------------------------------------------------
func _case_act04_handoff() -> void:
	_prepare_hub(
		{
			"chapter": "resonance_04",
			"completed": true,
			"from_act4": true,
			"spawn": Vector3(1.5, 4.06, 31.0),
			"yaw": 0.35,
		},
		ACT04_PAYLOAD
	)
	# L1: the payload is on the hub exactly as Act 4 left it.
	check("L1 chapter_progress handed to hub", bool((hub.get("chapter_progress") as Dictionary).get("completed", false)), str(hub.get("chapter_progress")))
	check("L1 pending_spawn handed to hub", bool((hub.get("pending_spawn") as Dictionary).get("from_act4", false)), str(hub.get("pending_spawn")))

	var scene: Node = await _load_act5()
	var player: PlayerController = scene.get("player") as PlayerController
	check("L2 Act05 reports consuming the hand-off", _truthy(scene.get("handoff_consumed")))
	check("L2 Act05 identified the Act-4 origin", _truthy(scene.get("handoff_from_act04")))
	check("L2 Act05 received the payload", not _dict(scene.get("handoff_payload")).is_empty())
	check("L3 body spawns at payload position", player.global_position.distance_to(Vector3(1.5, 4.06, 31.0)) < 0.35, str(player.global_position))
	check("L3 body faces payload yaw", absf(wrapf(player.yaw - 0.35, -PI, PI)) < 0.02, "yaw=%.3f" % player.yaw)
	check("L3 hub current_chapter is act05", str(hub.get("current_chapter")) == "act05", str(hub.get("current_chapter")))
	var hist: Dictionary = hub.get("chapter_history") as Dictionary
	var act4: Dictionary = hist.get("act04", {}) as Dictionary
	check("L3 Act-4 hand-off recorded in the chapter ledger", bool(act4.get("completed", false)), str(act4))
	check("L3 Act-4 payload carried verbatim", is_equal_approx(float(act4.get("seconds", 0.0)), 123.0), str(act4.get("seconds")))
	var hud: GameHud = scene.get("hud") as GameHud
	var toast: String = hud.toast_label.text if hud != null else ""
	check("L3 on-screen hand-off notice mentions Act 4", toast.contains("第四幕"), toast)
	check("L3 Act05 did not fabricate its own completion", (hist.get("act05", {}) as Dictionary).is_empty(), str(hist.get("act05")))
	await _drop_scene(scene)


# ---------------------------------------------------------------------------
# Case 2 — a different payload must produce a different world result
# ---------------------------------------------------------------------------
func _case_second_payload() -> void:
	var payload: Dictionary = ACT04_PAYLOAD.duplicate(true)
	payload["seconds"] = 456.0
	_prepare_hub(
		{
			"chapter": "resonance_04",
			"completed": true,
			"from_act4": true,
			"spawn_position": Vector3(-2.0, 4.06, 27.0),
			"yaw": -0.4,
		},
		payload
	)
	var scene: Node = await _load_act5()
	var player: PlayerController = scene.get("player") as PlayerController
	check("L3 second payload moves the body to its own position", player.global_position.distance_to(Vector3(-2.0, 4.06, 27.0)) < 0.35, str(player.global_position))
	check("L3 second payload applies its own yaw", absf(wrapf(player.yaw + 0.4, -PI, PI)) < 0.02, "yaw=%.3f" % player.yaw)
	var hist: Dictionary = hub.get("chapter_history") as Dictionary
	check("L3 ledger keeps the latest Act-4 payload", is_equal_approx(float((hist.get("act04", {}) as Dictionary).get("seconds", 0.0)), 456.0), str(hist.get("act04")))
	await _drop_scene(scene)


# ---------------------------------------------------------------------------
# Case 3 — direct Act-5 entry (no hand-off) still has to boot and fall back
# ---------------------------------------------------------------------------
func _case_direct_entry() -> void:
	_prepare_hub({}, {})
	var scene: Node = await _load_act5()
	var player: PlayerController = scene.get("player") as PlayerController
	check("L3 direct entry falls back to the level spawn", player.global_position.distance_to(LevelBuilder.SPAWN_POSITION) < 0.35, str(player.global_position))
	check("L3 direct entry is not mistaken for an Act-4 hand-off", not _truthy(scene.get("handoff_from_act04")))
	check("L3 direct entry still marks the chapter as act05", str(hub.get("current_chapter")) == "act05", str(hub.get("current_chapter")))
	await _drop_scene(scene)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
func _prepare_hub(pending: Dictionary, payload: Dictionary) -> void:
	hub.set("chapter_progress", payload.duplicate(true))
	hub.set("pending_spawn", pending.duplicate(true))
	hub.set("current_chapter", "act01")
	var hist: Dictionary = (hub.get("chapter_history") as Dictionary).duplicate(true)
	for key in hist.keys():
		hist[key] = {}
	hist["act04"] = {}
	hub.set("chapter_history", hist)


func _load_act5() -> Node:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(90)
	return scene


func _drop_scene(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	current_scene = null
	await _frames(12)


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


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
	print("ACT05_HANDOFF_RESULT " + JSON.stringify(report))
	var dir: String = ProjectSettings.globalize_path("res://evidence/tests")
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(dir.path_join("act05_handoff.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	quit(0 if failures == 0 else 1)
