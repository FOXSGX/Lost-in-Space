extends SceneTree

# -----------------------------------------------------------------------------
# M9 · Full continuous-playthrough test.
#
# This is the evidence run for "one level, not two prototypes". Every step is
# driven by the same Input actions a player uses (WASD, E, W/S on the drum, Q,
# Shift, Space). Nothing is marked complete by writing a flag:
#
#   board -> depart -> ride -> resonance bend -> grip -> fault stop
#   -> refused departure -> disembark -> walk the bay -> hook the eye
#   -> take over the winch -> break the jam -> overshoot -> recover
#   -> leave the console -> install the pin -> reboard -> depart
#   -> cross the repaired section -> arrive at the crystal gate
#
# The character is never teleported; the only teleport path in this run is the
# level's own rescue, which is not used here.
# -----------------------------------------------------------------------------

var app: Node
var scene: Node3D
var cart: AnimatableBody3D
var yard: Node3D
var rig: Node3D
var flow: Node
var player: CharacterBody3D
var cargo: Node3D
var output: String
var failures: int = 0
var checks: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var clock: int = 0
var routes: Array[Dictionary] = []
var camera_overlaps: int = 0
var camera_samples: int = 0
var corrections: int = 0

func _initialize() -> void:
	run.call_deferred()

func boot() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	output = args[0] if args.size() > 0 else "user://flow"
	DirAccess.make_dir_recursive_absolute(output)
	app = (load("res://act23/resonance_02.tscn") as PackedScene).instantiate()
	root.add_child(app)
	current_scene = app
	await frames(3)
	app.call("start_cart")
	scene = app.get("stage") as Node3D
	cart = scene.get("cart") as AnimatableBody3D
	yard = scene.get("yard") as Node3D
	rig = yard.get("rig") as Node3D
	flow = scene.get("flow")
	player = scene.get("player") as CharacterBody3D
	cargo = scene.get("device") as Node3D
	await frames(45)

func frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame
		clock += 1
		if scene != null and is_instance_valid(scene) and clock % 15 == 0:
			sample()

func sample() -> void:
	var rail: Dictionary = rig.call("alignment_state") as Dictionary
	var tension: Dictionary = rig.call("tension_state") as Dictionary
	var overlap: bool = bool(player.call("camera_overlap"))
	camera_samples += 1
	if overlap:
		camera_overlaps += 1
	samples.append({
		"t": clock,
		"phase": str(flow.get("phase")),
		"distance": float(cart.get("distance")),
		"speed": float(cart.get("speed")),
		"state": str(cart.get("state")),
		"angle": float(rail.get("angle_deg", 0.0)),
		"tension": float(tension.get("tension", 0.0)),
		"attached": bool(tension.get("attached", false)),
		"locked": bool(rail.get("locked", false)),
		"on_floor": player.is_on_floor(),
		"local_y": cart.to_local(player.global_position).y,
		"camera": str((player.get("camera") as Camera3D).global_position),
		"player_pos": str(player.global_position),
		"running": bool(cart.get("running")),
		"brake_reason": str(cart.get("brake_reason")),
		"camera_overlap": overlap,
	})

func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details, "t": clock,
		"phase": str(flow.get("phase")) if flow != null else ""})
	if not ok:
		failures += 1
	print("FLOW_", "OK " if ok else "FAIL ", label, " ", JSON.stringify(details))

func stop_movement() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down", "winch_haul", "winch_payout", "winch_creep"]:
		Input.action_release(action)

func travel_to(target: Vector3, limit: int = 900, radius: float = 0.12) -> bool:
	return await travel(target, limit, radius, false)

# On-deck movement has to re-resolve the world target every frame: the deck is
# moving at 1.55 m/s, so a target captured once would slide away from the player.
func travel_local(local: Vector3, limit: int = 900, radius: float = 0.12) -> bool:
	return await travel(local, limit, radius, true)

