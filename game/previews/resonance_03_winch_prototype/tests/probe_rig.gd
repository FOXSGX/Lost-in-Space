extends SceneTree

# Headless integration probe for the winch rig.
#
# Drives the REAL scene with the same Input actions a player uses: it walks the
# character with move_* actions, presses E/W/S/Space/F/Q/R through the app's
# input path, and reads only what the rig publishes. Nothing is teleported and no
# private solver state is written.
#
# Mission order being verified:
#   1. hook the far eye (long lever) and confirm the drum feeds out slack
#   2. haul: the far lever breaks the jam and brings the rail to the bracket
#   3. release: the taut cable holds the rail at the bracket
#   4. haul past the bracket: overshoot, then pay out to fall back into tolerance
#   5. lock the rail with F, wait for drift
#   6. reset and repeat to prove the loop is not one-shot
#   7. the mid eye (short lever) must NOT be able to break the jam
#
# Usage:
#   godot --headless --path <project> --script res://tests/probe_rig.gd -- <outdir>

var app: Node3D
var rig: Node3D
var player: CharacterBody3D
var output: String = "user://probe"
var checks: Array[Dictionary] = []
var failed: int = 0
var trace: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("res://resonance_03.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(30)
	rig = app.get("rig") as Node3D
	player = app.get("player") as CharacterBody3D
	if rig == null or player == null:
		print("PROBE_FAILED missing rig or player")
		quit(1)
		return

	await scenario_hook_and_haul()
	await scenario_recover_overshoot()
	await scenario_lock()
	await scenario_reset_and_repeat()
	await scenario_mid_eye_fails()
	await finish()

func frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

# --- readings --------------------------------------------------------------

func rail_state() -> Dictionary:
	return rig.call("alignment_state") as Dictionary

func winch_state() -> Dictionary:
	return rig.call("tension_state") as Dictionary

func angle_deg() -> float:
	return float(rail_state().get("angle_deg", 0.0))

func check(ok: bool, label: String) -> void:
	checks.append({"ok": ok, "label": label, "snapshot": _brief()})
	if ok:
		print("PROBE_OK ", label)
	else:
		failed += 1
		print("PROBE_FAILED ", label)

func _brief() -> Dictionary:
	var rail: Dictionary = rail_state()
	var winch: Dictionary = winch_state()
	return {
		"angle": rail.get("angle_deg", 0.0),
		"jammed": rail.get("jammed", false),
		"tension": winch.get("tension", 0.0),
		"length": winch.get("free_length", 0.0),
		"mode": winch.get("mode", ""),
		"state": rig.get("mission_state"),
	}

func sample(tag: String) -> void:
	var row: Dictionary = _brief()
	row["tag"] = tag
	trace.append(row)

# --- walking ---------------------------------------------------------------

func walk_to(target: Vector3, tolerance: float = 0.55, max_frames: int = 700) -> bool:
	for _i: int in range(max_frames):
		var flat_target: Vector2 = Vector2(target.x, target.z)
		var flat_self: Vector2 = Vector2(player.global_position.x, player.global_position.z)
		if flat_self.distance_to(flat_target) <= tolerance:
			_release_move()
			await frames(3)
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
		await physics_frame
	_release_move()
	return false

func _release_move() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)

# Tap an action through the real input queue, so both the polled state and the
# _input/_unhandled_input callbacks see it.
func press(action: String, hold_frames: int = 2) -> void:
	var down: InputEventAction = InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await frames(hold_frames)
	var up: InputEventAction = InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await frames(2)

# --- winch helpers ---------------------------------------------------------

# Hold the haul key until the rail reaches `limit_deg`, then release.
# Returns {broke, min_angle, frames}. The app polls held keys, so a plain
# action_press is the same hold a player produces with a keyboard.
func haul_until(limit_deg: float, max_frames: int) -> Dictionary:
	Input.action_press("winch_haul")
	var broke: bool = false
	var min_angle: float = 90.0
	var used: int = 0
	for i: int in range(max_frames):
		await physics_frame
		used = i
		var info: Dictionary = rail_state()
		min_angle = minf(min_angle, float(info.get("angle_deg", 90.0)))
		if not bool(info.get("jammed", true)):
			broke = true
		if bool(info.get("jammed", true)) == false and min_angle <= limit_deg:
			break
	Input.action_release("winch_haul")
	await frames(3)
	return {"broke": broke, "min_angle": min_angle, "frames": used}

