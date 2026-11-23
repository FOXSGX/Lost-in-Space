extends Node

## Two-instance co-op automation for the Resonance 05 V2 network slice.
##
## Started by App when launched with --auto=host or --auto=client. Each process
## drives its own first-person body through the real input actions and the real
## claim/axis protocol; no gameplay state is written directly except teleporting
## between stations (documented in the test report).
##
## The scenario deliberately creates mutual dependency:
##   * the host cannot latch the east leg and the client the west leg alone -
##     the claw interlock needs BOTH legs,
##   * the host loads the damper and the client pulls the pin + pushes the
##     carriage - the carriage is blocked without the damper,
##   * both must hold a catwalk rail through the recoil to earn phase B,
##   * the exit gate refuses until both participants are ready.

var role: String = "host"
var app: Node
var player: PlayerController
var level: LevelBuilder
var story: StoryDirector
var session: CoopSession
var net: CoopNet
var surge: SurgeDirector
var hud: GameHud
var checks: Array[Dictionary] = []
var t0: int = 0
var out_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-04-05-coop-vertical-slice"
var shot_dir: String = "C:/Users/ASUS/Desktop/迷失太空/work/deepseek-resonance-04-05-coop-vertical-slice/evidence/coop"


func _ready() -> void:
	t0 = Time.get_ticks_msec()
	app = get_parent()
	player = app.get("player") as PlayerController
	level = app.get("level") as LevelBuilder
	story = app.get("story") as StoryDirector
	session = app.get("session") as CoopSession
	net = app.get("net") as CoopNet
	surge = app.get("surge") as SurgeDirector
	hud = app.get("hud") as GameHud
	if hud != null:
		hud.title_layer.visible = false
	if role == "client":
		_run_client.call_deferred()
	else:
		_run_host.call_deferred()


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame


func wait(seconds: float) -> void:
	# Simulated-time wait so --write-movie (fixed step) records the same run.
	var count: int = maxi(1, int(round(seconds * 60.0)))
	for _i in range(count):
		await get_tree().physics_frame


func wait_until(cond: Callable, timeout: float) -> bool:
	var budget: int = maxi(1, int(round(timeout * 60.0)))
	for _i in range(budget):
		if bool(cond.call()):
			return true
		await get_tree().physics_frame
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
	await frames(10)


func press_interact() -> void:
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(3)


func hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await wait(seconds)
	Input.action_release(action)
	await frames(3)


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		DirAccess.make_dir_recursive_absolute(shot_dir)
		img.save_png("%s/%s_%s.png" % [shot_dir, role, name])
		print("SHOT ", role, "_", name)


