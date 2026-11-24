extends SceneTree

## 超市内部验收：两层卖场/仓库、冷柜/收银/路障、入口出口、民用导航模块。

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
	main.network_port = 28100 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame

	var ruin: RuinPlanet = main._ruin_planet
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(ruin != null and ruin.market_interior != null, "超市内部没有建立")
	var interior: Node3D = ruin.market_interior
	check(int(interior.call("level_count")) == 2, "超市不是两层")
	for level: int in 2:
		var level_y: float = (interior.call("level_position", level) as Vector3).y
		check(is_equal_approx(level_y, 570.0 + float(level) * 3.2), "超市楼层高度不对：%d" % level)
		var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(Vector3(-3.0, level_y + 2.0, 0.0), Vector3(-3.0, level_y - 1.0, 0.0), 2))
		check(not hit.is_empty(), "超市楼层没有可站立碰撞：%d" % level)
		if not hit.is_empty():
			check(absf((hit.position as Vector3).y - level_y) < 0.05, "超市楼层碰撞高度不对：%d" % level)

	check(interior.find_children("GondolaBase*", "MeshInstance3D", true, false).size() >= 9, "超市没有货架")
	check(interior.find_children("CheckoutBelt*", "MeshInstance3D", true, false).size() >= 2, "超市没有收银台")
	check(interior.find_children("FreezerBody", "MeshInstance3D", true, false).size() == 3, "超市没有冷柜")
	check(interior.find_children("BarricadePlank*", "MeshInstance3D", true, false).size() == 2, "超市没有幸存者路障")
	check(interior.find_children("VentGrate", "MeshInstance3D", true, false).size() == 1, "超市没有通风口线索")
	check(interior.find_children("MarketTask_market_navigation_module", "Node3D", true, false).size() == 1, "没有导航模块任务物")

	ruin.unlock_building(1, "market")
	await process_frame
	await physics_frame
	check(ruin.is_inside_market(player.global_position), "开门后没有进入超市")
	check(player.global_position.distance_to(ruin.market_spawn_position()) < 1.0, "进入超市后没有落在入口")
	check(player.global_position.y > 569.0, "玩家没有切到超市室内层")

	var task_points: Dictionary = interior.call("task_item_positions")
	var task_point: Vector3 = task_points["market_navigation_module"]
	player.teleport_to(Vector3(task_point.x, 570.0 + 3.2 + 0.15, task_point.z + 1.3))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	var task_target: Dictionary = ruin.nearest(player)
	check(String(task_target.get("kind", "")) == "market_quest_item", "导航模块没有进入交互目标")
	check(ruin.prompt(player).contains("取走民用导航模块"), "导航模块没有取走提示")
	ruin.handle_action(1, "repair")
	await process_frame
	check(ruin.has_quest_item("market_navigation_module"), "导航模块没有被记录")
	check((ruin.snapshot().get("quest_items", []) as Array).has("market_navigation_module"), "导航模块没有进入快照")
	check(ruin.market_quest_hud_text().contains("民用导航模块✓"), "超市任务物 HUD 没有勾选导航模块")

	player.teleport_to(Vector3(0.0, 570.15, 7.4))
	player.rotation.y = PI
	player._camera_yaw = PI
	player._camera_yaw_target = PI
	var exit_target: Dictionary = ruin.nearest(player)
	check(String(exit_target.get("kind", "")) == "market_exit", "超市出口没有进入交互目标")
	check(ruin.prompt(player).contains("离开超市"), "超市出口没有提示")
	main.exit_market(1)
	await process_frame
	await physics_frame
	check(not ruin.is_inside_market(player.global_position), "离开超市后仍在室内层")
	check(player.global_position.distance_to(ruin.buildings["market"].entry) < 3.0, "离开超市后没有回到大门")

	print("RUIN_MARKET_INTERIOR: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
