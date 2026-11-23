extends SceneTree
## Single-player freight mechanics probe on the real Resonance 04 level.
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/probe_freight.gd
##
## Every interaction goes through the real input map and the real animated
## collider. Teleports are only used to move between stations (as in the other
## probes); no platform/cargo state is set directly.

var game: Node
var player: EchoPlayer
var platform: FreightPlatform
var crystal: PortableCrystal
var checks: Array[Dictionary] = []
var failures: int = 0


func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	_run()


func _run() -> void:
	await create_timer(1.6).timeout
	player = game.player
	platform = game.platform
	crystal = game.crystal_a
	await create_timer(0.4).timeout
	_check("platform starts docked east", platform.current_dock() == "near", str(platform.travel_x))
	_check("crystal starts on the far loading dock", crystal.global_position.distance_to(LevelBuilder.CRYSTAL_A_SPAWN) < 0.6, str(crystal.global_position))
	_check("crystal and platform are separate objects", crystal != null and platform != null, "")

	# --- board and take the drive handle ---------------------------------
	player.teleport(Vector3(-9.0, 2.66, 2.5), 0.0)
	await create_timer(0.6).timeout
	_check("player boards the suspended platform", player.freight_platform == platform, str(player.freight_platform))
	var console_position: Vector3 = platform.to_global(Vector3(-1.02, 1.10, -0.50))
	player.aim_camera_at(console_position, -99.0)
	await create_timer(0.45).timeout
	await _press("interact")
	await create_timer(0.4).timeout
	_check("player can take the drive handle", player.platform_control == platform, str(player.platform_control))
	# --- drive west -------------------------------------------------------
	var start_x: float = platform.travel_x
	Input.action_press("move_forward")
	await create_timer(1.8).timeout
	Input.action_release("move_forward")
	await create_timer(0.3).timeout
	_check("W drives the platform west", platform.travel_x < start_x - 0.7, "x=%.2f" % platform.travel_x)
	_check("the driver is carried by the moving deck", player.freight_platform == platform and player.global_position.y > 2.2, str(player.global_position))
	# --- brake ------------------------------------------------------------
	await _press("interact")
	await create_timer(0.3).timeout
	player.teleport(Vector3(platform.travel_x + 0.4, 2.66, 3.2), 0.0)
	var brake_position: Vector3 = platform.to_global(Vector3(1.05, 1.22, 0.86))
	player.aim_camera_at(brake_position, -99.0)
	await create_timer(0.5).timeout
	await _press("interact")
	await create_timer(0.3).timeout
	_check("brake lever engages the safety brake", platform.brake_engaged, str(platform.brake_engaged))
	await _press("interact")
	await create_timer(0.3).timeout
	_check("brake lever releases", not platform.brake_engaged, str(platform.brake_engaged))

	# --- grab a rail ------------------------------------------------------
	player.teleport(Vector3(platform.travel_x + 0.75, 2.66, 1.8), 0.0)
	var grab_position: Vector3 = platform.to_global((FreightPlatform.GRAB_POINTS["n2"] as Dictionary)["rail"] as Vector3)
	player.aim_camera_at(grab_position, -99.0)
	await create_timer(0.5).timeout
	await _press("interact")
	await create_timer(0.4).timeout
	_check("player grabs the handrail", player.grab_platform == platform, str(player.grab_platform))
	_check("grab pins the body to the deck", absf(player.global_position.y - platform.deck_y) < 0.5, str(player.global_position))
	await _press("interact")
	await create_timer(0.3).timeout
	_check("player can release the rail", player.grab_platform == null, str(player.grab_platform))

	# --- drive to the far dock and load the crystal -----------------------
	player.teleport(Vector3(platform.travel_x, 2.66, 2.5), 0.0)
	player.aim_camera_at(platform.to_global(Vector3(-1.02, 1.10, -0.50)), -99.0)
	await create_timer(0.4).timeout
	await _press("interact")
	await create_timer(0.3).timeout
	Input.action_press("move_forward")
	await _wait_until(func() -> bool: return platform.current_dock() == "far", 20.0)
	Input.action_release("move_forward")
	await create_timer(0.3).timeout
	_check("platform reaches the west loading dock", platform.current_dock() == "far", str(platform.travel_x))
	await _press("interact")
	await create_timer(0.3).timeout
	# Pick up the crystal on the far dock.
	player.teleport(Vector3(-17.25, 2.66, 2.2), 0.0)
	await create_timer(0.5).timeout
	player.aim_camera_at(crystal.global_position + Vector3(0.0, 0.6, 0.0), -99.0)
	await create_timer(0.35).timeout
	await _press("pickup")
	await create_timer(0.35).timeout
	_check("crystal can be picked up on the far dock", player.carrying == crystal, str(player.carrying))
	# Load it on the platform (teleport with the carried crystal is a station move).
	player.teleport(Vector3(platform.travel_x, 2.66, 3.0), 0.0)
	await create_timer(0.5).timeout
	player.aim_camera_at(Vector3(platform.travel_x, 2.42, 3.0), -99.0)
	await _press("pickup")
	await create_timer(0.9).timeout
	_check("crystal seats in the freight bay", platform.cargo == crystal and platform.cargo_attached, str(platform.cargo))
	_check("cargo is loose before clamping", not platform.is_cargo_fixed(), "clamp_t=%.2f" % platform.clamp_t)

	# --- return east with loose cargo: the resonance accident ------------
	player.teleport(Vector3(platform.travel_x, 2.66, 2.5), 0.0)
	player.aim_camera_at(platform.to_global(Vector3(-1.02, 1.10, -0.50)), -99.0)
	await create_timer(0.4).timeout
	await _press("interact")
	await create_timer(0.3).timeout
	Input.action_press("move_back")
	var warning_seen: bool = false
	var max_tilt: float = 0.0
	var cargo_slid: bool = false
	var cargo_lost: bool = false
	for _index: int in range(360):
		await create_timer(0.05).timeout
		if platform.accident_phase == 1:
			warning_seen = true
		max_tilt = maxf(max_tilt, absf(platform.tilt_roll) + absf(platform.tilt_pitch))
		if platform.cargo_attached:
			cargo_slid = cargo_slid or absf(platform.cargo_u) > 0.12
		else:
			cargo_lost = true
		if platform.accident_fired and cargo_lost:
			break
	Input.action_release("move_back")
	_check("resonance warning precedes the shock", warning_seen, "")
	_check("resonance shock fires once", platform.accident_fired, "")
	_check("the loose deck visibly tilts", max_tilt > 0.08, "max=%.3f" % max_tilt)
	_check("loose cargo slides on the deck", cargo_slid or cargo_lost, "u=%.2f lost=%s" % [platform.cargo_u, str(cargo_lost)])
	_check("a hard accident can lose the crystal", cargo_lost, "cargo=" + str(platform.cargo))
	await create_timer(0.8).timeout
	_check("lost crystal becomes a free rigid body", not bool(crystal.get("freeze")) and crystal.get("freight") == null, str(crystal.global_position))
	_check("lost crystal lands on a reachable surface", crystal.global_position.y > -3.25, str(crystal.global_position))

	# --- recovery: pick the crystal up from the maintenance level --------
	player.teleport(Vector3(crystal.global_position.x, crystal.global_position.y + 0.1, crystal.global_position.z + 1.0), 0.0)
	await create_timer(0.6).timeout
	player.aim_camera_at(crystal.global_position + Vector3(0.0, 0.5, 0.0), -99.0)
	await create_timer(0.3).timeout
	await _press("pickup")
	await create_timer(0.35).timeout
	_check("the lost crystal can be recovered", player.carrying == crystal, str(player.carrying))
	if player.carrying == crystal:
		player.drop_carried(false)
		await create_timer(0.4).timeout

	# --- recall from the near dock ---------------------------------------
	player.teleport(Vector3(-6.0, 2.66, 1.0), 0.0)
	await create_timer(0.5).timeout
	var call_position: Vector3 = Vector3(-5.05, 3.18, 0.55)
	player.aim_camera_at(call_position, -99.0)
	await create_timer(0.45).timeout
	await _press("interact")
	await create_timer(0.3).timeout
	var recalled: bool = await _wait_until(func() -> bool: return platform.current_dock() == "near", 20.0)
	_check("dock call lever recalls the platform", recalled, "x=%.2f" % platform.travel_x)

	# --- service winch ---------------------------------------------------
	player.teleport(Vector3(-6.0, 2.66, 4.0), 0.0)
	await create_timer(0.4).timeout
	var winch_position: Vector3 = Vector3(-5.05, 3.18, 4.45)
	player.aim_camera_at(winch_position, -99.0)
	await create_timer(0.45).timeout
	await _press("interact")
	var lowered: bool = await _wait_until(func() -> bool: return platform.deck_y < 1.2, 12.0)
	_check("service winch lowers the deck", lowered, "y=%.2f" % platform.deck_y)
	await _press("interact")
	var raised: bool = await _wait_until(func() -> bool: return platform.deck_y > 2.35, 12.0)
	_check("service winch raises the deck", raised, "y=%.2f" % platform.deck_y)

	# --- reset ------------------------------------------------------------
	game.reset_level()
	await create_timer(1.0).timeout
	_check("reset returns the platform to the east dock", platform.current_dock() == "near" and absf(platform.deck_y - 2.6) < 0.1, "x=%.2f y=%.2f" % [platform.travel_x, platform.deck_y])
	_check("reset returns the crystal to the far dock", crystal.global_position.distance_to(LevelBuilder.CRYSTAL_A_SPAWN) < 1.2, str(crystal.global_position))
	_check("reset clears cargo and re-arms the accident", not platform.cargo_attached and not platform.accident_fired, "cargo=%s fired=%s" % [str(platform.cargo_attached), str(platform.accident_fired)])

	_finish()


func _wait_until(condition: Callable, timeout: float, poll: float = 0.08) -> bool:
	var elapsed: float = 0.0
	while elapsed < timeout:
		if bool(condition.call()):
			return true
		await create_timer(poll).timeout
		elapsed += poll
	return bool(condition.call())


func _press(action: String, hold: float = 0.12) -> void:
	Input.action_press(action)
	await create_timer(hold).timeout
	Input.action_release(action)
	await create_timer(0.14).timeout


func _check(label: String, ok: bool, detail: String) -> void:
	checks.append({"check": label, "ok": ok, "detail": detail})
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


func _finish() -> void:
	var report: Dictionary = {
		"checks": checks.size(),
		"failures": failures,
		"passed": failures == 0,
		"results": checks,
		"platform": {
			"x": platform.travel_x, "y": platform.deck_y, "dock": platform.current_dock(),
			"accident_fired": platform.accident_fired, "cargo": platform.cargo_attached,
		},
	}
	print("FREIGHT_PROBE_RESULT " + JSON.stringify(report))
	var dir: String = ProjectSettings.globalize_path("res://evidence/tests")
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(dir.path_join("freight.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	quit(0 if failures == 0 else 1)
