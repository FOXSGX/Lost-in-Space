extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	change_scene_to_file("res://previews/frost_open_layer1/preview.tscn")
	for index: int in 20:
		await process_frame
	var old_scene: Main3D = current_scene as Main3D
	old_scene.entered = true
	old_scene.shortcut_open = true
	old_scene.walker.health = 2
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_F5
	event.keycode = KEY_F5
	event.pressed = true
	Input.parse_input_event(event)
	for index: int in 30:
		await process_frame
	var fresh: Main3D = current_scene as Main3D
	var ok: bool = fresh != null and fresh != old_scene and fresh.walker.health==5 and not fresh.shortcut_open and not fresh.entered and fresh.walker.position.distance_to(Vector3(0,0,48))<0.2 and fresh._items.has_jet(1)
	print("FROST_OPEN_REENTRY_PASSED" if ok else "FROST_OPEN_REENTRY_FAILED")
	quit(0 if ok else 1)
