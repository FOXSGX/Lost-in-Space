extends SceneTree

## Act4 exit-gate state-machine regression (audit R-01 / R-19).
##
## Proves the two behaviours that used to soft-lock the exit:
##   A. A gate that is caught mid-travel by close_gate() (someone standing in
##      the doorway) keeps a state derived from its REAL height, so it can be
##      re-driven and eventually reports exit_allowed.
##   B. A gate that is already closing reverses to "opening" as soon as a body
##      enters the doorway, instead of pressing 850 kg onto the player.
##
## Run: godot --headless --path game --script res://tests/act4_gate_state.gd

var app: Node3D
var gate: ExitGate
var player: EchoPlayer
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("GATE_STATE ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func run() -> void:
	var scene: PackedScene = load("res://scenes/act4.tscn") as PackedScene
	app = scene.instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(60)
	gate = app.get("gate") as ExitGate
	player = app.get("player") as EchoPlayer
	check(gate != null, "gate resolved")
	check(player != null, "player resolved")
	if gate == null or player == null:
		quit(1)
		return

	var doorway: Area3D = gate.get("_doorway") as Area3D
	check(doorway != null, "doorway sensor resolved")
	if doorway == null:
		quit(1)
		return

	# Park the player far from the doorway for the "nobody there" phases.
	var away: Vector3 = doorway.global_position + Vector3(0.0, 0.0, 12.0)

	# ---- phase A: mid-travel close with a body in the doorway --------------
	gate.unlock("gate_state_probe")
	gate.open()
	var guard: int = 0
	while gate.height < 1.60 and guard < 400:
		await physics_frame
		guard += 1
	var h_mid: float = gate.height
	check(h_mid >= 1.40, "gate reached mid travel before the doorway block", {"height": h_mid})

	player.global_position = doorway.global_position
	player.velocity = Vector3.ZERO
	await frames(8)
	gate.close_gate()
	var state_after: String = str(gate.get("_state"))
	check(state_after == "opening", "mid-travel close keeps the gate drivable", {
		"state": state_after, "height": gate.height,
	})
	var h_before_more: float = gate.height
	await frames(45)
	check(gate.height > h_before_more + 0.20, "gate kept rising after the refused close", {
		"from": h_before_more, "to": gate.height,
	})

	# ---- phase B: clear the doorway, let the gate finish -------------------
	player.global_position = away
	player.velocity = Vector3.ZERO
	await frames(8)
	guard = 0
	while (not gate.exit_allowed) and guard < 900:
		await physics_frame
		guard += 1
	check(gate.exit_allowed, "exit becomes usable after re-driving the gate", {
		"height": gate.height, "state": str(gate.get("_state")),
		"hold": str(gate.get("hold_mode")), "frames": guard,
	})

	# ---- phase C: a closing gate reverses when a body walks in -------------
	gate.close_gate()
	guard = 0
	while gate.height > 2.20 and guard < 900:
		await physics_frame
		guard += 1
	check(str(gate.get("_state")) == "closing", "gate is closing", {
		"state": str(gate.get("_state")), "height": gate.height,
	})
	player.global_position = doorway.global_position
	player.velocity = Vector3.ZERO
	await frames(10)
	check(str(gate.get("_state")) == "opening", "closing gate reverses for a body in the doorway", {
		"state": str(gate.get("_state")), "height": gate.height,
	})
	var h_reverse: float = gate.height
	await frames(45)
	check(gate.height > h_reverse + 0.15, "reversed gate actually rises", {
		"from": h_reverse, "to": gate.height,
	})

	print("ACT4_GATE_STATE_REPORT ", JSON.stringify({
		"checks": checks, "failures": failures, "ok": failures == 0,
	}))
	quit(0 if failures == 0 else 1)