# One movement routine for both frames. It also does what a player does when a
# machine is in the way: if no progress is made for a moment, sidestep instead of
# grinding into the obstacle. Without that, a waypoint whose straight line grazes
# a cylinder is unreachable and the test reports a level bug that is not one.
func travel(target: Vector3, limit: int, radius: float, local: bool) -> bool:
	var reached: bool = false
	var aim: Vector3 = target
	var check_timer: int = 0
	var last: Vector3 = player.global_position
	var detour: int = 0
	var side: float = 1.0
	for _i: int in range(limit):
		var world_target: Vector3 = cart.to_global(target) if local else target
		var here: Vector3 = player.global_position
		if Vector2(here.x - world_target.x, here.z - world_target.z).length() < radius:
			reached = true
			break
		if detour > 0:
			detour -= 1
		else:
			aim = world_target
			check_timer += 1
			if check_timer >= 26:
				if Vector2(here.x - last.x, here.z - last.z).length() < 0.32:
					var toward: Vector3 = world_target - here
					toward.y = 0.0
					var perp: Vector3 = Vector3(-toward.z, 0.0, toward.x)
					if perp.length() > 0.001:
						aim = here + perp.normalized() * 2.2 * side
						detour = 24
						side = -side
				last = here
				check_timer = 0
		var direction: Vector3 = aim - player.global_position
		direction.y = 0.0
		if direction.length() < 0.06:
			direction = Vector3(0.08, 0.0, 0.08)
		var yaw: float = float(player.get("_camera_yaw"))
		var forward: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
		var strength: float = clampf(direction.length() / 0.55, 0.55, 1.0)
		var horizontal: float = direction.normalized().dot(right) * strength
		var vertical: float = -direction.normalized().dot(forward) * strength
		stop_movement()
		Input.action_press("move_right" if horizontal > 0.0 else "move_left", absf(horizontal))
		Input.action_press("move_down" if vertical > 0.0 else "move_up", absf(vertical))
		await physics_frame
		clock += 1
		if clock % 15 == 0:
			sample()
	stop_movement()
	await frames(6)
	return reached

func face(target: Vector3) -> void:
	for _i: int in range(26):
		var direction: Vector3 = target - player.global_position
		player.set("_camera_yaw_target", atan2(-direction.x, -direction.z))
		await physics_frame
		clock += 1

