extends Node

# Scripted third-person demonstration driver.
#
# Used for three deliverables:
#   * the player-view full-playthrough video
#   * the wrong-eye + recovery video
#   * the overshoot + reverse-adjustment video
# and for verifying the exported Windows build with `--demo=...`.
#
# It drives the same Input actions a player uses; it never calls the rail solver
# directly and never teleports during a demonstration (except the reset path,
# which is a real game action).

var mode: String = "full"
var app: Node3D
var player: CharacterBody3D
var rig: Node3D
var hud: CanvasLayer
var output_file: String = ""
var _finished: bool = false

func _ready() -> void:
	app = get_parent() as Node3D
	player = app.get("player") as CharacterBody3D
	rig = app.get("rig") as Node3D
	hud = app.get("hud") as CanvasLayer
	run.call_deferred()

func run() -> void:
	await wait(0.8)
	match mode:
		"wrong_eye":
			await run_wrong_eye()
		"overshoot":
			await run_overshoot()
		"full", "debug":
			await run_full()
		_:
			await run_full()
	_finished = true
	var result: Dictionary = {
		"mode": mode,
		"completed": bool(rig.get("completed")),
		"completions": int(rig.get("completion_count")),
		"state": str(rig.get("mission_state")),
		"angle": float((rig.call("alignment_state") as Dictionary).get("angle_deg", 0.0)),
	}
	print("DEMO_RESULT ", JSON.stringify(result))
	if not output_file.is_empty():
		var file: FileAccess = FileAccess.open(output_file, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "  "))
			file.close()
	await wait(1.0)
	get_tree().quit(0 if bool(result["completed"]) else 1)

# --- scenarios -------------------------------------------------------------

func run_full() -> void:
	await banner("完整通关 · 从断裂轨道到锁定销")
	if mode == "debug":
		await press("toggle_debug", 2)
	await walk_to_anchor("eye_far")
	await pause(0.8)
	await press("interact", 3)
	await pause(1.0)
	await take_console()
	await pause(0.6)
	await look_toward(Vector3(3.4, 0.9, -0.6))
	await haul_until(1.4, 1500)
	await wait(1.6)
	await pause(0.8)
	await leave_console()
	await walk_to_socket()
	await pause(0.8)
	await finish_lock()
	await wait(2.4)

func run_wrong_eye() -> void:
	await banner("错误连接 · 中段吊耳拉不动，换前端吊耳")
	await walk_to_anchor("eye_mid")
	await pause(0.8)
	await press("interact", 3)
	await pause(0.8)
	await take_console()
	await look_toward(Vector3(2.4, 0.9, -0.6))
	Input.action_press("winch_haul")
	await wait(3.4)
	Input.action_release("winch_haul")
	await wait(1.2)
	await pause(0.6)
	await leave_console()
	await press("winch_release", 3)
	await wait(0.8)
	await walk_to_anchor("eye_far")
	await pause(0.6)
	await press("interact", 3)
	await pause(0.8)
	await take_console()
	await look_toward(Vector3(3.4, 0.9, -0.6))
	await haul_until(1.4, 1500)
	await wait(1.6)
	await leave_console()
	await walk_to_socket()
	await pause(0.6)
	await finish_lock()
	await wait(2.2)

func run_overshoot() -> void:
	await banner("过冲与反向调整 · 收过头后用 S 放线")
	await walk_to_anchor("eye_far")
	await pause(0.6)
	await press("interact", 3)
	await pause(0.6)
	await take_console()
	await look_toward(Vector3(3.4, 0.9, -0.6))
	Input.action_press("winch_haul")
	var overshot: bool = false
	for _i: int in range(1200):
		await get_tree().physics_frame
		var angle: float = float((rig.call("alignment_state") as Dictionary).get("angle_deg", 15.0))
		if angle <= -1.5:
			overshot = true
			break
	Input.action_release("winch_haul")
	await wait(1.4)
	await pause(0.6)
	# Pay out until the rail starts swinging back, then hand over to a short
	# bang-bang controller: tap S while it is behind the line, tap W when it is
	# past it. This is the same correction a player makes by watching the nose.
	Input.action_press("winch_payout")
	for _i: int in range(180):
		await get_tree().physics_frame
		if float((rig.call("alignment_state") as Dictionary).get("angle_deg", 0.0)) >= -1.0:
			break
	Input.action_release("winch_payout")
	await recover_into_band()
	await pause(0.6)
	await leave_console()
	await walk_to_socket()
	await pause(0.6)
	await finish_lock()
	await wait(2.2)

