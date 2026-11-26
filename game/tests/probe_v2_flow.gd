extends SceneTree
## Resonance 04 V2 full single-player flow, including the suspended freight.
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/probe_v2_flow.gd
##
## The freight leg is driven with the real input map: board, take the handle,
## W/S drive, E brake/clamp/grab, F pickup/place. Only station-to-station moves
## are teleports (same standard as probe_resonance_04.gd). The rest of the act
## (hammer, memories 1-3, B1/B3, gate, exit, reset) is exercised as well.

var game: Node
var player: EchoPlayer
var platform: FreightPlatform
var crystal: PortableCrystal
var checks: Array[Dictionary] = []
var failures: int = 0
var arrivals: Array[Dictionary] = []
var started_msec: int = 0


func _initialize() -> void:
	started_msec = Time.get_ticks_msec()
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run()


func _run() -> void:
	await create_timer(1.2).timeout
	player = game.player
	platform = game.platform
	crystal = game.crystal_a
	game.network.node_arrived.connect(func(node_id: String, amplitude: float, kind: String) -> void:
		arrivals.append({"id": node_id, "amp": amplitude, "kind": kind, "t": game.game_time}))
	await create_timer(0.4).timeout
	_check("player spawns in the east cave", player.global_position.distance_to(LevelBuilder.SPAWN) < 0.6, str(player.global_position))
	await _test_hammer_and_memory_one()
	await _test_freight_transport()
	await _test_memory_two()
	await _test_memory_three_and_exit()
	await _test_reset()
	_finish()


func _test_hammer_and_memory_one() -> void:
	await _teleport(Vector3(2.25, 0.2, -0.4), 0.0)
	_check("hammer console is the selected interactable", player.current_target == game.hammer, str(player.current_target))
	await _strike()
	_check("first hammer strike", game.hammer.strike_count == 1, "strikes=%d" % game.hammer.strike_count)
	_check("memory one is reached", await _wait_until(func() -> bool: return game.memory.playing or bool(game.seen_memories.get(1, false)), 10.0), str(game.seen_memories))
	_check("memory one finishes", await _wait_until(func() -> bool: return bool(game.seen_memories.get(1, false)), 22.0), str(game.seen_memories))
	_check("objective introduces the fault and the freight line", game.hud.objective_label.text.contains("断层"), game.hud.objective_label.text)
	_check("west gap still blocks memory two", game.model.reached_amplitude("bell", "m2", 1.0) == 0.0, "%.3f" % game.model.reached_amplitude("bell", "m2", 1.0))