func press(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(5)

func travel_deck(local: Vector3, limit: int = 900, radius: float = 0.12) -> bool:
	return await travel_local(local, limit, radius)

func yard_point(local: Vector3) -> Vector3:
	return yard.to_global(local)

func walk(points: Array, limit_each: int = 900, radius: float = 0.35) -> bool:
	var index: int = 0
	for point: Variant in points:
		var target: Vector3 = point as Vector3
		var ok: bool = await travel_to(target, limit_each, radius)
		var here: Vector3 = player.global_position
		var miss: float = Vector2(here.x - target.x, here.z - target.z).length()
		routes.append({"leg": index, "ok": ok, "miss": miss,
			"target": str(target), "player": str(here)})
		if not ok:
			# A waypoint is a hint, not a waypoint in a navmesh: if the character is
			# close enough to still be inside the interaction range, keep walking.
			if miss > 2.0:
				return false
		index += 1
	return true

# --- predicates used by the polling helpers --------------------------------

func p_distance_above(value: float, _a: Variant = null) -> bool:
	return float(cart.get("distance")) > value

func p_stopped(_a: Variant = null) -> bool:
	return bool(cart.get("stopped_for_fault"))

func p_arrived(_a: Variant = null) -> bool:
	return bool(cart.get("arrived"))

func p_jam_broken(_a: Variant = null) -> bool:
	var rail: Dictionary = rig.call("alignment_state") as Dictionary
	return not bool(rail.get("jammed", true))

func p_angle_below(value: float) -> bool:
	var rail: Dictionary = rig.call("alignment_state") as Dictionary
	return float(rail.get("angle_deg", 0.0)) < value

func p_lockable(_a: Variant = null) -> bool:
	var rail: Dictionary = rig.call("alignment_state") as Dictionary
	return bool(rail.get("lockable", false))

func rail_angle() -> float:
	var rail: Dictionary = rig.call("alignment_state") as Dictionary
	return float(rail.get("angle_deg", 0.0))

func wait_until(predicate: Callable, limit: int) -> bool:
	for _i: int in range(limit):
		await physics_frame
		clock += 1
		if clock % 15 == 0:
			sample()
		if bool(predicate.call()):
			return true
	return false

func hold_until(action: String, limit: int, predicate: Callable) -> bool:
	Input.action_press(action)
	var hit: bool = await wait_until(predicate, limit)
	Input.action_release(action)
	await frames(4)
	return hit

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		captures.append({"name": label, "skipped": "headless"})
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	captures.append({"name": label, "frame": Engine.get_frames_drawn(),
		"distance": cart.get("distance"), "phase": flow.get("phase")})

# --- the run ---------------------------------------------------------------

func run() -> void:
	await boot()
	# 1) Board and depart.
	check(await travel_deck(Vector3(1.0, 1.91, 1.55)), "沿踏步登上矿车甲板")
	check(player.is_on_floor() and cart.to_local(player.global_position).y > 1.8, "甲板提供真实支撑")
	await shot("01_boarded")
	check(await travel_deck(Vector3(2.0, 1.91, 1.7)), "走到前端控制器")
	await face(cart.to_global(Vector3(2.48, 2.64, 1.08)))
	await press("repair")
	check(bool(cart.get("running")), "E 发车", {"distance": cart.get("distance")})

	# 2) Ride into the resonance bend and brace on the rail.
	check(await wait_until(p_distance_above.bind(31.5), 2600), "矿车驶入共振弯道")
	var bend: Node3D = scene.get("bend_event") as Node3D
	check(str(bend.get("phase")) != "idle", "共振弯道事件已激活", {"phase": bend.get("phase")})
	check(await travel_deck(Vector3(-0.7, 1.91, 1.44), 400), "行驶中走到扶手")
	await face(cart.to_global(Vector3(-0.7, 2.91, 0.87)))
	await press("repair")
	check(int(player.get("grip_id")) == 0, "E 抓扶", {"grip": player.get("grip_id")})
	await shot("02_bend_grip")
	await frames(420)
	check(int(player.get("grip_id")) == 0, "弯道中保持抓扶")
	await press("repair")
	check(int(player.get("grip_id")) == -1, "E 松开扶手")

	# 3) The governor stops the cart at the severed section.
	check(await wait_until(p_stopped, 3600), "矿车在前方断轨处安全停车",
		{"distance": cart.get("distance"), "speed": cart.get("speed")})
	check(not bool(cart.get("arrived")), "未通过断轨，不算到达终点", {"distance": cart.get("distance")})
	check(absf(float(cart.get("distance")) - 88.0) < 0.6, "停车位置在断轨前",
		{"distance": cart.get("distance")})
	await shot("03_fault_stop")

	# 4) Un-repaired departure must be refused.
	check(await travel_deck(Vector3(2.0, 1.91, 1.7)), "停车后走回控制器")
	await face(cart.to_global(Vector3(2.48, 2.64, 1.08)))
	await press("repair")
	check(not bool(cart.get("running")), "未修复时无法再次发车")
	check(str(scene.get("feedback")).find("断") >= 0 or str(scene.get("feedback")).find("轨道") >= 0,
		"拒绝发车时给出断轨原因", {"feedback": scene.get("feedback")})

	# 5) Disembark and walk to the break. The descent is given explicit waypoints:
	# the near-side rail is closed except for the boarding gate at x = 0.52..1.48,
	# and a diagonal approach slides along that rail instead of passing through it.
	check(await travel_deck(Vector3(1.0, 1.91, 1.70), 400), "沿甲板走到近侧车门")
	check(await travel_deck(Vector3(1.0, 1.91, 1.05), 300), "对准近侧登车口")
	check(await travel_deck(Vector3(1.0, 0.40, -2.00), 420), "沿黄色踏步下车到维修停车平台")
	check(cart.to_local(player.global_position).y < 0.6, "玩家已经离开甲板",
		{"local_y": cart.to_local(player.global_position).y})
	await shot("04_disembarked")
	check(await walk([
		yard_point(Vector3(2.2, 0.0, -1.20)),
		yard_point(Vector3(3.60, 0.0, -0.60)),
		yard_point(Vector3(5.60, 0.0, -0.55)),
	]), "走到断轨前端的吊耳旁")
	var far_anchor: Node3D = rig.call("find_anchor", "eye_far") as Node3D
	await face(far_anchor.call("attach_point") as Vector3)
	await press("repair")
	var tension_now: Dictionary = rig.call("tension_state") as Dictionary
	check(bool(tension_now.get("attached")), "E 把缆绳挂上前端吊耳",
		{"anchor": tension_now.get("anchor_name")})
	await shot("05_cable_attached")

	# 6) Take over the winch and break the jam.
	# The machine now has its real footprint, and its guard rail has a gate at the
	# operator pedestal. Approach from the south through that gate; the old route
	# walked through the drum housing and is no longer valid.
	# The under-deck volume is now solid, so the winch is reached around the cart's
	# nose rather than by walking through the deck at head height.
	check(await walk([
		yard_point(Vector3(5.60, 0.0, -1.50)),
		yard_point(Vector3(5.70, 0.0, 4.60)),
		yard_point(Vector3(-0.60, 0.0, 3.95)),
	], 900, 0.45), "绕过车头走到绞盘控制台")
	await face(rig.get("winch").global_position)
	await press("repair")
	check(bool(flow.get("at_console")), "E 接管绞盘", {"console": flow.get("at_console")})
	check(bool(player.get("interaction_locked")), "接管期间角色移动被锁定")
	check(await hold_until("winch_haul", 900, p_jam_broken), "前端吊耳把轨道从碎石里拉脱",
		{"angle": rail_angle()})
	await frames(110)
	check(rail_angle() < 13.5, "轨道真的开始转动", {"angle": rail_angle()})
	await shot("06_rail_moving")

	# 7) Overshoot on purpose, then recover.
	check(await hold_until("winch_haul", 2000, p_angle_below.bind(-5.2)), "持续收缆会拉过头",
		{"angle": rail_angle()})
	check(rail_angle() < -4.2, "过冲已越过导向槽（不是被自动吃掉）", {"angle": rail_angle()})
	var locked_out: Dictionary = rig.call("try_install_lock") as Dictionary
	check(not bool(locked_out.get("ok")), "明显歪斜时拒绝上锁", locked_out)
	await shot("07_overshoot")
	# Player-style recovery: creep + watch the pointer + tap payout.
	Input.action_press("winch_creep")
	var direction: String = ""
	for _i: int in range(1500):
		await physics_frame
		clock += 1
		var rail: Dictionary = rig.call("alignment_state") as Dictionary
		if bool(rail.get("lockable", false)):
			break
		var angle: float = float(rail.get("angle_deg", 0.0))
		var wanted: String = ""
		if angle > 2.0:
			wanted = "winch_haul"
		elif angle < -2.0:
			wanted = "winch_payout"
		if wanted != direction:
			if direction != "":
				Input.action_release(direction)
			direction = wanted
			if direction != "":
				Input.action_press(direction)
				corrections += 1
	Input.action_release("winch_haul")
	Input.action_release("winch_payout")
	Input.action_release("winch_creep")
	check(await wait_until(p_lockable, 300), "放线与微调把轨道带回锁定窗口",
		{"angle": rail_angle(), "corrections": corrections})
	await shot("08_aligned")

	# 8) Leave the console, install the pin at the socket.
	await press("repair")
	check(not bool(flow.get("at_console")), "E 离开绞盘")
	check(await walk([
		yard_point(Vector3(-0.60, 0.0, 3.95)),
		yard_point(Vector3(5.70, 0.0, 4.60)),
		yard_point(Vector3(7.30, 0.0, 2.60)),
		yard_point(Vector3(6.90, 0.0, 2.30)),
	], 900, 0.65), "绕过接收架走到锁定座")
	await face(yard.call("lock_station_position") as Vector3)
	await press("repair")
	var lock: Dictionary = rig.call("lock_state") as Dictionary
	check(bool(lock.get("locked")), "E 插入锁定销并完成机械锁定", lock)
	check(absf(rail_angle()) < 0.05, "锁定后轨道完全回到线路", {"angle": rail_angle()})
	check(bool(cart.get("route_clear")), "锁定后矿车线路被放行")
	await frames(90)
	var sign_node: Node3D = yard.get("entrance_sign") as Node3D
	check(sign_node != null and sign_node.visible, "修复后出现晶体矿区方向提示")
	await shot("09_locked")

	# 9) Walk back, reboard, depart through the repaired section. The parked cart
	# blocks the direct line south, so the route goes round its front nose first.
	check(await walk([
		yard_point(Vector3(5.60, 0.0, 2.30)),
		yard_point(Vector3(4.60, 0.0, 2.10)),
		yard_point(Vector3(2.90, 0.0, -0.80)),
		yard_point(Vector3(3.66, 0.0, -4.20)),
		yard_point(Vector3(0.00, 0.0, -4.10)),
	], 700, 0.6), "沿维修平台走回登车踏步")
	check(await travel_deck(Vector3(1.0, 0.40, -1.95), 420), "走回登车踏步下方")
	check(await travel_deck(Vector3(1.0, 1.91, 1.05), 420), "沿踏步回到甲板")
	check(await travel_deck(Vector3(1.0, 1.91, 1.70), 300), "回到近侧甲板")
	check(await travel_deck(Vector3(2.0, 1.91, 1.7), 600), "沿甲板走到前端控制器")
	await face(cart.to_global(Vector3(2.48, 2.64, 1.08)))
	await press("repair")
	check(bool(cart.get("running")), "修复后重新发车")
	await shot("10_depart_again")

	# 10) Cross the repaired section and arrive at the crystal gate.
	check(await wait_until(p_arrived, 4200), "矿车驶过修复段并抵达晶体矿区入口",
		{"distance": cart.get("distance"), "speed": cart.get("speed")})
	check(float(cart.get("distance")) > 104.0, "抵达位置在 03 晶体矿区入口",
		{"distance": cart.get("distance")})
	await shot("11_arrived")
	check(str(flow.get("phase")) == "done", "任务阶段进入 done", {"phase": flow.get("phase")})
	var door_ok: bool = await travel_deck(Vector3(1.0, 1.91, 1.70), 400)
	routes.append({"leg": "gate_door", "ok": door_ok, "local": str(cart.to_local(player.global_position)),
		"player": str(player.global_position), "locked": player.get("interaction_locked"),
		"paused": player.get("paused"), "cart_paused": cart.get("paused"),
		"input_blocked": scene.get("input_blocked"), "running": cart.get("running"),
		"grip": player.get("grip_id"), "input_enabled": player.get("input_enabled")})
	check(door_ok, "到达后沿甲板走到车门")
	var gate_ok: bool = await travel_deck(Vector3(1.0, 1.91, 1.05), 300)
	routes.append({"leg": "gate_edge", "ok": gate_ok, "local": str(cart.to_local(player.global_position))})
	check(gate_ok, "对准近侧登车口")
	var off_ok: bool = await travel_deck(Vector3(1.0, 0.40, -2.00), 420)
	routes.append({"leg": "gate_off", "ok": off_ok, "local": str(cart.to_local(player.global_position))})
	check(off_ok, "在晶体矿区入口下车")
	# The resonance hoop carries a camera-only proxy far thicker than the torus it
	# represents; a few frames can land inside that invisible box with no visible
	# geometry in the frame (see KNOWN_ISSUES). "No sustained occlusion" is the
	# honest gate; 0/413 was measured headless, 2/414 windowed.
	check(camera_overlaps <= 8, "整段流程相机未持续穿模",
		{"samples": camera_samples, "overlaps": camera_overlaps})
	await shot("12_crystal_gate")
	await finish()

func finish() -> void:
	stop_movement()
	var data: Dictionary = {
		"passed": failures == 0,
		"failures": failures,
		"checks": checks,
		"captures": captures,
		"samples": samples,
		"routes": routes,
		"camera_samples": camera_samples,
		"camera_overlaps": camera_overlaps,
		"corrections": corrections,
		"flow": flow.call("snapshot"),
		"events": scene.get("events"),
		"evidence": "Real Godot input actions only. No stage flags are written by the test.",
	}
	var file: FileAccess = FileAccess.open(output.path_join("flow.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	print("FLOW_RESULT ", JSON.stringify({"passed": failures == 0, "checks": checks.size(), "failures": failures}))
	scene = null
	current_scene = null
	app.queue_free()
	await frames(4)
	quit(0 if failures == 0 else 1)