func wait_settle(limit_deg: float, max_frames: int) -> bool:
	for _i: int in range(max_frames):
		await physics_frame
		var info: Dictionary = rail_state()
		if absf(float(info.get("angle_deg", 99.0))) <= limit_deg and bool(info.get("settled", false)):
			return true
	return false

func take_console() -> bool:
	var console: Vector3 = (app.get("winch_station") as Node3D).global_position
	await walk_to(Vector3(console.x, 0.3, console.z + 1.9), 0.8)
	if not bool(app.get("at_console")):
		await press("interact", 3)
	return bool(app.get("at_console"))

func leave_console() -> void:
	if bool(app.get("at_console")):
		await press("interact", 3)

func walk_to_anchor(anchor_id: String, offset: float = 1.4) -> bool:
	var anchor: Node3D = rig.call("find_anchor", anchor_id) as Node3D
	var at: Vector3 = anchor.call("attach_point") as Vector3
	return await walk_to(Vector3(at.x, 0.3, at.z + offset), 0.9)

func walk_to_socket() -> bool:
	var socket: Vector3 = (app.get("lock_station") as Node3D).global_position
	return await walk_to(Vector3(socket.x - 0.6, 0.3, socket.z - 1.4), 0.9)

# --- scenarios -------------------------------------------------------------

func scenario_hook_and_haul() -> void:
	# 1. Approach the far eye (long lever).
	var far_anchor: Node3D = rig.call("find_anchor", "eye_far") as Node3D
	var far_at: Vector3 = far_anchor.call("attach_point") as Vector3
	var arrived: bool = await walk_to(Vector3(far_at.x, 0.3, far_at.z + 1.5), 0.9)
	check(arrived, "player walked to the far lifting eye")
	sample("at_far_eye")
	await press("interact", 3)
	var winch: Dictionary = winch_state()
	check(bool(winch.get("attached", false)), "E attached the cable to the far eye")
	var reach: float = far_at.distance_to((app.get("winch_station") as Node3D).get_node("Sheave").global_position)
	check(float(winch.get("free_length", 0.0)) >= reach - 0.05, "hooking up feeds out cable to reach the eye (%.2f m)" % float(winch.get("free_length", 0.0)))
	check(float(winch.get("tension", 0.0)) < 300.0, "hooking up does not spike the tension (%.0f N)" % float(winch.get("tension", 0.0)))
	sample("attached")

	# 2. Try to haul from the wrong place: the console is not in reach.
	await press("winch_haul", 10)
	check(absf(angle_deg() - 15.0) < 0.01, "haul key does nothing away from the console")
	check(bool(rail_state().get("jammed", true)), "rail is still jammed")

	# 3. Walk to the winch console and take control.
	var reached_console: bool = await take_console()
	check(reached_console, "player walked to the winch console")
	check(bool(app.get("at_console")), "E took control of the winch")

	# 4. Haul until the jam breaks and the rail reaches the bracket.
	var haul: Dictionary = await haul_until(1.4, 900)
	check(bool(haul.get("broke", false)), "the far eye breaks the jam once the drum pulls hard enough")
	check(float(haul.get("min_angle", 99.0)) < 4.0, "hauling brought the rail back near the bracket (got %.2f deg)" % float(haul.get("min_angle", 99.0)))
	sample("after_haul")

	# 5. Releasing the cable must hold the rail instead of letting it fall back.
	var held: bool = await wait_settle(1.2, 240)
	check(held, "released cable holds the rail at the bracket")
	sample("held")

func scenario_recover_overshoot() -> void:
	# Leave the console, walk around, and take it again.
	await leave_console()
	await walk_to(Vector3((app.get("winch_station") as Node3D).global_position.x + 1.2, 0.3, (app.get("winch_station") as Node3D).global_position.z + 3.2), 0.8)
	var again: bool = await take_console()
	check(again, "took the console again after walking around")

	# Keep hauling past the bracket: that is the real overshoot direction.
	var haul: Dictionary = await haul_until(-1.5, 360)
	check(float(haul.get("min_angle", 99.0)) <= -1.0, "hauling past the bracket reproduces the overshoot (got %.2f deg)" % float(haul.get("min_angle", 99.0)))
	sample("overshot")

	# Pay out until the cable goes slack, then let the sag swing the rail back.
	Input.action_press("winch_payout")
	for _i: int in range(60):
		await physics_frame
		if float(winch_state().get("tension", 0.0)) <= 5.0:
			break
	Input.action_release("winch_payout")
	await frames(3)
	var recovered: bool = await wait_settle(1.0, 600)
	check(recovered, "paying out lets the rail fall back into the lock tolerance")
	sample("recovered")

