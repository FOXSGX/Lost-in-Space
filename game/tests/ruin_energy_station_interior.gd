extends SceneTree

## 能源站内部验收：四层结构、反应堆、星髓结晶、入口/出口传送。

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func run() -> void:
	var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
	root.add_child(main)
	await process_frame
	main._ship_session.persistence_enabled = false
	main.network_port = 28010 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame

	var ruin: RuinPlanet = main._ruin_planet
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(ruin != null and ruin.energy_station_interior != null, "能源站内部没有建立")
	var interior: Node3D = ruin.energy_station_interior
	check(int(interior.call("level_count")) == 4, "能源站不是四层")
	for level: int in 4:
		var level_y: float = (interior.call("level_position", level) as Vector3).y
		check(is_equal_approx(level_y, 320.0 + float(level) * 3.0), "能源站楼层高度不对：%d" % level)
		var space := main.get_world_3d().direct_space_state
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-6.0, level_y + 2.0, 0.0), Vector3(-6.0, level_y - 1.0, 0.0), 2))
		check(not hit.is_empty(), "能源站楼层没有可站立碰撞：%d" % level)
		if not hit.is_empty():
			check(absf((hit.position as Vector3).y - level_y) < 0.05, "能源站楼层碰撞高度不对：%d" % level)

	check(interior.find_children("ReactorGlow", "MeshInstance3D", true, false).size() >= 1, "没有反应堆核心")
	check(interior.find_children("StarMarrowCrystal*", "MeshInstance3D", true, false).size() >= 7, "没有星髓结晶")
	check(interior.find_children("DisguisedDistributionDoor", "MeshInstance3D", true, false).size() == 1, "没有配电间暗门")
	check(interior.find_children("TurbineBody", "MeshInstance3D", true, false).size() == 1, "没有汽轮机")
	check(interior.find_children("EjectionCapsule", "MeshInstance3D", true, false).size() == 1, "没有应急弹射舱")
	check(interior.get("physics_door") != null, "没有 LIS Physics 铰链门")
	check(interior.find_children("aqs002_bell_crystal", "Node3D", true, false).size() == 1, "没有接入星髓晶体美术资产")
	check(interior.find_children("aqs002_console", "Node3D", true, false).size() == 1, "没有接入操作台美术资产")
	check(interior.find_children("aqs002_press_static", "Node3D", true, false).size() == 1, "没有接入压机美术资产")

	ruin.unlock_building(1, "energy_station")
	await process_frame
	await physics_frame
	check(ruin.is_inside_energy_station(player.global_position), "开门后没有进入能源站")
	var spawn: Vector3 = ruin.energy_spawn_position()
	check(player.global_position.distance_to(spawn) < 1.0, "进入能源站后没有落在入口")
	check(player.global_position.y > 319.0, "玩家没有切到能源站室内层")

	var door_point: Vector3 = interior.call("physics_door_position")
	player.teleport_to(Vector3(door_point.x, 326.15, 1.0))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	var door_target: Dictionary = ruin.nearest(player)
	check(String(door_target.get("kind", "")) == "energy_physics_door", "物理维护门没有进入交互目标")
	check(ruin.prompt(player).contains("推开重型维护门"), "物理维护门没有提示")
	ruin.handle_action(1, "repair")
	for index: int in 12:
		await physics_frame
	check(absf(float(interior.call("physics_door_angle"))) > 0.01, "物理维护门没有被推开")
	player.teleport_to(spawn)

	player.rotation.y = PI
	player._camera_yaw = PI
	player._camera_yaw_target = PI
	var exit_target: Dictionary = ruin.nearest(player)
	check(String(exit_target.get("kind", "")) == "energy_exit", "能源站出口没有进入交互目标")
	check(ruin.prompt(player).contains("离开能源站"), "能源站出口没有提示")

	main.exit_energy_station(1)
	await process_frame
	await physics_frame
	check(not ruin.is_inside_energy_station(player.global_position), "离开能源站后仍在室内层")
	var entry: Vector3 = ruin.buildings["energy_station"].entry
	check(player.global_position.distance_to(entry) < 3.0, "离开能源站后没有回到大门")

	var collision_count := 0
	for child in interior.get_children():
		if child is StaticBody3D:
			collision_count += 1
	check(collision_count >= 30, "能源站内部碰撞体数量不足：%d" % collision_count)

	print("RUIN_ENERGY_STATION_INTERIOR: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
