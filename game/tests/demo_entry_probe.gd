extends SceneTree

## Menu acceptance probe: injects the same mouse press/release path a user uses
## on the demo button, then verifies the real scene transition to Act23.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var launcher_scene: PackedScene = load("res://demo/demo_launcher.tscn") as PackedScene
	var launcher: Node = launcher_scene.instantiate()
	root.add_child(launcher)
	current_scene = launcher
	await create_timer(0.8).timeout
	var button: Button = null
	for node: Node in launcher.find_children("*", "Button", true, false):
		var candidate: Button = node as Button
		if candidate != null and candidate.text == "开始演示 · 单人":
			button = candidate
			break
	if button == null:
		push_error("DEMO_ENTRY_BUTTON_MISSING")
		quit(1)
		return
	var viewport: Window = root
	var rect: Rect2 = button.get_global_rect()
	var canvas_size: Vector2 = viewport.get_visible_rect().size
	var window_size: Vector2 = viewport.size
	var scale: Vector2 = Vector2(window_size.x / canvas_size.x, window_size.y / canvas_size.y)
	var point: Vector2 = rect.get_center() * scale
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion)
	await create_timer(0.08).timeout
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	press.global_position = point
	viewport.push_input(press)
	await create_timer(0.08).timeout
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.global_position = point
	viewport.push_input(release)
	await create_timer(1.4).timeout
	var passed: bool = current_scene != null and str(current_scene.name) == "Act23Chapter"
	print("DEMO_ENTRY_PROBE scene=%s passed=%s" % [
		str(current_scene.name) if current_scene != null else "null", passed])
	quit(0 if passed else 2)