func scenario_lock() -> void:
	await frames(30)
	var rail_before: Dictionary = rail_state()
	check(absf(float(rail_before.get("angle_deg", 0.0))) <= 1.2, "rail is inside the lock tolerance")
	check(bool(rail_before.get("settled", false)), "rail is settled (no residual swing)")
	await leave_console()
	var reached: bool = await walk_to_socket()
	check(reached, "player walked to the lock socket")
	await press("interact", 3)
	check(bool(rig.get("completed")), "F installed the lock pin and completed the mission")
	sample("locked")

	# Drift test: 3 seconds with no input must not move the rail.
	var angle_at_lock: float = angle_deg()
	await frames(180)
	var angle_later: float = angle_deg()
	check(absf(angle_later - angle_at_lock) < 0.0005, "locked rail does not drift over 3 s (delta %.6f deg)" % absf(angle_later - angle_at_lock))

func scenario_reset_and_repeat() -> void:
	var completions_before: int = int(rig.get("completion_count"))
	await press("reset_mission", 3)
	await frames(20)
	var rail: Dictionary = rail_state()
	check(not bool(rig.get("completed")), "R cleared the completion state")
	check(bool(rail.get("jammed", false)), "R restored the jam")
	check(absf(float(rail.get("angle_deg", 0.0)) - 15.0) < 0.01, "R restored the start angle (%.2f)" % float(rail.get("angle_deg", 0.0)))
	check(not bool(winch_state().get("attached", false)), "R released the cable")
	check(int(rig.get("completion_count")) == completions_before, "R did not lose the completion counter")

	# Second completion through the same path, to prove the loop repeats.
	await walk_to_anchor("eye_far", 1.4)
	await press("interact", 3)
	check(bool(winch_state().get("attached", false)), "cable hooked again after reset")
	var console_ok: bool = await take_console()
	if console_ok and not bool(app.get("at_console")):
		await press("interact", 3)
	await haul_until(1.4, 900)
	var settled: bool = await wait_settle(1.2, 240)
	check(settled, "second haul settles at the bracket")
	await leave_console()
	await walk_to_socket()
	await press("interact", 3)
	check(bool(rig.get("completed")), "second completion succeeded after reset")
	check(int(rig.get("completion_count")) == completions_before + 1, "completion counter incremented")
	sample("repeat_locked")

func scenario_mid_eye_fails() -> void:
	# The short lever must fail: same machine, same tension, no movement.
	await press("reset_mission", 3)
	await frames(20)
	await walk_to_anchor("eye_mid", 1.3)
	await press("interact", 3)
	var winch: Dictionary = winch_state()
	check(bool(winch.get("attached", false)), "cable hooked to the mid eye")
	check(str(winch.get("anchor_name", "")).contains("中段"), "mid eye is the attached anchor")
	await take_console()
	Input.action_press("winch_haul")
	await frames(240)
	Input.action_release("winch_haul")
	await frames(3)
	var rail: Dictionary = rail_state()
	check(bool(rail.get("jammed", true)), "mid eye cannot break the jam")
	check(bool(winch_state().get("stalled", false)), "mid eye stalls the winch clutch instead")
	await press("reset_mission", 3)

func finish() -> void:
	var data: Dictionary = {
		"passed": failed == 0,
		"failures": failed,
		"checks": checks,
		"trace": trace,
		"snapshot": rig.call("rig_snapshot"),
		"feedback": rig.get("feedback_log"),
		"stability": rig.get("stability_log"),
	}
	var file: FileAccess = FileAccess.open(output.path_join("probe.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()
	print("PROBE_RESULT ", JSON.stringify({"passed": failed == 0, "failures": failed, "checks": checks.size()}))
	current_scene = null
	app.queue_free()
	await frames(3)
	await process_frame
	quit(0 if failed == 0 else 1)
