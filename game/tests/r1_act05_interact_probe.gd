extends SceneTree

## R1 solo interaction-priority probe for the Act05 maintenance ladder / rail /
## lock. Direct Main scene, real E key. Diagnostics only.

var log_lines: Array[String] = []
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func log_line(text: String) -> void:
	print("[solo] " + text)
	log_lines.append(text)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _face(pos: Vector3) -> void:
	var p: Node3D = current_scene.get("player") as Node3D
	var d: Vector3 = pos - p.global_position
	var yaw: float = atan2(-d.x, -d.z)
	var flat: float = Vector2(d.x, d.z).length()
	var pitch: float = -atan2(d.y - 1.45, maxf(flat, 0.05))
	p.call("set_look", yaw, clampf(pitch, -1.1, 1.1))


func _press() -> void:
	Input.action_press("interact")
	await _wait(0.12)
	Input.action_release("interact")
	await _wait(0.35)


func _state(label: String) -> void:
	var game := current_scene
	var p: Node3D = game.get("player") as Node3D
	var t: Variant = p.get("operate_target")
	var target_name: String = "null"
	if t is Node and is_instance_valid(t):
		target_name = str((t as Node).name)
	var session: Node = game.get("session")
	log_line("%s y=%.2f op=%s target=%s machine=%s grabbing=%s ext_hold=%s prompt='%s' pos=%s" % [
		label, p.global_position.y, str(bool(p.get("operating"))), target_name,
		str(session.get("local_operating_machine")) if session != null else "?",
		str(bool(p.get("grabbing"))), str(bool(p.get("external_hold"))),
		str(p.call("get", "current_prompt")), str(p.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])


func _stop() -> void:
	var p: Node3D = current_scene.get("player") as Node3D
	if bool(p.get("operating")):
		p.call("stop_operating")
	p.set("external_hold", false)
	if bool(p.get("grabbing")):
		p.call("stop_grab")
	await _wait(0.3)


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 600:
		await process_frame
		guard += 1
	await _wait(1.5)
	var game := current_scene
	if game == null or str(game.name) != "Main":
		log_line("FAIL wrong scene")
		_finish()
		return
	var level: Node = game.get("level")
	var p: Node3D = game.get("player") as Node3D
	var catwalk: Node = level.get("catwalk")
	var station: Node3D = catwalk.get("ladder_station_node") as Node3D
	var stand: Vector3 = Vector3(station.global_position.x, 0.06, station.global_position.z + 0.9)
	var ladder_center: Vector3 = Vector3(station.global_position.x, 1.35, station.global_position.z - 1.2)

	# Case A: look at the physical ladder (north), start the climb, then cancel
	# with E. Before R1 the climb set external_hold, and _handle_interact
	# checked external_hold first, so E could not release the body.
	p.call("teleport", stand, 0.0)
	await _wait(0.4)
	_face(ladder_center)
	await _wait(0.3)
	_state("A_BEFORE")
	await _press()
	_state("A_AFTER_CLIMB_START")
	if not bool(p.get("operating")):
		failures += 1
		log_line("FAIL aiming at the ladder did not start the climb")
	await _press()
	_state("A_AFTER_E_CANCEL")
	if bool(p.get("operating")) or bool(p.get("external_hold")):
		failures += 1
		log_line("FAIL E did not cancel the caged-ladder climb")
	await _stop()

	# Case C: on the deck, look at a grab rail.
	var grips: Array = catwalk.get("grab_points") as Array
	var grip: Node3D = grips[1] as Node3D
	var grip_pos: Vector3 = grip.global_position
	p.call("teleport", Vector3(grip_pos.x, 3.46, grip_pos.z - 0.75), 0.0)
	await _wait(0.5)
	_face(grip_pos)
	await _wait(0.3)
	_state("C_BEFORE")
	await _press()
	_state("C_AFTER_GRAB")
	if not bool(p.get("grabbing")):
		failures += 1
		log_line("FAIL aiming at a grab rail did not grab it")
	await _stop()

	# Case D1: stand on the hall floor under the deck and aim at the deck lock.
	# The old nearest-station scan reached it and teleported the body onto the
	# catwalk; that is the free-way-up the R1 station zones must close.
	var lock_station: Node3D = catwalk.get("lock_station_node") as Node3D
	var lock_pos: Vector3 = lock_station.global_position
	p.call("teleport", Vector3(lock_pos.x, 0.06, lock_pos.z + 1.4), 0.0)
	await _wait(0.5)
	_face(lock_pos)
	await _wait(0.3)
	_state("D1_BEFORE_FLOOR_LOCK")
	await _press()
	_state("D1_AFTER_FLOOR_LOCK")
	if bool(p.get("operating")) or p.global_position.y > 1.0:
		failures += 1
		log_line("FAIL floor-level E at the deck lock teleported the body onto the catwalk")
	await _stop()

	# Case D2: stand on the deck next to the lock and use it for real.
	p.call("teleport", Vector3(lock_pos.x, 3.50, lock_pos.z + 0.20), 0.0)
	await _wait(0.5)
	_face(lock_pos + Vector3(0, -0.3, 0))
	await _wait(0.3)
	_state("D2_BEFORE_DECK_LOCK")
	await _press()
	_state("D2_AFTER_DECK_LOCK")
	if str(game.get("session").get("local_operating_machine")) != "catwalk_lock":
		failures += 1
		log_line("FAIL deck-level E at the maintenance lock did not start the lock work")
	await _stop()
	_finish()


func _finish() -> void:
	var payload := {"probe": "r1_act05_interact_probe.gd", "failures": failures, "log": log_lines}
	var dir: String = ProjectSettings.globalize_path("res://evidence/tests")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("r1_act05_interact.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "  "))
		f.close()
	quit(0 if failures == 0 else 1)
