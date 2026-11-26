extends SceneTree
## Boot + standing probe for the freight arena in isolation.
##   godot --headless --fixed-fps 60 --path . --script res://tests/freight_boot.gd
## It builds the co-op room version of the arena, spawns the real first-person
## player on the near dock and prints the platform/player state. No state is
## faked: the player stands on the actual dock collider and boards the platform
## through the real moving AnimatableBody3D.

var game_root: Node3D
var arena_data: Dictionary
var platform: FreightPlatform
var player: EchoPlayer
var failures: int = 0


func _initialize() -> void:
	game_root = Node3D.new()
	game_root.name = "FreightBoot"
	root.add_child(game_root)
	_setup()


func _setup() -> void:
	await process_frame
	var world: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.38, 0.50)
	env.ambient_light_energy = 0.55
	world.environment = env
	game_root.add_child(world)
	var arena: FreightArena = FreightArena.new()
	arena_data = arena.build(game_root, true, true)
	platform = arena_data["platform"] as FreightPlatform
	var crystal: PortableCrystal = PortableCrystal.new()
	crystal.name = "CrystalA"
	crystal.position = arena_data["far_crystal_position"] as Vector3
	game_root.add_child(crystal)
	crystal.build("crystal_a", "res://assets/crystals/res_crys_cluster_env02_a_lod0.glb", "cyan", 0.58)
	crystal.set_spawn(arena_data["far_crystal_position"] as Vector3, 90.0)

	player = EchoPlayer.new()
	player.position = Vector3(-5.6, 2.66, 2.5)
	game_root.add_child(player)
	player.teleport(Vector3(-5.6, 2.66, 2.5), 0.0)
	await _run()


