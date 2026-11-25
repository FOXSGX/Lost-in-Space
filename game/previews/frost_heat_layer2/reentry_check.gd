extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	change_scene_to_file("res://previews/frost_heat_layer2/preview.tscn")
	for index: int in 20:
		await process_frame
	var old_scene: Main3D = current_scene as Main3D
	old_scene.melt = 1.0
	old_scene._apply_thaw()
	old_scene.shortcut_open = true
	old_scene.walker.health = 2
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_F5
	key.keycode = KEY_F5
	key.pressed = true
	Input.parse_input_event(key)
	for index: int in 30:
		await process_frame
	var fresh: Main3D = current_scene as Main3D
	var ok: bool = fresh!=null and fresh!=old_scene and fresh.melt==0 and not fresh.heating and not fresh.shortcut_open and fresh.walker.health==5 and fresh._items.has_jet(1)
	for part: Dictionary in fresh.ice_parts:
		ok = ok and (part.body as StaticBody3D).collision_layer==2 and (part.body.get_child(0) as MeshInstance3D).visible
	print("FROST_HEAT_REENTRY_PASSED" if ok else "FROST_HEAT_REENTRY_FAILED")
	quit(0 if ok else 1)