func _test_freight_transport() -> void:
	# Board at the east berth and drive to the far dock.
	await _teleport(Vector3(-9.0, 2.66, 2.5), 0.0)
	_check("player boards the suspended platform", player.freight_platform == platform, str(player.freight_platform))
	await _aim(platform.to_global(Vector3(-1.02, 1.10, -0.50)))
	await _press("interact")
	await create_timer(0.4).timeout
	_check("player takes the drive handle", player.platform_control == platform, str(player.platform_control))
	Input.action_press("move_forward")
	var reached_far: bool = await _wait_until(func() -> bool: return platform.current_dock() == "far", 20.0)
	Input.action_release("move_forward")
	await create_timer(0.4).timeout
	_check("platform crosses the fault to the west dock", reached_far, "x=%.2f" % platform.travel_x)
	await _press("interact")
	await create_timer(0.3).timeout
	# Recover the crystal from the far dock.
	await _teleport(Vector3(-17.3, 2.66, 2.1), 0.0)
	await _aim(crystal.global_position + Vector3(0.0, 0.6, 0.0))
	await _press("pickup")
	await create_timer(0.35).timeout
	_check("crystal is recovered from the far dock", player.carrying == crystal, str(player.carrying))
	# Load it into the platform cradle.
	await _teleport(Vector3(platform.travel_x, 2.66, 3.0), 0.0)
	await _aim(Vector3(platform.travel_x, 2.42, 3.0))
	await _press("pickup")
	await create_timer(1.0).timeout
	_check("crystal seats in the freight cradle", platform.cargo == crystal and platform.cargo_attached, str(platform.cargo))
	_check("cargo is loose before the clamp", not platform.is_cargo_fixed(), "clamp_t=%.2f" % platform.clamp_t)
	# Clamp it with the real lever.
	await _teleport(Vector3(platform.travel_x, 2.66, 2.25), 0.0)
	await _aim(platform.to_global(Vector3(-0.20, 1.06, -1.06)))
	await _press("interact")
	await create_timer(1.1).timeout
	_check("cargo clamp closes", platform.is_cargo_fixed(), "clamp_t=%.2f" % platform.clamp_t)
	# Drive back east through the resonance fault.
	await _teleport(Vector3(platform.travel_x, 2.66, 2.5), 0.0)
	await _aim(platform.to_global(Vector3(-1.02, 1.10, -0.50)))
	await _press("interact")
	await create_timer(0.35).timeout
	_check("player takes the handle for the return", player.platform_control == platform, str(player.platform_control))
	Input.action_press("move_back")
	var warning_seen: bool = false
	var shock_seen: bool = false
	var max_tilt: float = 0.0
	var stayed_clamped: bool = true
	for _index: int in range(420):
		await create_timer(0.05).timeout
		if platform.accident_phase == 1:
			warning_seen = true
		if platform.accident_fired:
			shock_seen = true
		max_tilt = maxf(max_tilt, absf(platform.tilt_roll) + absf(platform.tilt_pitch))
		if platform.cargo == crystal and not platform.is_cargo_fixed():
			stayed_clamped = false
		if platform.current_dock() == "near" and shock_seen:
			break
	Input.action_release("move_back")
	_check("resonance warning is telegraphed", warning_seen, "")
	_check("the resonance shock fires once", shock_seen and platform.accident_fired, "fired=%s" % str(platform.accident_fired))
	_check("the loaded deck visibly tilts", max_tilt > 0.08, "max=%.3f" % max_tilt)
	_check("the clamped crystal survives the shock", platform.cargo == crystal and stayed_clamped, "cargo=%s clamp=%.2f" % [str(platform.cargo), platform.clamp_t])
	_check("platform reaches the east dock with the crystal", await _wait_until(func() -> bool: return platform.current_dock() == "near", 20.0), "x=%.2f" % platform.travel_x)
	await _press("interact")
	await create_timer(0.3).timeout
	# Unload and put the crystal into B1.
	await _teleport(Vector3(platform.travel_x, 2.66, 3.0), 0.0)
	await _aim(crystal.global_position + Vector3(0.0, 0.6, 0.0))
	await _press("pickup")
	await create_timer(0.4).timeout
	_check("crystal unloads from the freight platform", player.carrying == crystal, str(player.carrying))
	_check("crystal is now on the east side of the fault", crystal.global_position.x > -8.4, str(crystal.global_position))
	var b1: ResonanceCradle = game.cradles["b1"] as ResonanceCradle
	await _teleport(Vector3(b1.global_position.x, b1.global_position.y + 0.2, b1.global_position.z + 1.2), 0.0)
	await _rotate_to(b1.required_yaw_deg)
	await _press("pickup", 0.15)
	await create_timer(0.7).timeout
	_check("crystal seats in B1 after real transport", b1.occupied != null and b1.aligned, "occupied=%s aligned=%s" % [str(b1.occupied), str(b1.aligned)])
	game.network.rebuild_edges()
	_check("B1 restores the west resonance path", game.model.reached_amplitude("bell", "m2", 1.0) >= 0.25, "amp=%.3f" % game.model.reached_amplitude("bell", "m2", 1.0))
	_check("objective advances to the relay", game.hud.objective_label.text.contains("撞钟"), game.hud.objective_label.text)


func _test_memory_two() -> void:
	await _teleport(Vector3(2.25, 0.2, -0.4), 0.0)
	await _strike()
	_check("second hammer strike", game.hammer.strike_count == 2, "strikes=%d" % game.hammer.strike_count)
	_check("memory two is reached", await _wait_until(func() -> bool: return game.memory.playing or bool(game.seen_memories.get(2, false)), 12.0), str(game.seen_memories))
	_check("memory two finishes", await _wait_until(func() -> bool: return bool(game.seen_memories.get(2, false)), 24.0), str(game.seen_memories))
	_check("echo from memory two dead-ends before B3", game.network.last_dead_end == "m2", game.network.last_dead_end)
	await _teleport(Vector3(-16.8, 0.9, -11.15), 0.0)
	await _press("pickup")
	var b3: ResonanceCradle = game.cradles["b3"] as ResonanceCradle
	await _teleport(Vector3(b3.global_position.x, b3.global_position.y + 0.2, b3.global_position.z + 1.2), 0.0)
	await _rotate_to(b3.required_yaw_deg)
	await _press("pickup", 0.15)
	await create_timer(0.7).timeout
	_check("violet crystal seats on the observation ledge", b3.occupied != null and b3.aligned, "aligned=%s" % str(b3.aligned))
	game.network.rebuild_edges()
	_check("final chain reaches the main memory crystal", game.model.reached_amplitude("m2", "m3", 0.92) >= 0.25, "amp=%.3f" % game.model.reached_amplitude("m2", "m3", 0.92))


