extends SceneTree

# -----------------------------------------------------------------------------
# merge_safety_handoff_probe.gd · C2 x G conflict guard (isolated, deterministic)
#
#   1) hand-off window: a moving cart + a rider below deck must NOT trigger the
#      protective brake (G sets _chapter_handoff_started; C2's tick must yield).
#   2) positive control: the same state outside the hand-off window must brake
#      exactly once with driver_left_deck (C2 behaviour preserved).
#   3) teardown: an actor node that was freed (old player release) is skipped,
#      not dereferenced, and does not trigger a brake.
#
# Output: one MERGE_SAFETY line, exit 0 only when every check passes.
# -----------------------------------------------------------------------------

var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "detail": detail})
	if not ok:
		failures += 1
	print("MERGE_SAFETY_", "OK " if ok else "FAIL ", label, " ", JSON.stringify(detail))

func _finish() -> void:
	print("MERGE_SAFETY ", JSON.stringify({
		"checks": checks.size(), "failures": failures, "passed": failures == 0,
	}))
	quit(0 if failures == 0 else 2)

func run() -> void:
	var app: Node = (load("res://act23/act23_entry.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await frames(20)
	var stage: Node3D = app.find_child("MovingCartSlice", true, false) as Node3D
	if stage == null:
		check(false, "stage_present")
		_finish()
		return
	var cart: Node = stage.get("cart")
	var player: CharacterBody3D = stage.get("player") as CharacterBody3D
	stage.set_physics_process(false)
	cart.set_physics_process(false)
	player.set_physics_process(false)

	# --- 1) hand-off window: no brake even with a moving cart + off-deck rider
	var riders: Dictionary = stage.get("_safety_riders") as Dictionary
	stage.set("_chapter_handoff_started", true)
	stage.set("_safety_brake_count", 0)
	riders[1] = true
	cart.set("running", true)
	cart.set("speed", 1.55)
	player.call("restore_at", cart.to_global(Vector3(1.0, 0.6, -3.0)))
	stage.call("_safety_brake_tick")
	var local_y: float = cart.to_local(player.global_position).y
	check(int(stage.get("_safety_brake_count")) == 0 and bool(cart.get("running")),
		"handoff_window_does_not_brake",
		{"brake_count": int(stage.get("_safety_brake_count")), "running": bool(cart.get("running")), "local_y": local_y})

	# --- 2) positive control: outside the hand-off window the same state brakes
	stage.set("_chapter_handoff_started", false)
	stage.set("_safety_triggered", false)
	stage.set("_safety_brake_count", 0)
	riders[1] = true
	cart.set("running", true)
	cart.set("speed", 1.55)
	player.call("restore_at", cart.to_global(Vector3(1.0, 0.6, -3.0)))
	stage.call("_safety_brake_tick")
	check(int(stage.get("_safety_brake_count")) == 1 and not bool(cart.get("running"))
			and str(cart.get("brake_reason")) == "driver_left_deck",
		"normal_tick_still_brakes_once",
		{"brake_count": int(stage.get("_safety_brake_count")), "running": bool(cart.get("running")),
		 "brake_reason": str(cart.get("brake_reason"))})

	# --- 3) released old actor: freed node is skipped, not dereferenced
	stage.set("_safety_brake_count", 0)
	stage.set("_safety_triggered", false)
	stage.call("_safety_reset")
	cart.set("running", true)
	cart.set("speed", 1.55)
	player.call("restore_at", cart.to_global(Vector3(1.0, 1.91, 1.6)))
	riders[1] = true
	var ghost: CharacterBody3D = CharacterBody3D.new()
	ghost.name = "ReleasedOldPlayer"
	stage.add_child(ghost)
	ghost.global_position = cart.to_global(Vector3(1.0, 0.6, -3.0))
	var actors: Dictionary = stage.get("actors") as Dictionary
	actors[2] = ghost
	riders[2] = true
	ghost.free()
	stage.call("_safety_brake_tick")
	check(int(stage.get("_safety_brake_count")) == 0 and bool(cart.get("running")),
		"released_actor_is_skipped",
		{"brake_count": int(stage.get("_safety_brake_count")), "running": bool(cart.get("running")),
		 "ghost_valid": is_instance_valid(ghost)})

	# --- 4) real hand-off preparation: flag + chapter transport quiesce
	# This calls the production `_check_chapter_handoff()` (not a reimplementation)
	# and proves G's `begin_handoff()` is actually reached from the merged stage.
	var flow: Node = stage.get("flow")
	var coop: Node = stage.get("coop")
	if flow == null or coop == null:
		check(false, "handoff_nodes_present", {"flow": flow != null, "coop": coop != null})
	else:
		stage.set("_chapter_handoff_started", false)
		flow.set("phase", "done")
		stage.call("_check_chapter_handoff", 0.0)
		check(bool(stage.get("_chapter_handoff_started")), "handoff_flag_set",
			{"phase": str(flow.get("phase"))})
		check(bool(coop.get("_handoff_closing")), "handoff_quiesces_transport",
			{"mode": str(coop.get("mode")), "closing": bool(coop.get("_handoff_closing"))})

	_finish()