func recover_into_band() -> bool:
	for _attempt: int in range(40):
		var info: Dictionary = rig.call("alignment_state") as Dictionary
		var angle: float = float(info.get("angle_deg", 0.0))
		if bool(info.get("lockable", false)):
			return true
		print("DEMO_OVERSHOOT_RECOVER angle=%.2f tension=%.0f" % [
			angle, float((rig.call("tension_state") as Dictionary).get("tension", 0.0)),
		])
		if angle < -1.2:
			if float((rig.call("tension_state") as Dictionary).get("tension", 0.0)) > 80.0:
				Input.action_press("winch_payout")
				await wait(0.12)
				Input.action_release("winch_payout")
			else:
				await wait(0.45)
		elif angle > 1.2:
			var pulse: float = 0.28 if angle > 4.0 else 0.12
			Input.action_press("winch_haul")
			await wait(pulse)
			Input.action_release("winch_haul")
		else:
			await wait(0.5)
		await wait(0.35)
	return false

func finish_lock() -> void:	for _attempt: int in range(12):
		var info: Dictionary = rig.call("alignment_state") as Dictionary
		var target: Dictionary = app.call("_nearest_interaction") as Dictionary
		print("DEMO_LOCK_TRY angle=%.2f lockable=%s settled=%s pos=%s target=%s dist=%.2f" % [
			float(info.get("angle_deg", 0.0)), str(info.get("lockable", false)), str(info.get("settled", false)),
			str(player.global_position), str(target.get("kind", "")),
			player.global_position.distance_to((app.get("lock_station") as Node3D).global_position),
		])
		if bool(info.get("lockable", false)):
			await press("interact", 3)
			await wait(0.5)
			if bool(rig.get("completed")):
				return
		await wait(0.6)

# --- movement --------------------------------------------------------------

func walk_to_anchor(anchor_id: String, offset: float = 1.45) -> void:
	var anchor: Node3D = rig.call("find_anchor", anchor_id) as Node3D
	var at: Vector3 = anchor.call("attach_point") as Vector3
	await walk_to(Vector3(at.x + 0.55, 0.3, at.z + offset))
	await look_toward(Vector3(at.x, 0.75, at.z))

func walk_to_socket() -> void:
	var socket: Vector3 = (app.get("lock_station") as Node3D).global_position
	await walk_to(Vector3(socket.x - 0.6, 0.3, socket.z - 1.4))
	await look_toward(Vector3(socket.x, 0.75, socket.z))

func leave_console() -> void:
	if bool(app.get("at_console")):
		await press("interact", 3)
	await pause(0.3)

func take_console() -> void:
	var console: Vector3 = (app.get("winch_station") as Node3D).global_position
	await walk_to(Vector3(console.x, 0.3, console.z + 1.85))
	if not bool(app.get("at_console")):
		await press("interact", 3)
	await pause(0.4)

func walk_to(target: Vector3, tolerance: float = 0.6, max_frames: int = 900) -> bool:
	for _i: int in range(max_frames):
		var flat_target: Vector2 = Vector2(target.x, target.z)
		var flat_self: Vector2 = Vector2(player.global_position.x, player.global_position.z)
		if flat_self.distance_to(flat_target) <= tolerance:
			_release_move()
			await wait(0.15)
			return true
		var direction: Vector2 = (flat_target - flat_self).normalized()
		player.set("_camera_yaw_target", atan2(-direction.x, -direction.y))
		var yaw: float = float(player.get("_camera_yaw"))
		var forward: Vector2 = Vector2(-sin(yaw), -cos(yaw))
		var right: Vector2 = Vector2(cos(yaw), -sin(yaw))
		var horizontal: float = direction.dot(right)
		var vertical: float = -direction.dot(forward)
		_release_move()
		if horizontal > 0.02:
			Input.action_press("move_right", absf(horizontal))
		elif horizontal < -0.02:
			Input.action_press("move_left", absf(horizontal))
		if vertical > 0.02:
			Input.action_press("move_down", absf(vertical))
		elif vertical < -0.02:
			Input.action_press("move_up", absf(vertical))
		await get_tree().physics_frame
	_release_move()
	return false

func _release_move() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)

func look_toward(target: Vector3) -> void:
	var dx: float = target.x - player.global_position.x
	var dz: float = target.z - player.global_position.z
	player.set("_camera_yaw_target", atan2(-dx, -dz))
	await wait(0.35)

func haul_until(limit_deg: float, max_frames: int) -> void:
	Input.action_press("winch_haul")
	for _i: int in range(max_frames):
		await get_tree().physics_frame
		var info: Dictionary = rig.call("alignment_state") as Dictionary
		if float(info.get("angle_deg", 15.0)) <= limit_deg:
			break
	Input.action_release("winch_haul")
	await wait(0.3)

# --- input/timing ----------------------------------------------------------

func press(action: String, hold_frames: int = 2) -> void:
	var down: InputEventAction = InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await wait(float(hold_frames) / 60.0)
	var up: InputEventAction = InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await wait(0.1)

func banner(text: String) -> void:
	if hud != null:
		hud.call("show_feedback", text, "info")
	await wait(1.2)

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func pause(seconds: float) -> void:
	await wait(seconds)
