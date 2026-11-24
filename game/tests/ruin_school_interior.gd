extends SceneTree

## 学校内部验收：三层结构、教室/实验室/天文台/广播站、入口出口、观测数据任务物。

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
	main.network_port = 28060 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame

	var ruin: RuinPlanet = main._ruin_planet
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(ruin != null and ruin.school_interior != null, "学校内部没有建立")
	var interior: Node3D = ruin.school_interior
	check(int(interior.call("level_count")) == 3, "学校不是三层")
	for level: int in 3:
		var level_y: float = (interior.call("level_position", level) as Vector3).y
		check(is_equal_approx(level_y, 450.0 + float(level) * 3.0), "学校楼层高度不对：%d" % level)
		var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(Vector3(-3.0, level_y + 2.0, 0.0), Vector3(-3.0, level_y - 1.0, 0.0), 2))
		check(not hit.is_empty(), "学校楼层没有可站立碰撞：%d" % level)
		if not hit.is_empty():
			check(absf((hit.position as Vector3).y - level_y) < 0.05, "学校楼层碰撞高度不对：%d" % level)

	check(interior.find_children("Blackboard*", "MeshInstance3D", true, false).size() >= 4, "学校没有黑板")
	check(interior.find_children("SchoolComputer*", "Node3D", true, false).size() >= 6, "学校没有计算机房")
	check(interior.find_children("Telescope", "Node3D", true, false).size() == 1, "学校没有天文望远镜")
	check(interior.find_children("BroadcastConsole", "MeshInstance3D", true, false).size() == 1, "学校没有广播站")
	check(interior.find_children("SchoolTask_school_observation_data", "Node3D", true, false).size() == 1, "没有观测数据任务物")

	ruin.unlock_building(1, "school")
	await process_frame
	await physics_frame
	check(ruin.is_inside_school(player.global_position), "开门后没有进入学校")
	check(player.global_position.distance_to(ruin.school_spawn_position()) < 1.0, "进入学校后没有落在入口")
	check(player.global_position.y > 449.0, "玩家没有切到学校室内层")

	var task_points: Dictionary = interior.call("task_item_positions")
	var task_point: Vector3 = task_points["school_observation_data"]
	player.teleport_to(Vector3(task_point.x, 450.0 + 2.0 * 3.0 + 0.15, task_point.z + 1.3))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	var task_target: Dictionary = ruin.nearest(player)
	check(String(task_target.get("kind", "")) == "school_quest_item", "观测数据没有进入交互目标")
	check(ruin.prompt(player).contains("取走天文观测数据"), "观测数据没有取走提示")
	ruin.handle_action(1, "repair")
	await process_frame
	check(ruin.has_quest_item("school_observation_data"), "观测数据没有被记录")
	check((ruin.snapshot().get("quest_items", []) as Array).has("school_observation_data"), "观测数据没有进入快照")
	check(ruin.school_quest_hud_text().contains("观测数据✓"), "学校任务物 HUD 没有勾选观测数据")

	player.teleport_to(Vector3(0.0, 450.15, 7.0))
	player.rotation.y = PI
	player._camera_yaw = PI
	player._camera_yaw_target = PI
	var exit_target: Dictionary = ruin.nearest(player)
	check(String(exit_target.get("kind", "")) == "school_exit", "学校出口没有进入交互目标")
	check(ruin.prompt(player).contains("离开学校"), "学校出口没有提示")
	main.exit_school(1)
	await process_frame
	await physics_frame
	check(not ruin.is_inside_school(player.global_position), "离开学校后仍在室内层")
	check(player.global_position.distance_to(ruin.buildings["school"].entry) < 3.0, "离开学校后没有回到大门")

	print("RUIN_SCHOOL_INTERIOR: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