func write_report(file_name: String, extra: Dictionary = {}) -> void:
	var passed: int = 0
	for c in checks:
		if bool(c["ok"]):
			passed += 1
	var report: Dictionary = {
		"role": role,
		"passed": passed,
		"failed": checks.size() - passed,
		"elapsed": float(Time.get_ticks_msec() - t0) / 1000.0,
		"checks": checks,
		"state": {
			"stage": story.stage,
			"core_locked": level.core.is_locked(),
			"stabilizers": level.stabilizers_latched(),
			"net": level.core.get_net(),
			"catwalk_tilt": level.catwalk.tilt,
			"catwalk_pins": level.catwalk.pins_seated,
			"brake": level.brake.pressure,
			"damper": level.damper.pressure,
			"iso_separated": level.isolation.separated_flag,
			"can_finish": session.can_finish(),
			"ledger": session.ledger_snapshot(),
			"claims": net._claims_copy(),
			"peers": net.peer_count(),
		},
	}
	for key in extra.keys():
		report[key] = extra[key]
	DirAccess.make_dir_recursive_absolute(out_dir + "/tests-out")
	var f: FileAccess = FileAccess.open("%s/tests-out/%s" % [out_dir, file_name], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("REPORT %s pass=%d fail=%d" % [file_name, passed, checks.size() - passed])


# ---------------------------------------------------------------------------
# host
# ---------------------------------------------------------------------------

func _run_host() -> void:
	await wait(1.5)
	var connected: bool = await wait_until(func() -> bool: return net.peer_count() >= 2, 45.0)
	check("peer_connected", connected, "peers=%d" % net.peer_count())
	if not connected:
		write_report("coop_host.json", {"aborted": "client never connected"})
		get_tree().quit()
		return
	var seen: bool = await wait_until(func() -> bool: return net.remotes.has(2), 10.0)
	check("client_avatar_visible", seen, "remotes=%d" % net.remotes.size())
	await shot("connected")

	# --- phase A: east stabiliser leg (host) ------------------------------
	var stab: StabilizerRig = level.stabilizers[1]
	await stand(stab.anchor.origin + Vector3(0, 0, -0.6), stab.global_position + Vector3(0, 1.2, 0))
	await press_interact()
	var claimed: bool = await wait_until(func() -> bool: return session.claim_owner("stabilizer_e") == 1, 4.0)
	check("host_claimed_east_leg", claimed, "owner=%d" % session.claim_owner("stabilizer_e"))
	await hold("move_forward", 3.8)
	check("host_east_leg_latched", stab.latched, "ext=%.2f" % stab.extension)
	await press_interact()
	await shot("east_leg_latched")

	# --- phase A: counterweight (host) ------------------------------------
	await stand(Vector3(8.5, 1.70, 7.47), level.right_station.area.global_position)
	await press_interact()
	var operating: bool = await wait_until(func() -> bool: return player.operating, 4.0)
	check("host_on_counterweight", operating)
	var net_before: float = level.core.get_net()
	await hold("move_back", 9.0)
	await press_interact()
	var net_after: float = level.core.get_net()
	check("host_moved_counterweight", absf(net_after) < absf(net_before) - 0.10, "net %.3f -> %.3f" % [net_before, net_after])
	check("host_counterweight_credit", session.ledger.has_credit(1, "counterweight_effect"))
	await shot("counterweight")

	# --- wait for the client's west leg (mutual interlock) ----------------
	var both: bool = await wait_until(func() -> bool: return level.stabilizers_latched() == 2, 60.0)
	check("both_legs_latched", both, "legs=%d" % level.stabilizers_latched())
	var cap: bool = await wait_until(func() -> bool: return level.core.is_capturable(), 20.0)
	check("core_in_capture_range", cap, "net=%.3f omega=%.3f" % [level.core.get_net(), level.core.get_omega()])
	await shot("both_legs")

	# --- phase B: recoil, both grab the catwalk --------------------------
	await stand(Vector3(-10.4, 3.50, -3.95), Vector3(-11.1, 4.45, -3.45))
	var grabbed: bool = false
	for attempt in range(3):
		await press_interact()
		grabbed = player.grabbing
		if grabbed:
			break
		await stand(Vector3(-10.4, 3.50, -3.95), Vector3(-11.1, 4.45, -3.45))
	check("host_grabbed_rail", grabbed)
	await shot("grab_before_surge")
	surge._begin_warning()
	await wait(4.6)
	check("surge_fired", surge.surge_count >= 1, "count=%d severity=%.2f" % [surge.surge_count, surge.severity])
	check("host_brace_credit", session.ledger.has_credit(1, "brace_hold"))
	check("catwalk_tilted", level.catwalk.max_tilt_seen > 0.02, "max=%.3f pins=%d" % [level.catwalk.max_tilt_seen, level.catwalk.pins_seated])
	await shot("surge")
	if player.grabbing:
		await press_interact()

	# --- phase C: lock the core ------------------------------------------
	var capturable_again: bool = await wait_until(func() -> bool: return level.core.is_capturable(), 15.0)
	if not capturable_again:
		await stand(Vector3(8.5, 1.70, 7.47), level.right_station.area.global_position)
		await press_interact()
		await hold("move_back" if level.core.get_net() > 0.0 else "move_forward", 2.0)
		await press_interact()
		await wait(1.0)
	await stand(Vector3(0, 0.06, 10.1), Vector3(0, 1.2, 8.6))
	await press_interact()
	var locked: bool = await wait_until(func() -> bool: return level.core.is_locked(), 6.0)
	check("core_locked", locked, "stage=%d" % story.stage)
	check("host_lock_credit", session.ledger.has_credit(1, "lock_assist"))
	await shot("core_locked")

	# --- phase C: damper (host) ------------------------------------------
	await wait(1.2)
	await stand(Vector3(6.4, 0.06, -2.3), Vector3(6.4, 1.2, -4.4))
	await press_interact()
	await hold("move_forward", 2.4)
	check("host_damper_latched", level.damper.latched_flag, "pressure=%.2f" % level.damper.pressure)
	if player.operating:
		await press_interact()
	await shot("damper")

	# --- wait for the client to separate the coupling --------------------
	var separated: bool = await wait_until(func() -> bool: return level.isolation.separated_flag, 60.0)
	check("isolation_separated", separated, "progress=%.2f" % level.isolation.progress)
	await wait(2.6)

	# --- data + exit ------------------------------------------------------
	await stand(Vector3(-3.0, 0.06, -8.0), Vector3(-3.0, 1.0, -9.1))
	await press_interact()
	var data_ok: bool = await wait_until(func() -> bool: return story.data_taken, 6.0)
	check("data_taken", data_ok)
	await shot("data")
	var gate: bool = await wait_until(func() -> bool: return session.can_finish(), 40.0)
	check("participation_gate_open", gate, session.gate_text())
	await stand(Vector3(-25.5, 0.06, -2.0), Vector3(-27.5, 1.2, -2.0))
	var completed: bool = await wait_until(func() -> bool: return story.stage == StoryDirector.Stage.COMPLETED, 8.0)
	check("run_completed", completed, "stage=%d" % story.stage)
	await shot("completed")
	var p2_ready: bool = session.ledger.is_ready(2)
	check("client_participation_recorded", p2_ready, str(session.ledger.get_record(2).get("phases", {})))
	write_report("coop_host.json")
	await wait(1.0)
	get_tree().quit()


# ---------------------------------------------------------------------------
# client
# ---------------------------------------------------------------------------

func _run_client() -> void:
	await wait(1.5)
	var online: bool = await wait_until(func() -> bool: return net.is_online(), 45.0)
	check("connected_to_host", online)
	if not online:
		write_report("coop_client.json", {"aborted": "no host"})
		get_tree().quit()
		return
	await shot("connected")

	# --- phase A: west stabiliser leg (client) ---------------------------
	var stab: StabilizerRig = level.stabilizers[0]
	await stand(stab.anchor.origin + Vector3(0, 0, -0.6), stab.global_position + Vector3(0, 1.2, 0))
	await press_interact()
	var operating: bool = await wait_until(func() -> bool: return player.operating, 8.0)
	check("client_claimed_west_leg", operating, "owner=%d" % session.claim_owner("stabilizer_w"))
	await hold("move_forward", 4.2)
	var latched: bool = await wait_until(func() -> bool: return stab.latched, 8.0)
	check("client_west_leg_latched", latched, "ext=%.2f" % stab.extension)
	if player.operating:
		await press_interact()
	await shot("west_leg")

	# --- phase B: wait for the recoil warning, then grab a rail ----------
	var warned: bool = await wait_until(func() -> bool: return surge.warning_left > 0.0, 120.0)
	check("warning_received", warned, "warning=%.1f" % surge.warning_left)
	await shot("warning")
	await stand(Vector3(-12.4, 3.50, -3.95), Vector3(-13.1, 4.45, -3.45))
	var grabbed: bool = false
	for attempt in range(3):
		await press_interact()
		grabbed = player.grabbing
		if grabbed:
			break
		await stand(Vector3(-12.4, 3.50, -3.95), Vector3(-13.1, 4.45, -3.45))
	check("client_grabbed_rail", grabbed)
	await wait(3.6)
	check("client_brace_credit", session.ledger.has_credit(2, "brace_hold"), str(session.ledger.get_record(2).get("phases", {})))
	await shot("brace")
	if player.grabbing:
		await press_interact()

	# --- wait for host to lock the core ----------------------------------
	var locked: bool = await wait_until(func() -> bool: return level.core.is_locked(), 120.0)
	check("core_locked_seen", locked, "stage=%d" % story.stage)

	# --- phase C: pin + carriage -----------------------------------------
	await stand(Vector3(10.7, 0.06, -5.0), Vector3(10.6, 1.3, -8.6))
	await press_interact()
	var pin_out: bool = await wait_until(func() -> bool: return level.isolation.pin_out, 8.0)
	check("client_pulled_pin", pin_out)
	await shot("pin")
	# The carriage refuses to move while the extraction damper is still unloaded
	# ("先去加载回路阻尼器"). The host loads it right after locking the core, so the
	# client waits for the damper like a real player would, then grabs and retries.
	await wait_until(func() -> bool: return level.damper.damper_effect() >= 0.35, 120.0)
	var carriage: bool = false
	for attempt in range(8):
		if session.is_pending_claim(level.isolation.machine_id):
			await wait(1.0)
			continue
		await press_interact()
		carriage = await wait_until(func() -> bool: return player.operating, 2.5)
		if carriage:
			break
		await wait(0.8)
	check("client_on_carriage", carriage)
	var damped: bool = level.damper.damper_effect() >= 0.35
	check("damper_loaded_by_host", damped, "effect=%.2f" % level.damper.damper_effect())
	await hold("move_forward", 5.0)
	var separated: bool = await wait_until(func() -> bool: return level.isolation.separated_flag, 12.0)
	check("client_separated_coupling", separated, "progress=%.2f" % level.isolation.progress)
	check("client_carriage_credit", session.ledger.has_credit(2, "carriage_push"))
	await shot("separated")

	# --- wait for completion ----------------------------------------------
	var completed: bool = await wait_until(func() -> bool: return story.stage == StoryDirector.Stage.COMPLETED, 120.0)
	check("completed_seen", completed, "stage=%d" % story.stage)
	var end_text: String = story.completion_text()
	check("end_text_received", end_text.contains("全员参与记录"), end_text.substr(0, 40))
	await shot("completed")
	var phases: Dictionary = session.ledger.get_record(2).get("phases", {})
	check("client_all_phases", int(phases.get("A", 0)) > 0 and int(phases.get("B", 0)) > 0 and int(phases.get("C", 0)) > 0, str(phases))
	write_report("coop_client.json")
	await wait(1.0)
	get_tree().quit()
