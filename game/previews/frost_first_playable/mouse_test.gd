extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i: int in count:
		await process_frame

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func motion() -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = Vector2(120, 65)
	Input.parse_input_event(event)

func escape() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventAction.new()
	event.action = "ui_cancel"
	Input.parse_input_event(event)

func run() -> void:
	var a: Node3D = load("res://previews/frost_first_playable/adventure.tscn").instantiate()
	root.add_child(a)
	a.start_session(false)
	await frames(20)
	var p: Node3D = a.players[1]
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "spawn captures mouse after camera construction")
	var old_rotation: Vector3 = p._camera.global_rotation
	motion()
	await frames(30)
	check(absf(p._camera.global_rotation.y-old_rotation.y)>0.1, "mouse motion turns camera yaw")
	check(absf(p._camera.global_rotation.x-old_rotation.x)>0.05, "mouse motion turns camera pitch")
	check(p._camera.global_position.distance_to(p.global_position+Vector3.UP*p.SHIP_EYE_HEIGHT)<0.1, "camera remains at first-person eye")
	escape()
	await frames(3)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape releases cursor")
	var paused_yaw: float = p._camera_yaw_target
	motion()
	await frames(3)
	check(p._camera_yaw_target==paused_yaw, "released cursor does not turn camera")
	escape()
	await frames(3)
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Escape resumes capture")
	motion()
	await frames(10)
	check(p._camera_yaw_target!=paused_yaw, "resumed mouse turns view")
	a.spawn_actor(2,false)
	await frames(3)
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "remote actor does not release local cursor")
	print("MOUSE_RESULT failures=",failures)
	a.queue_free()
	await frames(3)
	quit(failures)
