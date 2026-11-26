extends SceneTree

## Single-player acceptance test for Resonance 05 V2.
##
## Everything here goes through the real interaction path: the player is walked
## or teleported to a station, `E` is delivered as the real "interact" action,
## pumping is the real W input, and the machines own their own state. Teleports
## are used only to move between stations (the same standard as the baseline
## probe) and never to fake a mechanical result.

var app: Node3D
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var hud: GameHud
var session: CoopSession
var surge: SurgeDirector
var checks: Array[Dictionary] = []
var t0: int = 0
var out_path: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-04-05-coop-vertical-slice/tests-out/solo_coop.json"


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func wait(seconds: float) -> void:
	# Simulated-time wait: counted in physics frames, so the same script behaves
	# identically in real time and in --write-movie (fixed-step) recording.
	var count: int = maxi(1, int(round(seconds * 60.0)))
	for _i in range(count):
		await physics_frame


func wait_until(cond: Callable, timeout: float) -> bool:
	# Frame-counted timeout for the same reason as wait().
	var budget: int = maxi(1, int(round(timeout * 60.0)))
	for _i in range(budget):
		if bool(cond.call()):
			return true
		await physics_frame
	return bool(cond.call())


func check(name: String, ok: bool, detail: String = "") -> bool:
	checks.append({"name": name, "ok": ok, "detail": detail})
	print(("PASS  " if ok else "FAIL  ") + name + (("  |  " + detail) if detail != "" else ""))
	return ok


func yaw_to(from: Vector3, to: Vector3) -> float:
	var d: Vector3 = to - from
	return atan2(-d.x, -d.z)


func pitch_to(from: Vector3, to: Vector3) -> float:
	var flat: float = Vector2(to.x - from.x, to.z - from.z).length()
	return -atan2(to.y - (from.y + 1.62), flat)


func stand(pos: Vector3, target: Vector3) -> void:
	player.force_exit_operate()
	player.stop_grab()
	player.external_hold = false
	player.teleport(pos, yaw_to(pos, target), clampf(pitch_to(pos, target), -1.1, 1.1))
	await frames(8)


func press_interact() -> void:
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(3)


func hold_forward(seconds: float) -> void:
	Input.action_press("move_forward")
	await wait(seconds)
	Input.action_release("move_forward")
	await frames(3)


func hold_back(seconds: float) -> void:
	Input.action_press("move_back")
	await wait(seconds)
	Input.action_release("move_back")
	await frames(3)


func release_all() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "interact", "sprint", "jump"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func credits(pid: int) -> Array:
	var record: Dictionary = session.ledger.get_record(pid)
	return (record.get("credits", {}) as Dictionary).keys()


