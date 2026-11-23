extends SceneTree

## Component + sequence test for Resonance 05. Real input actions drive doors,
## levers, the capture claw and the isolation carriage; teleports are only used
## between stations so each mechanism is tested in isolation.

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var hud: GameHud
var core: CoreRig
var failures: int = 0
var checks: Array[Dictionary] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok": ok, "label": label, "details": details})
	if not ok:
		failures += 1
	print("CHECK ", "OK   " if ok else "FAIL ", label, " ", JSON.stringify(details))


func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame


func seconds(value: float) -> void:
	await frames(int(value * 60.0))


func press_key(action: String) -> void:
	Input.action_press(action)
	await frames(2)
	Input.action_release(action)
	await frames(2)


func hold(action: String, duration: float) -> void:
	Input.action_press(action)
	await seconds(duration)
	Input.action_release(action)
	await seconds(0.15)


func teleport(pos: Vector3, yaw: float, pitch: float = -0.1) -> void:
	player.force_exit_operate()
	player.teleport(pos, yaw, pitch)
	await frames(6)


func log_state(tag: String) -> void:
	print("STATE ", tag, " pos=", player.global_position, " stage=", story.stage, " cp=", story.checkpoint,
		" net=", snappedf(core.get_net(), 0.001), " angle=", snappedf(core.get_angle(), 0.001),
		" L=", snappedf(level.left_cart.get_p(), 0.01), " R=", snappedf(level.right_cart.get_p(), 0.01),
		" locked=", core.is_locked(), " cap=", core.is_capturable())


