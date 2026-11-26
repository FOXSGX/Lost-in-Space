extends SceneTree

## R2 diagnostic only (NOT acceptance evidence): reproduces the Act05 level
## layout obstacles found while authoring the real-input routes. Uses test-only
## teleports to put the body next to each obstacle, then walks with real input
## and reports the exact collider from PlayerController's F3 block audit.

var player: Node = null
var level: Node = null

func _initialize() -> void:
	_run.call_deferred()


func _face(target: Vector3) -> void:
	var d: Vector3 = target - (player.global_position as Vector3)
	player.call("set_look", atan2(-d.x, -d.z), clampf(-atan2(d.y - 1.45, maxf(Vector2(d.x, d.z).length(), 0.05)), -1.1, 1.1))


func _walk(target: Vector3, seconds: float, tol: float, label: String) -> bool:
	var t := 0.0
	var last: Vector3 = player.global_position
	var stuck := 0.0
	_face(target)
	Input.action_press("move_forward")
	while t < seconds:
		await physics_frame
		t += 1.0 / 60.0
		var cur: Vector3 = player.global_position
		_face(Vector3(target.x, cur.y, target.z))
		if Vector2(cur.x - target.x, cur.z - target.z).length() <= tol:
			break
		if cur.distance_to(last) < 0.012:
			stuck += 1.0 / 60.0
		else:
			stuck = 0.0
			last = cur
		if stuck > 1.0:
			break
	Input.action_release("move_forward")
	await physics_frame
	var dist := Vector2((player.global_position as Vector3).x - target.x, (player.global_position as Vector3).z - target.z).length()
	print("WALK ", label, " pos=", (player.global_position as Vector3).snapped(Vector3(0.01, 0.01, 0.01)), " dist=", "%.2f" % dist)
	if dist > tol:
		print("BLOCK ", label, " ", player.call("get_block_text"))
		return false
	return true


func _teleport(pos: Vector3, label: String) -> void:
	player.call("teleport", pos, 0.0)
	await create_timer(0.4).timeout
	print("TELEPORT ", label, " pos=", player.global_position)


func _run() -> void:
	await process_frame
	var hub: Node = root.get_node_or_null("/root/SessionHub")
	hub.set("chapter_progress", {"completed": true, "probe": "r2_layout"})
	hub.set("pending_spawn", {"chapter": "resonance_04", "completed": true, "from_act4": true})
	change_scene_to_file("res://scenes/main.tscn")
	var guard := 0
	while current_scene == null and guard < 300:
		await process_frame
		guard += 1
	await create_timer(1.0).timeout
	var game: Node = current_scene
	player = game.get("player")
	level = game.get("level")

	print("DEFECT_A east balcony ramp vs crew duty board")
	await _teleport(Vector3(4.2, 4.0, 10.4), "east ramp top")
	await _walk(Vector3(4.2, 0.0, 1.5), 10.0, 0.8, "east ramp descent")
	print("DEFECT_A_END y=", player.global_position.y, " pos=", player.global_position)

	print("DEFECT_B catwalk free end / landing step")
	await _teleport(Vector3(-7.85, 3.42, -3.15), "ladder landing")
	await _walk(Vector3(-7.0, 3.4, -4.0), 4.0, 0.6, "landing to deck free end")
	print("DEFECT_B_END y=", player.global_position.y, " pos=", player.global_position)
	# Jump east from the deck free end (normal jump input) and report where it lands.
	await _teleport(Vector3(-8.7, 3.47, -3.85), "deck free end")
	_face(Vector3(-7.0, 3.47, -3.85))
	Input.action_press("move_forward")
	await create_timer(0.25).timeout
	Input.action_press("jump")
	await create_timer(0.20).timeout
	Input.action_release("jump")
	await create_timer(1.6).timeout
	Input.action_release("move_forward")
	await create_timer(0.8).timeout
	print("DEFECT_B_JUMP pos=", player.global_position, " block=", player.call("get_block_text"))

	print("DEFECT_C west counterweight station exit vs console")
	await _teleport(Vector3(-8.5, 1.6, 7.466), "west counterweight anchor")
	await _walk(Vector3(-8.0, 0.0, 2.4), 8.0, 0.8, "station direct ramp exit")
	print("DEFECT_C_END y=", player.global_position.y, " pos=", player.global_position)

	print("DEFECT_D isolation bed west approach vs carriage end stop")
	await _teleport(Vector3(6.8, 0.0, -9.6), "south of isolation")
	await _walk(Vector3(8.3, 0.0, -9.6), 5.0, 0.6, "east past end stop")
	print("DEFECT_D_END pos=", player.global_position)

	quit(0)
