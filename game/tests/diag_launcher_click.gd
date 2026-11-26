extends SceneTree

## R6A diagnostic v2: measure headless window/canvas sizes, compute the correct
## window-space click point for the Launcher button, push a REAL mouse click,
## and verify the scene really switches to Act01. Quits promptly either way.

func _initialize() -> void:
	_watchdog.call_deferred()
	_run.call_deferred()


func _watchdog() -> void:
	await create_timer(90.0).timeout
	push_error("DIAG WATCHDOG TIMEOUT")
	quit(9)


func _run() -> void:
	var guard := 0
	while current_scene == null and guard < 300:
		await physics_frame
		guard += 1
	var launcher: Node = current_scene
	var btn: Button = null
	for i in range(200):
		btn = _find_button("开始单人剧情", launcher)
		if btn != null:
			break
		await create_timer(0.05).timeout
	if btn == null:
		push_error("DIAG button not found")
		quit(2)
		return
	# let the layout pass settle so anchors resolve to real positions
	for i in range(3):
		await physics_frame
	await create_timer(0.2).timeout

	var vp: Window = get_root()
	var canvas_size: Vector2 = vp.get_visible_rect().size
	var window_size: Vector2 = vp.size
	var rect := btn.get_global_rect()
	var canvas_center := rect.get_center()
	var scale := Vector2(window_size.x / canvas_size.x, window_size.y / canvas_size.y)
	var click := Vector2(canvas_center.x * scale.x, canvas_center.y * scale.y)
	print("DIAG window_size=", window_size, " canvas_size=", canvas_size, " scale=", scale)
	print("DIAG global_rect=", rect, " canvas_center=", canvas_center, " click_window=", click)

	var motion := InputEventMouseMotion.new()
	motion.position = click
	motion.global_position = click
	vp.push_input(motion)
	await create_timer(0.10).timeout
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click
	press.global_position = click
	vp.push_input(press)
	await create_timer(0.08).timeout
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click
	release.global_position = click
	vp.push_input(release)

	var guard2 := 0
	while (current_scene == null or str(current_scene.name) != "Act01") and guard2 < 600:
		await physics_frame
		guard2 += 1
	if current_scene != null and str(current_scene.name) == "Act01":
		print("DIAG CLICK_OK entered Act01 at frame ", guard2)
		quit(0)
	else:
		print("DIAG CLICK_MISSED current_scene=", str(current_scene.name if current_scene != null else "null"))
		quit(3)


func _find_button(text: String, from: Node) -> Button:
	if from == null:
		return null
	for n in from.find_children("*", "Button", true, false):
		var b: Button = n as Button
		if b != null and b.text == text:
			return b
	return null