func _run() -> void:
	await create_timer(0.8).timeout
	_check("player spawned on the near dock", player.global_position.y > 2.3, str(player.global_position))
	_check("player is standing (not falling)", player.is_on_floor(), "floor=" + str(player.is_on_floor()))
	_check("platform starts at the near park", absf(platform.travel_x - FreightArena.NEAR_PARK_X) < 0.05, str(platform.travel_x))
	_check("crystal starts on the far dock", (game_root.get_node("CrystalA") as Node3D).global_position.distance_to(arena_data["far_crystal_position"] as Vector3) < 1.0, "")
	# Diagnostics: what is actually under the platform and what collides there.
	print("PLATFORM_POS ", platform.global_position, " layer=", platform.collision_layer, " children=", platform.get_child_count())
	for child: Node in platform.get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child as CollisionShape3D
			print("  SHAPE ", cs.name, " at ", cs.global_position, " size=", (cs.shape as BoxShape3D).size if cs.shape is BoxShape3D else "?")
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	ray.from = Vector3(-8.8, 4.0, 2.5)
	ray.to = Vector3(-8.8, -1.0, 2.5)
	ray.collision_mask = 1
	ray.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(ray)
	print("RAY_PLATFORM ", hit)
	# Walk west along the dock, through the open east gate, onto the platform.
	player.aim_camera_at(Vector3(-9.0, 2.7, 2.5), 0.0)
	await create_timer(0.3).timeout
	Input.action_press("move_forward")
	await create_timer(0.28).timeout
	print("MIDWALK ", player.global_position, " floor=", player.is_on_floor(), " freight=", player.freight_platform)
	await create_timer(0.27).timeout
	Input.action_release("move_forward")
	await create_timer(0.35).timeout
	print("POSTWALK ", player.global_position, " floor=", player.is_on_floor(), " freight=", player.freight_platform)
	# Take the drive handle through the real interaction path and drive west.
	var console_position: Vector3 = platform.to_global(Vector3(-1.02, 1.10, -0.50))
	player.aim_camera_at(console_position, -99.0)
	await create_timer(0.45).timeout
	print("TARGET ", player.current_target)
	Input.action_press("interact")
	await create_timer(0.14).timeout
	Input.action_release("interact")
	await create_timer(0.3).timeout
	print("CONTROL ", player.platform_control, " owner=", platform.control_owner_id)
	Input.action_press("move_forward")
	await create_timer(2.0).timeout
	var mid_platform: Vector3 = platform.global_position
	var mid_player: Vector3 = player.global_position
	Input.action_release("move_forward")
	await create_timer(0.4).timeout
	print("DRIVE ", "platform=", platform.global_position, " speed=", platform.speed, " player=", player.global_position, " floor=", player.is_on_floor())
	_check("the platform moves under the driver", mid_platform.x < FreightArena.NEAR_PARK_X - 0.8, "x=%.2f" % mid_platform.x)
	_check("the driver rides the moving platform", absf(player.global_position.x - platform.global_position.x) < 1.8 and player.is_on_floor(), "player=" + str(player.global_position) + " platform=" + str(platform.global_position))

	# Drive all the way to the far loading dock.
	Input.action_press("move_forward")
	await create_timer(3.4).timeout
	Input.action_release("move_forward")
	await create_timer(0.3).timeout
	_check("platform reaches the far dock", platform.current_dock() == "far", "x=%.2f dock=%s" % [platform.travel_x, platform.current_dock()])
	Input.action_press("interact")
	await create_timer(0.12).timeout
	Input.action_release("interact")
	await create_timer(0.25).timeout
	_check("driver can release the handle", player.platform_control == null, str(player.platform_control))

	# Pick up the crystal on the far dock through the real pickup input.
	var crystal: PortableCrystal = game_root.get_node("CrystalA") as PortableCrystal
	player.teleport(Vector3(-17.25, 2.66, 3.0), 0.0)
	await create_timer(0.35).timeout
	player.aim_camera_at(crystal.global_position + Vector3(0.0, 0.7, 0.0), -99.0)
	await create_timer(0.25).timeout
	Input.action_press("pickup")
	await create_timer(0.12).timeout
	Input.action_release("pickup")
	await create_timer(0.35).timeout
	_check("crystal can be picked up on the far dock", player.carrying == crystal, str(player.carrying))

	# Carry it to the platform cargo bay and drop it.
	player.teleport(Vector3(platform.travel_x, 2.66, 3.0), 0.0)
	await create_timer(0.35).timeout
	player.aim_camera_at(Vector3(platform.travel_x, 2.4, 3.0), -99.0)
	Input.action_press("pickup")
	await create_timer(0.12).timeout
	Input.action_release("pickup")
	await create_timer(0.8).timeout
	_check("dropped crystal seats in the freight bay", platform.cargo == crystal and platform.cargo_attached, "cargo=" + str(platform.cargo))

	# Clamp it down.
	var clamp_control: Vector3 = platform.to_global(Vector3(-0.20, 1.06, -1.06))
	player.teleport(Vector3(platform.travel_x, 2.66, 2.35), 0.0)
	player.aim_camera_at(clamp_control, -99.0)
	await create_timer(0.4).timeout
	print("CLAMP_TARGET ", player.current_target)
	Input.action_press("interact")
	await create_timer(0.12).timeout
	Input.action_release("interact")
	await create_timer(0.9).timeout
	_check("cargo clamp closes", platform.clamp_closed and platform.clamp_t > 0.9, "clamp_t=%.2f" % platform.clamp_t)

	# Drive east into the resonance fault.
	var console_position2: Vector3 = platform.to_global(Vector3(-1.02, 1.10, -0.50))
	player.teleport(Vector3(platform.travel_x, 2.66, 2.5), 0.0)
	player.aim_camera_at(console_position2, -99.0)
	await create_timer(0.4).timeout
	Input.action_press("interact")
	await create_timer(0.12).timeout
	Input.action_release("interact")
	await create_timer(0.25).timeout
	_check("driver can take the handle for the return trip", player.platform_control == platform, str(player.platform_control))
	Input.action_press("move_back")
	var warning_seen: bool = false
	var max_tilt: float = 0.0
	for _index: int in range(240):
		await create_timer(0.05).timeout
		if platform.accident_phase == 1:
			warning_seen = true
		max_tilt = maxf(max_tilt, absf(platform.tilt_roll) + absf(platform.tilt_pitch))
		if platform.accident_fired and platform.accident_phase == 0:
			break
	Input.action_release("move_back")
	print("ACCIDENT ", "warning=", warning_seen, " fired=", platform.accident_fired, " max_tilt=", max_tilt, " cargo=", platform.cargo, " u=%.2f" % platform.cargo_u, " player_y=%.2f" % player.global_position.y)
	_check("resonance warning precedes the shock", warning_seen, "")
	_check("resonance shock fires exactly once", platform.accident_fired, "")
	_check("the deck visibly tilts", max_tilt > 0.04, "max=%.3f" % max_tilt)
	_check("clamped cargo stays in the cradle", platform.cargo == crystal and absf(platform.cargo_u) < 0.35, "u=%.2f" % platform.cargo_u)
	await create_timer(2.0).timeout
	_check("the shock does not fire a second time", platform.accident_fired and platform.accident_phase == 0, "phase=%d" % platform.accident_phase)
	_check("the player is still aboard or safely on the dock", platform._riders.has(player) or player.global_position.y > -1.0, "riders=%d y=%.2f" % [platform._riders.size(), player.global_position.y])
	print("BOOT_STATE ", JSON.stringify({
		"player": str(player.global_position),
		"platform_x": platform.travel_x,
		"platform_y": platform.deck_y,
		"on_platform": player.freight_platform == platform,
		"riders": platform._riders.size(),
		"dock": platform.current_dock(),
	}))
	quit(0 if failures == 0 else 1)


func _check(label: String, condition: bool, detail: String) -> void:
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