func run() -> void:
	t0 = Time.get_ticks_msec()
	app = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(app)
	current_scene = app
	await frames(90)
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	hud = app.get("hud") as GameHud
	session = app.get("session") as CoopSession
	surge = app.get("surge") as SurgeDirector
	hud.title_layer.visible = false
	hud.clear_subtitles()

	check("scene_built", level != null and level.core != null and level.catwalk != null)
	check("new_machines_present", level.stabilizers.size() == 2 and level.brake != null and level.damper != null and level.duty_board != null)
	check("participant_registered", session.ledger.player_ids().size() == 1 and session.ledger.status_of(1) == "active")

	# Enter the hall through the real trigger so the mission arms normally.
	await stand(Vector3(0, 4.06, 12.6), Vector3(0, 4.06, 6.0))
	await wait(0.8)
	check("hall_entered", story.stage >= StoryDirector.Stage.DISCOVER_INSTABILITY, "stage=%d" % story.stage)

	# --- Phase A: stabiliser legs ------------------------------------------
	var east_anchor: Vector3 = level.stabilizers[1].anchor.origin
	await stand(east_anchor + Vector3(0, 0, -0.6), level.stabilizers[1].global_position + Vector3(0, 1.2, 0))
	check("east_station_targeted", player.current_target == level.stabilizers[1], "target=%s" % (player.current_target.name if player.current_target != null else "none"))
	await press_interact()
	check("east_station_claimed", session.claim_owner("stabilizer_e") == 1, "owner=%d" % session.claim_owner("stabilizer_e"))
	await hold_forward(6.0)   # R4: 5.80 m stroke is ~4.1 s at full flow
	check("east_leg_latched", level.stabilizers[1].latched, "ext=%.2f press=%.2f" % [level.stabilizers[1].extension, level.stabilizers[1].pressure])
	await press_interact()

	# MECHANICS-005A-R4: with the R0 swing restored (peak 0.50 rad = 28.6 deg) the
	# ring is 10.2 m off-axis on the west side, so the west pad physically cannot
	# reach it until the counterweights bring the core into the capture window.
	# This is the intended mechanic, not a regression: balance first, then seat
	# the second leg. The west leg is pumped after the counterweight phase below.
	check("stabilizers_latched_pending_balance", level.stabilizers_latched() == 1,
		"latched=%d" % level.stabilizers_latched())

	# --- Lock interlock is real before balancing ---------------------------
	await stand(Vector3(0, 0.06, 10.1), Vector3(0, 1.2, 8.6))
	var relock: Dictionary = level.core.request_lock()
	check("lock_refused_only_when_out_of_range", not bool(relock.get("ok", false)), str(relock.get("reason", "")))

	# --- Phase A: counterweight, real lever input --------------------------
	await stand(Vector3(-8.5, 1.70, 7.47), level.left_station.area.global_position)
	check("left_station_targeted", player.current_target == level.left_station, "target=%s" % (player.current_target.name if player.current_target != null else "none"))
	await press_interact()
	check("left_station_operating", player.operating and session.claim_owner("cart_left") == 1)
	await hold_forward(1.6)
	await press_interact()

	await stand(Vector3(8.5, 1.70, 7.47), level.right_station.area.global_position)
	await press_interact()
	# Right cart starts at the far outside: pulling it in reduces the net moment.
	var initial_net: float = level.core.get_net()
	await hold_back(7.0)
	await press_interact()
	var final_net: float = level.core.get_net()
	check("counterweight_changed_core", absf(final_net) < absf(initial_net) - 0.10, "net %.3f -> %.3f" % [initial_net, final_net])
	check("credit_counterweight", session.ledger.has_credit(1, "counterweight_effect"))

	# Nudge until capturable (still through the real lever).
	var tries: int = 0
	while not level.core.is_capturable() and tries < 12:
		tries += 1
		await stand(Vector3(8.5, 1.70, 7.47), level.right_station.area.global_position)
		await press_interact()
		if level.core.get_net() > 0.0:
			await hold_back(1.2)
		else:
			await hold_forward(1.2)
		await press_interact()
		await wait(0.8)
	check("core_capturable_with_two_legs", level.core.is_capturable(), "net=%.3f omega=%.3f tries=%d" % [level.core.get_net(), level.core.get_omega(), tries])

	# --- Phase A: second leg, now that the core is inside the capture window ---
	var west_anchor: Vector3 = level.stabilizers[0].anchor.origin
	await stand(west_anchor + Vector3(0, 0, -0.6), level.stabilizers[0].global_position + Vector3(0, 1.2, 0))
	await press_interact()
	# R4: the ring must be inside the pad's reach for the whole pump. Wait for the
	# swing to settle rather than pumping into a moving target.
	# R4: the core swings at the R0 amplitude, so a leg pumped while the ring is
	# on the far side simply runs to its end stop in clear air - correct physics.
	# A human retracts and tries again; this loop does the same, up to 6 attempts.
	var wl_tries: int = 0
	while not level.stabilizers[0].latched and wl_tries < 6:
		wl_tries += 1
		# retract fully, wait for the ring to come back into reach, pump again
		Input.action_press("move_back")
		await wait(4.5)
		Input.action_release("move_back")
		await frames(4)
		var settle: int = 0
		while settle < 600:
			settle += 1
			if absf(level.core.get_omega()) < 0.20 and absf(level.core.get_angle()) < 0.09:
				break
			await frames(1)
		await hold_forward(6.0)
	check("west_leg_latched", level.stabilizers[0].latched,
		"ext=%.2f angle=%.3f tries=%d" % [level.stabilizers[0].extension,
			level.core.get_angle(), wl_tries])
	await press_interact()
	check("stabilizers_latched", level.stabilizers_latched() == 2)
	check("credit_stabilizer", session.ledger.has_credit(1, "stabilizer_lock"))
	check("capture_limit_widened", is_equal_approx(level.core.capture_net_limit(), 0.25), "limit=%.3f" % level.core.capture_net_limit())

	# --- Phase A/B: emergency brake + surge warning ------------------------
	await stand(Vector3(-13.1, 0.06, -2.4), Vector3(-12.0, 1.3, -5.2))
	check("brake_station_targeted", player.current_target == level.brake, "target=%s" % (player.current_target.name if player.current_target != null else "none"))
	await press_interact()
	await hold_forward(2.2)
	check("brake_latched", level.brake.latched, "pressure=%.2f" % level.brake.pressure)
	check("credit_brake", session.ledger.has_credit(1, "brake_charge"))
	await press_interact()

	# Force the guaranteed recoil, then hold a catwalk rail through it.
	surge._begin_warning()
	await wait(0.4)
	await stand(Vector3(-12.0, 3.48, -4.1), Vector3(-13.1, 4.45, -3.45))
	check("catwalk_grab_targeted", player.current_target is GrabPoint, "target=%s" % (player.current_target.name if player.current_target != null else "none"))
	await press_interact()
	check("catwalk_grabbed", player.grabbing)
	var pins_before: int = level.catwalk.pins_seated
	await wait(4.2)
	check("surge_fired", surge.surge_count >= 1, "count=%d severity=%.2f" % [surge.surge_count, surge.severity])
	check("brace_credit", session.ledger.has_credit(1, "brace_hold"))
	check("surge_response_credit", session.ledger.has_credit(1, "surge_response"))
	check("catwalk_reacted", level.catwalk.max_tilt_seen > 0.02 or level.catwalk.pins_seated < pins_before, "max_tilt=%.3f pins %d->%d" % [level.catwalk.max_tilt_seen, pins_before, level.catwalk.pins_seated])
	await press_interact()
	check("catwalk_released", not player.grabbing)

	# --- Phase A/B: re-seat the pins on the deck --------------------------
	await stand(Vector3(-10.6, 3.48, -4.35), Vector3(-11.1, 3.6, -3.85))
	check("lock_station_targeted", player.current_target is CatwalkStation, "target=%s" % (player.current_target.name if player.current_target != null else "none"))
	await press_interact()
	await hold_forward(2.0)
	check("catwalk_pins_back", level.catwalk.pins_seated == 2, "pins=%d" % level.catwalk.pins_seated)
	await press_interact()
	await stand(Vector3(-10.6, 3.48, -4.35), Vector3(-11.1, 3.6, -3.85))
	await press_interact()
	await hold_forward(1.8)
	await press_interact()
	check("catwalk_preloaded", level.catwalk.preload_state > 0.9, "preload=%.2f" % level.catwalk.preload_state)

	# --- Phase C: lock the core -------------------------------------------
	await stand(Vector3(0, 0.06, 10.1), Vector3(0, 1.2, 8.6))
	check("lock_station_targeted_final", player.current_target == level.lock_rig, "target=%s" % (player.current_target.name if player.current_target != null else "none"))
	await press_interact()
	await wait(2.2)
	check("core_locked", level.core.is_locked(), "stage=%d" % story.stage)
	check("credit_lock_assist", session.ledger.has_credit(1, "lock_assist"))
	check("stage_after_lock", story.stage >= StoryDirector.Stage.DISCOVER_FEEDBACK, "stage=%d" % story.stage)

	# --- Phase C: damper + isolation --------------------------------------
	await wait(1.0)
	await stand(Vector3(6.4, 0.06, -2.3), Vector3(6.4, 1.2, -4.4))
	check("damper_station_targeted", player.current_target == level.damper, "target=%s" % (player.current_target.name if player.current_target != null else "none"))
	await press_interact()
	await hold_forward(2.2)
	check("damper_latched", level.damper.latched_flag, "pressure=%.2f" % level.damper.pressure)
	check("credit_damper", session.ledger.has_credit(1, "damper_latch"))
	await press_interact()

	await stand(Vector3(10.7, 0.06, -5.0), Vector3(10.6, 1.3, -8.6))
	check("isolation_targeted", player.current_target == level.isolation, "target=%s" % (player.current_target.name if player.current_target != null else "none"))
	await press_interact()
	check("isolation_pin_out", level.isolation.pin_out)
	check("credit_isolation_pin", session.ledger.has_credit(1, "isolation_pin"))
	await press_interact()
	check("isolation_operating", player.operating)
	await hold_forward(3.0)
	check("isolation_separated", level.isolation.separated_flag, "progress=%.2f" % level.isolation.progress)
	check("credit_carriage_push", session.ledger.has_credit(1, "carriage_push"))
	await wait(2.2)

	# --- Data and exit -----------------------------------------------------
	await stand(Vector3(-3.0, 0.06, -8.0), Vector3(-3.0, 1.0, -9.1))
	check("data_targeted", player.current_target == level.data_plinth, "target=%s" % (player.current_target.name if player.current_target != null else "none"))
	await press_interact()
	await wait(1.0)
	check("data_taken", story.data_taken)
	check("credit_data", session.ledger.has_credit(1, "data_take"))
	# The blast door lifts at 0.38 m/s of travel over ~2.6 s; wait for the
	# mechanism to finish instead of sampling it one second after the data.
	var door_open: bool = await wait_until(func() -> bool: return level.exit_door.is_opened, 6.0)
	check("exit_door_open", door_open, "progress=%.2f" % level.exit_door.open_progress)

	check("all_phases_ready", session.ledger.is_ready(1), "kinds=%s" % str(credits(1)))
	check("gate_open", session.can_finish())
	await stand(Vector3(-25.5, 0.06, -2.0), Vector3(-27.5, 1.2, -2.0))
	await wait(1.2)
	check("stage_completed", story.stage == StoryDirector.Stage.COMPLETED, "stage=%d" % story.stage)
	check("run_completed_flag", story.completed_flag())
	check("end_text_has_crew", story.completion_text().contains("全员参与记录"))

	release_all()
	var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
	var passed: int = 0
	var failed: int = 0
	for c in checks:
		if bool(c["ok"]):
			passed += 1
		else:
			failed += 1
	print("SOLO_RESULT pass=%d fail=%d elapsed=%.1f" % [passed, failed, elapsed])
	var report: Dictionary = {
		"test": "solo_coop_acceptance",
		"passed": passed,
		"failed": failed,
		"elapsed": elapsed,
		"checks": checks,
		"ledger": session.ledger.snapshot(),
		"stage": story.stage,
	}
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	quit()
