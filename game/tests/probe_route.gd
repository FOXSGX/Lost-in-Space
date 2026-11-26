extends SceneTree
## Route reachability probe: can the player physically walk the critical path?
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/probe_route.gd
##
## Each leg steers with the real camera-relative input map (hold W, aim the
## camera at the next waypoint) and fails if the player is still more than the
## tolerance away after the time budget. This is the check that catches a rock
## or a collider that silently blocks a required route.

const OUT_JSON := "res://evidence/tests/route.json"

var game: Node
var player: EchoPlayer
var checks: Array[Dictionary] = []
var lines: PackedStringArray = []


func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run()


func _run() -> void:
	await create_timer(1.2).timeout
	player = game.player
	await create_timer(0.4).timeout

	var legs: Array[Array] = [
		["spawn -> hammer console", Vector3(0.0, 0.2, 6.0), Vector3(2.6, 0.2, -0.6), 7.0, 1.1],
		["hammer -> freight stair foot", Vector3(2.6, 0.2, -0.6), Vector3(-1.6, 0.2, 3.8), 8.0, 1.2],
		["stair foot -> east loading dock", Vector3(-1.6, 0.2, 3.8), Vector3(-5.6, 2.6, 3.8), 10.0, 1.2],
		["east dock -> platform berth", Vector3(-5.6, 2.6, 3.8), Vector3(-8.8, 2.6, 3.0), 5.0, 1.0],
		["far dock -> crystal socket", Vector3(-17.2, 2.6, 1.2), Vector3(-17.2, 2.6, 2.8), 5.0, 0.45],
		["maintenance floor -> pit ramp base", Vector3(-8.65, -3.2, 6.8), Vector3(-8.65, -3.16, 7.05), 4.0, 0.45],
		["pit ramp -> cave floor", Vector3(-8.65, -3.16, 7.05), Vector3(-8.65, 0.2, 3.0), 8.0, 1.1],
		["B1 -> crystal B", Vector3(-11.8, 0.2, -10.4), Vector3(-16.8, 0.2, -12.5), 8.0, 1.4],
		["crystal B -> ramp approach", Vector3(-16.8, 0.2, -12.5), Vector3(-18.0, 0.2, -13.4), 6.0, 1.3],
		["ramp approach -> observation ledge", Vector3(-18.0, 0.2, -13.4), Vector3(-11.8, 3.4, -19.6), 9.0, 1.6],
		["ledge -> hammer console", Vector3(-11.8, 3.4, -19.6), Vector3(2.6, 0.2, -0.6), 18.0, 1.6],
		["hammer -> north walkway", Vector3(2.6, 0.2, -0.6), Vector3(4.9, 0.2, -4.4), 7.0, 1.4],
		["north walkway -> east crystal aisle", Vector3(4.9, 0.2, -4.4), Vector3(2.0, 0.2, -8.2), 6.0, 1.4],
		["crystal aisle -> gate approach", Vector3(2.0, 0.2, -8.2), Vector3(2.2, 0.2, -24.4), 11.0, 1.6],
	]
	for leg: Array in legs:
		var label: String = str(leg[0])
		var start: Vector3 = leg[1] as Vector3
		var target: Vector3 = leg[2] as Vector3
		var budget: float = float(leg[3])
		var tolerance: float = float(leg[4])
		player.teleport(start, 0.0)
		await create_timer(0.35).timeout
		var arrived: bool = await _walk_to(target, budget, tolerance)
		var distance: float = player.global_position.distance_to(target)
		_check(label, arrived, "distance to target %.2f m, ended at %s" % [distance, str(player.global_position)])

	_finish()


func _walk_to(target: Vector3, budget: float, tolerance: float) -> bool:
	var elapsed: float = 0.0
	var stuck_time: float = 0.0
	var last: Vector3 = player.global_position
	while elapsed < budget:
		var flat: Vector3 = target - player.global_position
		flat.y = 0.0
		var height_ok: bool = absf(player.global_position.y - target.y) < 1.0
		if flat.length() <= tolerance and height_ok:
			Input.action_release("move_forward")
			return true
		player.aim_camera_at(player.global_position + flat, -0.10)
		Input.action_press("move_forward")
		await physics_frame
		elapsed += 1.0 / 60.0
		if player.global_position.distance_to(last) < 0.004:
			stuck_time += 1.0 / 60.0
			if stuck_time > 1.2:
				break
		else:
			stuck_time = 0.0
			last = player.global_position
	Input.action_release("move_forward")
	await create_timer(0.15).timeout
	return player.global_position.distance_to(target) <= tolerance + 0.5 and absf(player.global_position.y - target.y) < 1.2


func _check(label: String, ok: bool, detail: String) -> void:
	checks.append({"check": label, "ok": ok, "detail": detail})
	var line: String = "%s %s | %s" % ["PASS" if ok else "FAIL", label, detail]
	lines.append(line)
	print(line)


func _finish() -> void:
	var passed: int = 0
	for entry: Dictionary in checks:
		if bool(entry["ok"]):
			passed += 1
	var summary: Dictionary = {"total": checks.size(), "passed": passed, "failed": checks.size() - passed, "checks": checks}
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT_JSON), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "  "))
		file.close()
	print("ROUTE_RESULT %d/%d passed, %d failed" % [passed, checks.size(), checks.size() - passed])
	quit(0 if passed == checks.size() else 1)
