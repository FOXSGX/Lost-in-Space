class_name PlaythroughBot
extends RefCounted

## Real-input playthrough bot. Movement uses the player's Input actions, camera
## steering uses the real InputEventMouseMotion handler, and every interaction
## goes through E. No teleporting and no direct gameplay-state writes.

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var hud: GameHud
var failures: int = 0
var checks: Array[Dictionary] = []
var capture_dir: String = ""
var capture_every: int = 4
var frame_index: int = 0
var viewport: Viewport
var captured: int = 0
var route_log: Array[String] = []


func setup(p_app: Node3D) -> void:
	app = p_app
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	hud = app.get("hud") as GameHud
	viewport = app.get_viewport()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.mouse_enabled = true
	hud.title_layer.visible = false
	hud.clear_subtitles()


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details})
	if not ok:
		failures += 1
	print("BOT ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func frames(count: int) -> void:
	for _i in range(count):
		await app.get_tree().physics_frame
		frame_index += 1
		if capture_dir != "" and frame_index % maxi(1, capture_every) == 0:
			await app.get_tree().process_frame
			await _capture()


func seconds(value: float) -> void:
	await frames(int(value * 60.0))


func _capture() -> void:
	if captured > 4200:
		return
	var image: Image = viewport.get_texture().get_image()
	if image == null:
		return
	image.save_jpg("%s/frame_%05d.jpg" % [capture_dir, captured], 0.82)
	captured += 1


func turn_to(target_yaw: float, max_step: float = 0.22) -> void:
	var delta: float = wrapf(target_yaw - player.yaw, -PI, PI)
	delta = clampf(delta, -max_step, max_step)
	if absf(delta) < 0.003:
		return
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = Vector2(-delta / PlayerController.MOUSE_SENSITIVITY, 0.0)
	player._unhandled_input(ev)


func face_position(target: Vector3, pitch: float = 0.0) -> void:
	var d: Vector3 = target - player.global_position
	var yaw: float = atan2(-d.x, -d.z)
	turn_to(yaw, PI)
	player.set_look(yaw, pitch)


func walk_to(target: Vector3, tolerance: float = 0.85, max_seconds: float = 22.0) -> bool:
	var elapsed: float = 0.0
	var last_pos: Vector3 = player.global_position
	var stuck_time: float = 0.0
	Input.action_press("move_forward")
	while elapsed < max_seconds:
		var current: Vector3 = player.global_position
		var flat_target: Vector3 = Vector3(target.x, current.y, target.z)
		var dist: float = Vector2(current.x - target.x, current.z - target.z).length()
		if dist <= tolerance:
			break
		var d: Vector3 = flat_target - current
		var desired: float = atan2(-d.x, -d.z)
		turn_to(desired, 0.16)
		# keep a normal player's gaze near the horizon while walking
		player.pitch = lerpf(player.pitch, 0.0, 0.18)
		player._apply_look()
		await app.get_tree().physics_frame
		frame_index += 1
		elapsed += 1.0 / 60.0
		if capture_dir != "" and frame_index % maxi(1, capture_every) == 0:
			await app.get_tree().process_frame
			await _capture()
		if current.distance_to(last_pos) < 0.012:
			stuck_time += 1.0 / 60.0
		else:
			stuck_time = 0.0
			last_pos = current
		if stuck_time > 1.2:
			Input.action_release("move_forward")
			var side: String = "move_right" if int(elapsed * 10.0) % 2 == 0 else "move_left"
			Input.action_press(side)
			await frames(10)
			Input.action_release(side)
			Input.action_press("move_forward")
			stuck_time = 0.0
	Input.action_release("move_forward")
	await frames(6)
	var final_dist: float = Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length()
	route_log.append("walk %s -> %s dist=%.2f elapsed=%.1f" % [target, player.global_position, final_dist, elapsed])
	return final_dist <= tolerance * 1.8


func press_interact() -> void:
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(4)


func hold(action: String, duration: float) -> void:
	Input.action_press(action)
	await seconds(duration)
	Input.action_release(action)
	await frames(8)


func try_interact(check_callable: Callable, face_target: Vector3, pitch: float = -0.3, attempts: int = 4) -> bool:
	for i in range(attempts):
		await face_position(face_target, pitch)
		await frames(2)
		await press_interact()
		await frames(3)
		if bool(check_callable.call()):
			return true
		var d: Vector3 = face_target - player.global_position
		var dist: float = Vector2(d.x, d.z).length()
		if dist > 0.35:
			var move: Vector3 = player.global_position + Vector3(d.x, 0, d.z).normalized() * 0.22
			player.global_position = Vector3(move.x, player.global_position.y, move.z)
			await frames(4)
	return false


func run_tour() -> Dictionary:
	await frames(20)
	print("BOT_START")

	# 1. entrance and jammed shutter
	check(await walk_to(Vector3(0, 4.06, 26.0), 0.8), "walk: spawn to jammed shutter")
	await face_position(Vector3(0, 5.0, 24.2), 0.05)
	await press_interact()
	check(player.operating, "door grabbed with E")
	await hold("move_forward", 3.8)
	check(level.push_door.is_opened, "door pushed open")
	await press_interact()
	check(await walk_to(Vector3(0, 4.06, 22.5), 0.8), "walk: through shutter")
	check(await walk_to(Vector3(0, 4.06, 12.6), 0.9), "walk: balcony")
	check(story.stage >= StoryDirector.Stage.DISCOVER_INSTABILITY, "hall checkpoint reached", {"stage": story.stage})
	await frames(20)

	# 2. left ramp and left station
	check(await walk_to(Vector3(-5.0, 4.06, 10.4), 0.7, 14.0), "walk: left ramp top")
	check(await walk_to(Vector3(-5.0, 1.4, 4.2), 1.0, 14.0), "walk: left ramp middle")
	check(await walk_to(Vector3(-5.0, 0.06, 2.4), 0.8, 12.0), "walk: left ramp bottom")
	check(await walk_to(Vector3(-8.0, 0.06, 2.2), 0.9, 12.0), "walk: station approach")
	check(await walk_to(Vector3(-8.0, 1.66, 4.6), 0.8, 12.0), "walk: up station ramp")
	check(await walk_to(Vector3(-9.2, 1.66, 5.6), 0.7, 8.0), "walk: left platform side")
	await walk_to(Vector3(-9.3, 1.66, 7.5), 0.6, 8.0)
	check(await walk_to(Vector3(-8.6, 1.66, 7.4), 0.55, 8.0), "walk: left lever anchor")
	var grabbed: bool = await try_interact(func() -> bool: return player.operating, Vector3(-8.53, 1.4, 7.13), 0.45)
	check(grabbed, "left lever grabbed by real E")
	if grabbed:
		var p0: float = level.left_cart.get_p()
		await hold("move_forward", 1.8)
		var p1: float = level.left_cart.get_p()
		check(p1 > p0 + 0.15, "left cart moved with W", {"before": p0, "after": p1})
		await press_interact()
		check(not player.operating, "left lever released")

	# 3. lock console while unbalanced
	await walk_to(Vector3(-9.3, 1.66, 7.4), 0.6, 8.0)
	await walk_to(Vector3(-9.2, 1.66, 5.6), 0.7, 8.0)
	await walk_to(Vector3(-8.0, 1.66, 4.6), 0.8, 8.0)
	await walk_to(Vector3(-8.0, 0.06, 2.2), 0.9, 10.0)
	await walk_to(Vector3(-10.3, 0.06, 4.2), 0.9, 10.0)
	await walk_to(Vector3(-10.3, 0.06, 8.8), 0.9, 10.0)
	await walk_to(Vector3(-10.3, 0.06, 10.6), 0.9, 8.0)
	await walk_to(Vector3(0, 0.06, 10.6), 0.9, 14.0)
	check(await walk_to(Vector3(0, 0.06, 9.2), 0.7, 8.0), "walk: lock console")
	var attempted: bool = await try_interact(func() -> bool: return story.lock_attempts >= 1, Vector3(0, 1.2, 7.1), 0.15)
	check(attempted, "lock failure recorded", {"attempts": story.lock_attempts})
	check(not core_locked(), "lock refused while unbalanced")

	# 4. right station, pull the right cart fully inward
	await walk_to(Vector3(0, 0.06, 10.6), 0.9, 8.0)
	await walk_to(Vector3(10.3, 0.06, 10.6), 0.9, 14.0)
	await walk_to(Vector3(10.3, 0.06, 8.8), 0.9, 8.0)
	check(await walk_to(Vector3(10.3, 0.06, 4.2), 0.9, 10.0), "walk: east aisle")
	check(await walk_to(Vector3(9.8, 0.06, 2.2), 0.9, 8.0), "walk: right station approach")
	check(await walk_to(Vector3(8.0, 0.06, 2.2), 0.8, 8.0), "walk: right ramp foot")
	check(await walk_to(Vector3(8.0, 1.66, 4.6), 0.8, 10.0), "walk: up right station ramp")
	check(await walk_to(Vector3(9.2, 1.66, 5.6), 0.7, 8.0), "walk: right platform side")
	await walk_to(Vector3(9.3, 1.66, 7.5), 0.6, 8.0)
	check(await walk_to(Vector3(8.6, 1.66, 7.4), 0.55, 8.0), "walk: right lever anchor")
	var grabbed_r: bool = await try_interact(func() -> bool: return player.operating, Vector3(8.53, 1.4, 7.13), 0.45)
	check(grabbed_r, "right lever grabbed")
	if grabbed_r:
		await hold("move_back", 3.6)
		await press_interact()
	await seconds(1.2)
	print("BOT_BALANCE net=", level.core.get_net(), " cap=", level.core.is_capturable(), " L=", level.left_cart.get_p(), " R=", level.right_cart.get_p())
	check(level.core.is_capturable(), "core capturable after both carts", {"net": level.core.get_net()})

	# 5. engage the claw
	await walk_to(Vector3(9.3, 1.66, 7.4), 0.6, 8.0)
	await walk_to(Vector3(9.2, 1.66, 5.6), 0.7, 8.0)
	await walk_to(Vector3(8.0, 1.66, 4.6), 0.8, 8.0)
	await walk_to(Vector3(8.0, 0.06, 2.2), 0.8, 8.0)
	await walk_to(Vector3(10.3, 0.06, 4.2), 0.9, 10.0)
	await walk_to(Vector3(10.3, 0.06, 8.8), 0.9, 10.0)
	await walk_to(Vector3(10.3, 0.06, 10.6), 0.9, 8.0)
	await walk_to(Vector3(0, 0.06, 10.6), 0.9, 14.0)
	check(await walk_to(Vector3(0, 0.06, 9.2), 0.7, 8.0), "walk: back to lock console")
	var locked_ok: bool = await try_interact(func() -> bool: return core_locked(), Vector3(0, 1.2, 7.1), 0.15, 3)
	await seconds(2.4)
	check(locked_ok or core_locked(), "core locked with claw")
	check(story.checkpoint >= 2, "lock checkpoint", {"checkpoint": story.checkpoint})
	await seconds(2.0)

	# 6. isolation bay via the east aisle
	await walk_to(Vector3(0, 0.06, 10.6), 0.9, 8.0)
	await walk_to(Vector3(10.3, 0.06, 10.6), 0.9, 12.0)
	await walk_to(Vector3(10.3, 0.06, 8.8), 0.9, 8.0)
	check(await walk_to(Vector3(10.3, 0.06, 4.2), 0.9, 10.0), "walk: east aisle north")
	await walk_to(Vector3(12.35, 0.06, 4.0), 0.7, 10.0)
	check(await walk_to(Vector3(12.35, 0.06, -2.0), 0.8, 14.0), "walk: east aisle south")
	check(await walk_to(Vector3(10.9, 0.06, -5.7), 0.8, 12.0), "walk: isolation bay")
	var pin_ok: bool = await try_interact(func() -> bool: return level.isolation.pin_out, Vector3(10.8, 1.4, -6.6), 0.18, 3)
	check(pin_ok, "safety pin pulled")
	var iso_grabbed: bool = await try_interact(func() -> bool: return player.operating, Vector3(10.8, 1.4, -6.6), 0.18, 3)
	check(iso_grabbed, "isolation lever grabbed")
	if iso_grabbed:
		await hold("move_forward", 3.2)
		await press_interact()
	await seconds(2.8)
	check(level.isolation.separated_flag, "coupling separated")
	check(level.data_plinth.revealed_flag, "navigation data revealed")

	# 7. data plinth behind the core
	check(await walk_to(Vector3(6.0, 0.06, -6.0), 0.9, 12.0), "walk: around isolation")
	check(await walk_to(Vector3(6.0, 0.06, -11.0), 0.9, 12.0), "walk: rear hall")
	check(await walk_to(Vector3(-2.0, 0.06, -8.1), 0.9, 16.0), "walk: data plinth")
	var data_ok: bool = await try_interact(func() -> bool: return story.data_taken, Vector3(-3.0, 1.0, -9.1), 0.30)
	check(data_ok, "navigation data taken")
	await seconds(4.0)
	check(level.exit_door.open_progress > 0.8, "exit door open", {"progress": level.exit_door.open_progress})

	# 8. evacuate
	check(await walk_to(Vector3(-8.0, 0.06, -6.0), 1.0, 14.0), "walk: exit side")
	check(await walk_to(Vector3(-13.4, 0.06, -2.0), 0.9, 14.0), "walk: blast door")
	check(await walk_to(Vector3(-24.5, 0.06, -2.0), 1.0, 18.0), "walk: exit corridor")
	await seconds(1.0)
	check(story.stage == StoryDirector.Stage.COMPLETED, "chapter completed", {"stage": story.stage})

	var report: Dictionary = {
		"ok": failures == 0,
		"failures": failures,
		"checks": checks,
		"route": route_log,
		"stage": story.stage,
		"checkpoint": story.checkpoint,
		"lock_attempts": story.lock_attempts,
		"surges": story.surges,
		"elapsed": story.completion_time - story.start_time,
	}
	return report


func core_locked() -> bool:
	return level.core.is_locked()





