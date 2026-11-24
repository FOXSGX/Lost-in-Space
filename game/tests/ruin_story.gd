extends SceneTree

## 腐墟星剧情验收：暗门/庇护所/NPC/核心/三条方案/结局。

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
	main.network_port = 28230 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame

	var ruin: RuinPlanet = main._ruin_planet
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(ruin.shelter_interior != null, "庇护所内部没有建立")
	check(ruin.shelter_npc_positions().has("engineer"), "庇护所没有工程师")
	check(ruin.shelter_npc_positions().has("doctor"), "庇护所没有医生")

	ruin.unlock_building(1, "energy_station")
	await process_frame
	await physics_frame
	var secret: Vector3 = ruin.energy_station_interior.call("secret_door_position")
	player.teleport_to(Vector3(secret.x, secret.y - 0.85, secret.z + 0.8))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	var secret_target: Dictionary = ruin.nearest(player)
	check(String(secret_target.get("kind", "")) == "energy_secret_door", "配电间暗门没有进入交互目标")
	check(ruin.prompt(player).contains("配电间暗门"), "配电间暗门没有提示")
	ruin.handle_action(1, "repair")
	await process_frame
	await physics_frame
	check(ruin.is_inside_shelter(player.global_position), "暗门没有进入庇护所")
	check(player.global_position.distance_to(ruin.shelter_spawn_position()) < 1.0, "庇护所入口位置不对")

	# 庇护所出口回能源站，再进来继续对话。
	var shelter_exit: Vector3 = ruin.shelter_exit_position()
	player.teleport_to(Vector3(shelter_exit.x, 700.15, shelter_exit.z - 1.2))
	player.rotation.y = PI
	player._camera_yaw = PI
	player._camera_yaw_target = PI
	var shelter_exit_target: Dictionary = ruin.nearest(player)
	check(String(shelter_exit_target.get("kind", "")) == "shelter_exit", "庇护所出口没有进入交互目标")
	check(ruin.prompt(player).contains("离开庇护所"), "庇护所出口没有提示")
	main.exit_shelter(1)
	await process_frame
	await physics_frame
	check(not ruin.is_inside_shelter(player.global_position), "离开庇护所后仍在庇护所")
	check(ruin.is_inside_energy_station(player.global_position), "离开庇护所后没有回到能源站")
	main.enter_shelter(1)
	await process_frame
	await physics_frame
	check(ruin.is_inside_shelter(player.global_position), "再次进入庇护所失败")

	# 第一次和工程师交谈。
	var npcs: Dictionary = ruin.shelter_npc_positions()
	var engineer: Vector3 = npcs["engineer"]
	player.teleport_to(Vector3(engineer.x, 700.15, engineer.z + 2.0))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	var npc_target: Dictionary = ruin.nearest(player)
	check(String(npc_target.get("kind", "")) == "shelter_npc", "工程师没有进入交互目标")
	check(String(npc_target.get("id", "")) == "engineer", "交互目标不是工程师")
	ruin.handle_action(1, "repair")
	await process_frame
	check(ruin.story_flags.get("met_engineer", false) == false, "未选择前不应标记已见工程师")
	check(main._ruin_dialogue_visible, "工程师对话面板没有打开")
	ruin.choose_shelter_dialogue(1, "engineer", 0)
	await process_frame
	check(ruin.story_flags.get("met_engineer", false), "工程师对话没有推进剧情")
	check(not main._ruin_dialogue_visible, "对话选择后面板没有关闭")

	# 第一次和医生交谈。
	var doctor: Vector3 = npcs["doctor"]
	player.teleport_to(Vector3(doctor.x, 700.15, doctor.z + 2.0))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	ruin.handle_action(1, "repair")
	await process_frame
	check(main._ruin_dialogue_visible, "医生对话面板没有打开")
	ruin.choose_shelter_dialogue(1, "doctor", 0)
	await process_frame
	check(ruin.story_flags.get("met_doctor", false), "医生对话没有推进剧情")

	# 核心门禁：没卡不能取。
	player.teleport_to(Vector3(7.0, 320.15, 6.7))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	var core_target: Dictionary = ruin.nearest(player)
	check(String(core_target.get("kind", "")) == "energy_quest_item", "反应堆核心没有进入交互目标")
	ruin.handle_action(1, "repair")
	await process_frame
	check(not ruin.has_quest_item("reactor_core"), "没有门禁卡却拿到了反应堆核心")

	# 用测试直接补齐三件套（拾取位置与交互已由各自室内测试覆盖）。
	ruin.quest_items["energy_access_card"] = true
	player.teleport_to(Vector3(7.0, 320.15, 6.7))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	ruin.handle_action(1, "repair")
	await process_frame
	check(ruin.has_quest_item("reactor_core"), "有门禁卡却没有拿到反应堆核心")
	ruin.quest_items["coolant_stabilizer"] = true
	ruin.quest_items["school_observation_data"] = true
	ruin.quest_items["market_navigation_module"] = true
	ruin._refresh_story_stage()
	await process_frame
	check(ruin.story_ready(), "三件套齐了但 story_ready 仍为 false")
	check(ruin.story_objective_text().contains("回庇护所"), "三件套齐后目标没有指向庇护所")

	# 回庇护所选择医生方案。
	player.teleport_to(Vector3(engineer.x, 700.15, engineer.z + 2.0))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	ruin.handle_action(1, "repair")
	await process_frame
	check(main._ruin_dialogue_visible, "三件套齐后没有最终方案对话")
	ruin.choose_shelter_dialogue(1, "engineer", 1)
	await process_frame
	check(ruin.story_plan == "doctor", "没有选中医生方案")
	check(ruin.story_objective_text().contains("菌群泵"), "医生方案目标不对")

	# B1 关泵。
	var pump: Vector3 = ruin.energy_station_interior.call("pump_console_position")
	player.teleport_to(Vector3(pump.x, 323.15, pump.z + 1.6))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	var pump_target: Dictionary = ruin.nearest(player)
	check(String(pump_target.get("kind", "")) == "energy_pump_console", "菌群泵控制台没有进入交互目标")
	ruin.handle_action(1, "repair")
	await process_frame
	check(ruin.story_flags.get("pump_shutdown", false), "菌群泵没有关闭")

	# B2 重启，真结局。
	var reactor: Vector3 = ruin.energy_station_interior.call("reactor_console_position")
	player.teleport_to(Vector3(reactor.x, 320.15, reactor.z + 1.6))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	var reactor_target: Dictionary = ruin.nearest(player)
	check(String(reactor_target.get("kind", "")) == "energy_reactor_console", "反应堆控制台没有进入交互目标")
	ruin.handle_action(1, "repair")
	await process_frame
	check(ruin.story_ending == "true", "没有进入真结局")
	check(ruin.story_objective_text().contains("星球保住"), "真结局标题不对")
	check(ruin.snapshot().get("story", {}).get("ending", "") == "true", "结局没有进入快照")

	print("RUIN_STORY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
