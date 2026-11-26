extends SceneTree

## Full single-player acceptance run for the Act 01 MODULE (standalone host).
##
## Adapted from the Act01 V2 `solo_full_run.gd`: all locomotion uses
## Input.action_press and the player's normal physics body; all interactions use
## the normal raycast and Act1Interactable API. No stage flags or player
## positions are set directly.
##
## The only behavioural change vs the source run: after the cart departs, the
## module no longer switches to a local fake "act02_ride" second act. It emits an
## Act01 completion through `Act1SessionBridge` (standalone stub). This test
## asserts the completion was recorded (chapter_history.act01 / act01_completed),
## which is exactly what the main integration will observe in integrated mode.

var scene: Node3D
var stage: Node3D
var player: Act1StationPlayer
var failures: Array[String] = []
var log_lines: Array[String] = []
var snapshots: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func log_line(text: String) -> void:
	print(text)
	log_lines.append(text)


func check(ok: bool, text: String) -> void:
	log_line(("PASS " if ok else "FAIL ") + text)
	if not ok:
		failures.append(text)


func _face(target: Vector3) -> void:
	var d := target - player.global_position
	player.yaw = atan2(-d.x, -d.z)
	player.rotation.y = player.yaw


func walk(target: Vector3, seconds: float, label := "") -> void:
	_face(target)
	Input.action_press("move_forward")
	var stuck := 0
	var last := player.global_position
	for i in range(int(seconds * 60.0)):
		await physics_frame
		_face(target)
		if Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < 0.55:
			break
		if i % 30 == 0:
			if player.global_position.distance_to(last) < 0.08:
				stuck += 1
			else:
				stuck = 0
			last = player.global_position
	Input.action_release("move_forward")
	await physics_frame
	log_line("WALK %s target=%s pos=%s y=%.2f" % [label, str(target.snapped(Vector3(0.1, 0.1, 0.1))), str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01))), player.global_position.y])