func _test_memory_three_and_exit() -> void:
	await _teleport(Vector3(2.25, 0.2, -0.4), 0.0)
	await _strike()
	_check("third hammer strike", game.hammer.strike_count == 3, "strikes=%d" % game.hammer.strike_count)
	_check("memory three is reached", await _wait_until(func() -> bool: return bool(game.seen_memories.get(3, false)), 34.0), str(game.seen_memories))
	_check("exit gate opens after memory three", game.gate.is_open, str(game.gate.is_open))
	_check("all three memories were seen", game.seen_memories.size() == 3, str(game.seen_memories))
	await _teleport(Vector3(6.2, 0.2, -25.0), 0.0)
	_check("walking into the open exit completes the act", await _wait_until(func() -> bool: return game.completed, 5.0), str(game.completed))
	_check("completion time is recorded", game.completion_seconds > 5.0, "seconds=%.1f" % game.completion_seconds)
	var payload: Dictionary = game.completion_payload()
	_check("completion payload reports the freight accident", bool(payload.get("freight_accident_fired", false)), str(payload))
	# Hold the completion card long enough for a human to read it in the
	# recorded playthrough; the reset test follows after this beat.
	await create_timer(4.0).timeout


func _test_reset() -> void:
	game.reset_level()
	await create_timer(1.0).timeout
	_check("reset returns the player to spawn", player.global_position.distance_to(LevelBuilder.SPAWN) < 0.8, str(player.global_position))
	_check("reset closes the gate and clears memories", not game.gate.is_open and game.seen_memories.is_empty(), str(game.seen_memories))
	_check("reset returns the freight platform east", platform.current_dock() == "near" and absf(platform.deck_y - 2.6) < 0.1, "x=%.2f y=%.2f" % [platform.travel_x, platform.deck_y])
	_check("reset returns the crystal to the far dock", crystal.global_position.distance_to(LevelBuilder.CRYSTAL_A_SPAWN) < 1.2, str(crystal.global_position))
	_check("reset clears cargo and re-arms the accident", not platform.cargo_attached and not platform.accident_fired, "cargo=%s fired=%s" % [str(platform.cargo_attached), str(platform.accident_fired)])
	await _teleport(Vector3(2.25, 0.2, -0.4), 0.0)
	await _strike()
	_check("a second playthrough starts with a real strike", game.hammer.strike_count == 4, "strikes=%d" % game.hammer.strike_count)
	_check("memory one can wake again after reset", await _wait_until(func() -> bool: return game.memory.playing or bool(game.seen_memories.get(1, false)), 10.0), str(game.seen_memories))


func _strike() -> void:
	await _press("interact", 0.12)
	Input.action_press("move_forward")
	await create_timer(1.45).timeout
	Input.action_release("move_forward")
	await _press("interact", 0.12)
	await create_timer(2.0).timeout


func _aim(point: Vector3) -> void:
	player.aim_camera_at(point, -99.0)
	await create_timer(0.35).timeout


func _press(action: String, hold: float = 0.12) -> void:
	Input.action_press(action)
	await create_timer(hold).timeout
	Input.action_release(action)
	await create_timer(0.14).timeout


func _teleport(position_value: Vector3, yaw: float = 0.0) -> void:
	player.teleport(position_value, yaw)
	await create_timer(0.4).timeout


func _rotate_to(target_yaw: float) -> void:
	if player.carrying == null:
		return
	var current: float = player.carrying.held_yaw_deg
	var delta: float = fposmod(target_yaw - current, 360.0)
	var steps: int = int(round(delta / 45.0))
	for _index: int in range(steps):
		await _press("rotate_crystal", 0.10)


func _wait_until(condition: Callable, timeout: float, poll: float = 0.1) -> bool:
	var elapsed: float = 0.0
	while elapsed < timeout:
		if bool(condition.call()):
			return true
		await create_timer(poll).timeout
		elapsed += poll
	return bool(condition.call())


func _check(label: String, ok: bool, detail: String = "") -> void:
	checks.append({"check": label, "ok": ok, "detail": detail})
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


func _finish() -> void:
	var elapsed: float = float(Time.get_ticks_msec() - started_msec) / 1000.0
	var report: Dictionary = {
		"checks": checks.size(), "failures": failures, "passed": failures == 0,
		"elapsed_seconds": elapsed, "results": checks,
		"platform": {"x": platform.travel_x, "y": platform.deck_y, "accident_fired": platform.accident_fired,
			"cargo": platform.cargo_attached, "dock": platform.current_dock()},
	}
	print("V2_FLOW_RESULT " + JSON.stringify(report))
	var dir: String = ProjectSettings.globalize_path("res://evidence/tests")
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(dir.path_join("v2_flow.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	quit(0 if failures == 0 else 1)