func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://tests-out"
	DirAccess.make_dir_recursive_absolute(out_dir)
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(10)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	hud = app.get("hud") as GameHud
	core = level.core
	hud.title_layer.visible = false
	await frames(30)
	log_state("boot")
	check(player != null and level != null and story != null, "boot: nodes present")
	check(player.global_position.distance_to(LevelBuilder.SPAWN_POSITION) < 0.3, "spawn position", {"pos": str(player.global_position)})
	var on_floor: bool = await is_on_floor_soon()
	check(on_floor, "spawn on floor")

	# 1. walking in the entrance tunnel
	var start: Vector3 = player.global_position
	Input.action_press("move_forward")
	await seconds(2.5)
	Input.action_release("move_forward")
	await seconds(0.4)
	var moved: float = player.global_position.distance_to(start)
	check(moved > 4.0, "walk forward in tunnel", {"moved": moved})
	check(player.global_position.y > 3.5, "tunnel floor collision holds player")

	# 2. jammed shutter opened with real W hold
	await teleport(Vector3(0, 4.06, 25.7), 0.0, -0.05)
	await frames(4)
	check(level.push_door.get_prompt().contains("E"), "door prompt is reachable", {"prompt": level.push_door.get_prompt()})
	await press_key("interact")
	check(player.operating, "door grab enters operating mode")
	await hold("move_forward", 3.6)
	check(level.push_door.is_opened, "door opens after sustained push", {"progress": level.push_door.progress})
	await press_key("interact")
	check(not player.operating, "E releases door")
	await teleport(Vector3(0, 4.06, 22.0), 0.0, 0.0)
	await frames(20)
	check(player.global_position.z < 23.0, "player can pass through open shutter")

	# 3. hall trigger and checkpoint
	await teleport(Vector3(0, 4.06, 12.6), 0.0, -0.15)
	await frames(12)
	check(story.stage >= StoryDirector.Stage.DISCOVER_INSTABILITY, "hall trigger advances mission", {"stage": story.stage})
	check(story.checkpoint == 1, "hall checkpoint set", {"checkpoint": story.checkpoint})

	await teleport(Vector3(0, 0.06, 8.0), 0.0, -0.2)
	await seconds(1.0)
	check(player.global_position.y > -0.2, "hall floor collision holds player", {"pos": str(player.global_position), "on_floor": player.is_on_floor()})

	# 4. left lever: real grab, real push, real reverse
	await teleport(Vector3(-9.025, 1.66, 7.625), -PI * 0.25, -0.45)
	await frames(6)
	check(player.current_target != null, "left station is detected", {"target": str(player.current_target)})
	await press_key("interact")
	check(player.operating, "left lever grabbed")
	var p0: float = level.left_cart.get_p()
	await hold("move_forward", 1.6)
	var p1: float = level.left_cart.get_p()
	check(p1 > p0 + 0.15, "left cart moves outward with W", {"before": p0, "after": p1})
	await hold("move_back", 0.9)
	var p2: float = level.left_cart.get_p()
	check(p2 < p1 - 0.05, "left cart reverses with S", {"before": p1, "after": p2})
	await press_key("interact")
	check(not player.operating, "left lever released")
	await seconds(0.8)
	log_state("after left lever")

	# 5. right lever: move inward to reduce the rightward moment
	await teleport(Vector3(9.025, 1.66, 7.625), PI * 0.25, -0.45)
	await frames(6)
	check(player.current_target != null, "right station is detected")
	await press_key("interact")
	check(player.operating, "right lever grabbed")
	await hold("move_back", 3.5)
	await press_key("interact")
	await seconds(1.0)
	log_state("after right lever")
	check(core.get_net() < 0.5, "right cart inward reduces net moment", {"net": core.get_net()})

	# 6. failed lock outside capture range
	if not core.is_capturable():
		await teleport(Vector3(0, 0.06, 9.1), 0.0, -0.18)
		await frames(8)
		await press_key("interact")
		await seconds(0.6)
		check(not core.is_locked(), "lock fails while unbalanced")
		check(story.lock_attempts >= 1, "failure counted", {"attempts": story.lock_attempts, "net": core.get_net()})
	else:
		print("SKIP failed-lock check: core already capturable")

	# 7. balance both carts using real lever input until the core is capturable
	await balance_with_real_input()

	# 7b. V2 interlock: the claw hydraulics only press once both stabiliser legs
	# are latched. The legs have their own acceptance coverage in
	# test_solo_coop.gd; here the leg state is set directly so this component
	# suite keeps testing balance -> claw -> isolation.
	for i in range(level.stabilizers.size()):
		level.stabilizers[i].latched = true
		level.core.set_stabilizer_latched(i, true)
	await frames(10)

	# 8. lock the core
	await teleport(Vector3(0, 0.06, 9.1), 0.0, -0.18)
	await frames(8)
	check(core.is_capturable(), "core capturable before lock", {"net": core.get_net(), "omega": core.get_omega()})
	await press_key("interact")
	check(core.is_locking() or core.is_locked(), "capture claw starts closing")
	await seconds(2.2)
	check(core.is_locked(), "core locked")
	check(story.checkpoint == 2, "lock checkpoint set", {"checkpoint": story.checkpoint})
	await seconds(2.2)
	log_state("after lock")

	# 9. isolation interlock + pin + carriage
	# V2: the sliding carriage is held by residual vibration until the extraction
	# damper is loaded, so load the damper crank with real input first.
	await teleport(Vector3(6.4, 0.06, -2.3), 0.0, -0.12)
	await frames(8)
	await press_key("interact")
	await hold("move_forward", 2.4)
	check(level.damper.latched_flag, "extraction damper loaded", {"pressure": level.damper.pressure})
	await press_key("interact")

	await teleport(Vector3(10.85, 0.06, -5.95), 0.0, -0.18)
	await frames(8)
	check(level.isolation.pin_out == false, "isolation pin initially in")
	await press_key("interact")
	await seconds(0.3)
	check(level.isolation.pin_out, "safety pin pulled with E")
	await press_key("interact")
	check(player.operating, "isolation lever grabbed")
	await hold("move_forward", 3.0)
	check(level.isolation.separated_flag, "coupling separated by pushing carriage", {"progress": level.isolation.progress})
	await press_key("interact")
	await seconds(2.2)
	check(level.data_plinth.revealed_flag, "navigation data revealed after isolation")

	# 10. take navigation data
	await teleport(Vector3(-3.0, 0.06, -8.1), 0.0, -0.4)
	await frames(8)
	print("DATA_PLINTH pos=", level.data_plinth.global_position, " area=", level.data_plinth.area.global_position,
		" layer=", level.data_plinth.area.collision_layer, " prompt='", level.data_plinth.get_prompt(),
		"' player=", player.global_position, " yaw=", player.yaw, " target=", player.current_target,
		" in_group=", level.data_plinth.is_in_group("interactable"))
	check(level.data_plinth.revealed_flag, "data plinth revealed")
	await press_key("interact")
	await seconds(0.5)
	check(story.data_taken, "navigation data taken")
	check(level.exit_door.should_open, "exit door unlocked")
	await seconds(4.0)
	check(level.exit_door.open_progress > 0.6, "exit door opens", {"progress": level.exit_door.open_progress})

	# 11. walk into exit trigger
	# V2: this component suite never took part in phase B (no recoil brace), so
	# the crew gate must refuse the finale instead of completing the chapter. The
	# full completion path is covered by test_solo_coop.gd.
	var session: CoopSession = app.get("session") as CoopSession
	await teleport(Vector3(-24.5, 0.06, -2.0), PI * 0.5, 0.0)
	await frames(20)
	check(story.stage != StoryDirector.Stage.COMPLETED, "chapter waits for the crew gate", {"stage": story.stage})
	check(not session.can_finish() and session.gate_text() != "", "gate names the missing phase", {"gate": session.gate_text()})

	var report: Dictionary = {
		"ok": failures == 0,
		"failures": failures,
		"checks": checks,
		"final_stage": story.stage,
		"lock_attempts": story.lock_attempts,
		"surges": story.surges,
	}
	var f: FileAccess = FileAccess.open(out_dir + "/flow_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("FLOW_REPORT ", JSON.stringify({"ok": failures == 0, "failures": failures, "checks": checks.size()}))
	quit(0 if failures == 0 else 1)


func is_on_floor_soon() -> bool:
	await seconds(0.3)
	return player.is_on_floor()


func balance_with_real_input() -> void:
	# Bring the right cart in until low, then trim with the left cart outward.
	await teleport(Vector3(9.025, 1.66, 7.625), PI * 0.25, -0.45)
	await frames(4)
	if player.current_target != null and not player.operating:
		await press_key("interact")
	if player.operating:
		await hold("move_back", 3.2)
		await press_key("interact")
	await seconds(0.8)
	log_state("balance right")
	if not core.is_capturable():
		await teleport(Vector3(-9.025, 1.66, 7.625), -PI * 0.25, -0.45)
		await frames(4)
		if player.current_target != null and not player.operating:
			await press_key("interact")
		if player.operating:
			await hold("move_forward", 2.2)
			await press_key("interact")
		await seconds(1.2)
	log_state("balance left")
	# fine trim in small nudges
	var guard: int = 0
	while not core.is_capturable() and guard < 6:
		guard += 1
		var net: float = core.get_net()
		if net > 0.14:
			await teleport(Vector3(9.025, 1.66, 7.625), PI * 0.25, -0.45)
			await frames(3)
			if player.current_target != null and not player.operating:
				await press_key("interact")
			if player.operating:
				await hold("move_back", 0.8)
				await press_key("interact")
		elif net < -0.14:
			await teleport(Vector3(9.025, 1.66, 7.625), PI * 0.25, -0.45)
			await frames(3)
			if player.current_target != null and not player.operating:
				await press_key("interact")
			if player.operating:
				await hold("move_forward", 0.8)
				await press_key("interact")
		await seconds(1.0)
	log_state("balance final")