func press_id(id: String, hold := 0.14, label := "") -> bool:
	if not stage.interactables.has(id):
		check(false, "missing interactable %s" % id)
		return false
	var point: Act1Interactable = stage.interactables[id]
	var dist := player.global_position.distance_to(point.global_position)
	if dist > 4.1:
		log_line("AIM %s distance too far %.2f at %s" % [id, dist, str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	player.look_at_point(point.global_position)
	await create_timer(0.22).timeout
	var found := "none"
	if player.current_target != null:
		found = str(player.current_target.get("interaction_id"))
	log_line("AIM %s target=%s prompt=%s" % [id, found, player.current_prompt])
	if found != id:
		return false
	Input.action_press("interact")
	await create_timer(hold).timeout
	Input.action_release("interact")
	await create_timer(0.35).timeout
	return true


func hold_id(id: String, seconds: float) -> bool:
	if not stage.interactables.has(id):
		return false
	var point: Act1Interactable = stage.interactables[id]
	player.look_at_point(point.global_position)
	await create_timer(0.22).timeout
	var found := "none"
	if player.current_target != null:
		found = str(player.current_target.get("interaction_id"))
	log_line("HOLD_AIM %s target=%s" % [id, found])
	if found != id:
		return false
	Input.action_press("interact")
	for i in range(int(seconds * 60.0)):
		await physics_frame
		if not Input.is_action_pressed("interact"):
			break
	Input.action_release("interact")
	await create_timer(0.3).timeout
	return true


func _run() -> void:
	scene = (load("res://act1/act01.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await create_timer(1.1).timeout
	stage = scene
	player = stage.local_player
	log_line("START pos=%s" % str(player.global_position))
	check(not player.downed and player.is_on_floor(), "spawn is on solid floor")

	# --- A. entry ---------------------------------------------------------
	await walk(Vector3(0, 0, 12.0), 3.0, "entry approach")
	await walk(Vector3(0, 0, 10.6), 1.8, "door rail")
	for i in range(4):
		var ok := await press_id("shove_gantry", 0.10)
		if ok:
			await create_timer(0.6).timeout
		if stage.flags["debris_cleared"]:
			break
	check(stage.flags["debris_cleared"], "collapsed gantry physically cleared from the door rail")
	await walk(Vector3(3.1, 0, 10.35), 2.2, "latch side")
	await press_id("release_latch", 0.12)
	check(stage.flags["latch_released"], "mechanical latch released")
	await walk(Vector3(1.0, 0, 10.0), 1.6, "door front")
	await hold_id("door_handle", 6.2)
	check(stage.flags["door_open"], "industrial door opened and collider moved with it")
	await walk(Vector3(0, 0, 6.5), 2.5, "through doorway")
	check(player.global_position.z < 8.0, "walked through the open doorway (no invisible wall)")

	# --- B. power cart ----------------------------------------------------
	await walk(Vector3(0, 0, 4.0), 2.0, "airlock exit")
	await walk(Vector3(-3.0, 0, 0.4), 2.5, "power room west")
	await walk(Vector3(-7.8, 0, 0.4), 3.0, "power room north")
	await walk(Vector3(-8.0, 0, -2.5), 1.7, "cart rear")
	await press_id("cart_push", 0.12)
	check(player.external_hold, "gripped the 70 kg power trolley handle")
	Input.action_press("move_forward")
	for i in range(150):
		await physics_frame
	Input.action_release("move_forward")
	await create_timer(0.3).timeout
	log_line("CART pushed to %.2f path_blocked=%s" % [stage.builder.power_cart.global_position.x, str(stage.builder.power_cart.path_blocked)])
	# release the handle (module-specific Q = act1_cancel)
	Input.action_press("act1_cancel")
	await create_timer(0.16).timeout
	Input.action_release("act1_cancel")
	await create_timer(0.4).timeout
	check(not player.external_hold, "released trolley handle")
	# go around and kick the fallen rail bracket off
	await walk(Vector3(-4.6, 0, -0.4), 2.4, "around cart north")
	await walk(Vector3(-1.0, 0, -0.5), 3.0, "rail bracket")
	await walk(Vector3(-0.95, 0, -1.15), 1.2, "bracket approach")
	await press_id("rail_shove", 0.10)
	await create_timer(0.8).timeout
	check(stage.flags["rail_cleared"], "rail bracket cleared from the trolley path")
	# return behind the cart
	await walk(Vector3(-1.0, 0, -0.4), 1.8, "return north")
	await walk(Vector3(-7.8, 0, -0.4), 3.2, "cart rear north")
	await walk(Vector3(-7.8, 0, -2.55), 1.3, "cart rear center")
	await walk(Vector3(-7.2, 0, -2.55), 0.8, "cart handle")
	await press_id("cart_push", 0.12)
	check(player.external_hold, "regripped trolley after clearing the rail")
	Input.action_press("move_forward")
	for i in range(520):
		await physics_frame
	Input.action_release("move_forward")
	await create_timer(1.0).timeout
	Input.action_press("act1_cancel")
	await create_timer(0.16).timeout
	Input.action_release("act1_cancel")
	await create_timer(0.4).timeout
	check(stage.builder.power_cart.docked, "trolley physically rolled into the dock tolerance")
	check(stage.flags["power_docked"], "host registered the physical dock")
	# winch + clamp: both on the maintenance side of the socket
	await walk(Vector3(1.5, 0, -0.5), 1.8, "cart west north")
	await walk(Vector3(1.5, 0, -5.0), 2.4, "socket west")
	await walk(Vector3(1.95, 0, -5.0), 0.8, "winch")
	await press_id("power_winch", 0.12)
	for i in range(360):
		if stage.builder.power_cart.module_transferred_flag:
			break
		await create_timer(1.0 / 60.0).timeout
	check(stage.builder.power_cart.module_transferred_flag, "power module physically traversed the guide rail")
	await walk(Vector3(2.4, 0, -4.3), 1.2, "clamp west")
	await press_id("power_clamp", 0.12)
	# MECHANICS-001B-R2：锁爪是实体机械，需要真实转动时间才能闭合到位
	for i in range(220):
		if stage.flags["power_ready"]:
			break
		await create_timer(1.0 / 60.0).timeout
	check(stage.flags["power_ready"], "power module clamped and control circuit live")
	snapshots["power"] = stage.build_snapshot(0)

	# --- C. ventilation ---------------------------------------------------
	await walk(Vector3(0, 0, -8.0), 3.0, "power exit")
	await walk(Vector3(-1.0, 0, -12.8), 3.0, "vent threshold")
	check(player.global_position.z < -11.5, "walked into the ventilation hall")
	await walk(Vector3(7.0, 0, -14.8), 4.0, "hall north east")
	await walk(Vector3(7.0, 0, -17.5), 2.0, "hall east")
	await walk(Vector3(7.7, 0, -22.3), 2.5, "rotor lock")
	await press_id("rotor_lock", 0.12)
	check(stage.flags["rotor_lock_released"], "rotor lock physically removed")
	await walk(Vector3(8.1, 0, -28.15), 3.8, "coupling")
	await press_id("coupling", 0.12)
	check(stage.flags["coupling_engaged"], "drive coupling engaged")
	await walk(Vector3(7.0, 0, -14.8), 4.5, "hall return north")
	await walk(Vector3(-7.8, 0, -14.8), 7.0, "control gallery north")
	await walk(Vector3(-7.8, 0, -18.0), 1.8, "control gallery")
	await walk(Vector3(-7.8, 0, -23.0), 2.4, "fan start")
	await press_id("start_fan", 0.12)
	check(stage.builder.vent.running, "main fan started")
	check(stage.flags["fan_started"], "fan start registered")
	await walk(Vector3(-7.8, 0, -14.8), 3.0, "west gallery north")
	await walk(Vector3(7.0, 0, -14.8), 7.0, "damper side north")
	await walk(Vector3(7.0, 0, -18.0), 1.8, "damper side")
	await walk(Vector3(8.0, 0, -29.6), 5.0, "damper control")
	await press_id("damper", 0.12)
	check(stage.flags["damper_open"], "main duct damper opened")
	# get clear of the main outflow during the pressure test
	await walk(Vector3(8.0, 0, -34.0), 3.0, "safe south")
	var wait := 0
	while wait < 12 and not stage.flags["vent_complete"]:
		await create_timer(1.0).timeout
		wait += 1
		log_line("VENT t=%d speed=%.2f damper=%.2f pressure=%.2f complete=%s pos=%s" % [wait, stage.builder.vent.speed, stage.builder.vent.damper, stage.builder.vent.pressure, str(stage.flags["vent_complete"]), str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	check(stage.flags["vent_complete"], "6-second live pressure test completed")
	snapshots["vent"] = stage.build_snapshot(0)

	# --- D. station -------------------------------------------------------
	await walk(Vector3(7.0, 0, -35.4), 2.5, "hall south")
	await walk(Vector3(0.0, 0, -35.6), 4.0, "hall center")
	await walk(Vector3(0.0, 0, -37.6), 2.4, "station threshold")
	check(player.global_position.z < -37.0, "station threshold is walkable")
	await walk(Vector3(-5.6, 0, -40.5), 3.5, "station west")
	await walk(Vector3(-5.6, 0, -44.3), 2.5, "chock approach")
	await walk(Vector3(-5.62, 0, -45.5), 1.4, "chock")
	await press_id("chock", 0.12)
	check(stage.flags["chock_removed"], "wheel chock removed")
	await walk(Vector3(-4.5, 0, -40.6), 2.4, "station return")
	await walk(Vector3(0.0, 0, -38.2), 2.0, "station center")
	await walk(Vector3(7.2, 0, -38.2), 3.5, "ramp north")
	await walk(Vector3(7.2, 1.55, -43.0), 3.5, "platform ramp")
	check(player.global_position.y > 1.2, "walked up the boarding ramp")
	await walk(Vector3(7.35, 1.55, -48.2), 3.0, "platform brake side")
	await walk(Vector3(6.55, 1.55, -48.6), 1.2, "brake")
	await press_id("parking_brake", 0.12)
	# MECHANICS-001E-R2：销爪是实体机械，需真实抽出时间才能解除
	for i in range(200):
		if stage.flags["brake_released"]:
			break
		await create_timer(1.0 / 60.0).timeout
	check(stage.flags["brake_released"], "parking brake released")
	# MECHANICS-001F：货舱固定带改成矿车上的真实棘轮，交互点在货台东侧；
	# 玩家要站到站台边、隔着登车缺口摇 7 档棘轮（每档 0.55 s 的真实行程）。
	await walk(Vector3(6.55, 1.55, -46.2), 2.0, "platform cargo side")
	await walk(Vector3(5.35, 1.55, -47.05), 1.6, "cargo ratchet")
	var cargo_presses := 0
	for n in range(10):
		if stage.flags["cargo_secured"]:
			break
		var aimed := await press_id("cargo", 0.12)
		if not aimed:
			break
		cargo_presses += 1
		await create_timer(0.6).timeout
	log_line("CARGO presses=%d tension=%.0f secured=%s" % [
		cargo_presses,
		stage.builder.cargo_rig.tension() if stage.builder.cargo_rig != null else -1.0,
		str(stage.flags["cargo_secured"])])
	check(stage.flags["cargo_secured"], "cargo restraint locked (real ratchet tension)")
	# board through the open east side of the V2.3 cart, going around the real cargo
	# crate (it is a solid 100 kg body; walking into it no longer pushes it around)
	await walk(Vector3(5.35, 1.55, -48.30), 2.0, "platform edge aft")
	await walk(Vector3(4.05, 1.55, -48.40), 1.8, "cart entry")
	await walk(Vector3(2.10, 1.55, -48.65), 1.8, "around cargo")
	await walk(Vector3(0.0, 1.55, -49.30), 1.8, "cart deck")
	check(stage.all_active_aboard(), "player physically inside the mine cart")
	await walk(Vector3(-3.0, 1.55, -50.0), 2.6, "launch console")
	var cr: Act1CargoRig = stage.builder.cargo_rig
	if cr != null:
		log_line("CARGO_STATE secured=%s tension=%.0f clicks=%d inzone=%s latch=%s pawl=%.2f flag=%s crate_local=%s" % [
			str(cr.secured()), cr.tension(), cr.clicks, str(cr.crate_in_zone()),
			str(cr.latch_open), cr.pawl_depth, str(stage.flags["cargo_secured"]),
			str(cr.to_local(cr.crate.global_position).snapped(Vector3(0.01, 0.01, 0.01)))])
	await press_id("launch_cart", 0.12)
	check(stage.flags["departure_started"], "departure interlock accepted all real tasks")
	check(player.external_hold, "rider attached to moving cart")
	var cart_start: float = stage.builder.mine_cart.global_position.z
	await create_timer(2.0).timeout
	var cart_after: float = stage.builder.mine_cart.global_position.z
	check(cart_after < cart_start - 2.0, "cart physically travelled down the rails")
	snapshots["launch"] = stage.build_snapshot(0)
	# wait for handoff; the module records the completion via the SessionBridge
	await create_timer(8.0).timeout
	var completion: Dictionary = stage.bridge.recorded_completion()
	var handoff_ok := bool(completion.get("completed", false))
	check(handoff_ok, "Act01 completion recorded through Act1SessionBridge (completed=true)")
	check(bool(stage.flags.get("handoff", false)) or handoff_ok, "handoff flag set or completion recorded")
	var report := {
		"passed": failures.is_empty(),
		"failures": failures,
		"flags": snapshots.get("launch", {}).get("flags", {}),
		"credits": snapshots.get("launch", {}).get("credits", {}),
		"snapshots": snapshots,
		"completion": completion,
		"mode": "standalone",
		"log": log_lines,
	}
	var f := FileAccess.open("res://../tests-out/act1_solo_full_run.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	log_line("RESULT failures=%d completion=%s" % [failures.size(), str(completion.get("completed", false))])
	quit(0 if failures.is_empty() else 1)