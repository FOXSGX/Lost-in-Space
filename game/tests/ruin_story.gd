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
	check(ruin.prompt(player).contains("门禁通讯"), "配电间暗门没有门禁通讯提示")
	ruin.handle_action(1, "repair")
	await process_frame
	await physics_frame
	check(not ruin.is_inside_shelter(player.global_position), "门禁通讯不应把玩家送进庇护所")
	check(main._ruin_dialogue_visible, "门禁通讯没有打开庇护所对话")
	check(main._ruin_dialogue_npc == "engineer", "第一次门禁通讯不是老工程师")

	# 第一次对话：老工程师；不出门、不进入庇护所。
	var npcs: Dictionary = ruin.shelter_npc_positions()
	check(npcs.has("engineer") and npcs.has("doctor"), "庇护所 NPC 位置缺失")
	_press_e(main)
	await process_frame
	check(ruin.story_flags.get("met_engineer", false), "工程师对话没有推进剧情")
	check(not main._ruin_dialogue_visible, "对话选择后面板没有关闭")

	# 第二次仍在门外通讯：这次轮到年轻医生。
	player.teleport_to(Vector3(secret.x, secret.y - 0.85, secret.z + 0.8))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	ruin.handle_action(1, "repair")
	await process_frame
	check(main._ruin_dialogue_visible, "第二次门禁通讯没有打开")
	check(main._ruin_dialogue_npc == "doctor", "第二次门禁通讯不是年轻医生")
	ruin.choose_shelter_dialogue(1, "doctor", 0)
	await process_frame
	check(ruin.story_flags.get("met_doctor", false), "医生对话没有推进剧情")
	check(not ruin.is_inside_shelter(player.global_position), "医生对话后玩家进入了庇护所")
	check(not main._ruin_dialogue_visible, "两次对话完成后面板没有自动关闭")
	check(main._ruin_dialogue_reopen_lock_until > Time.get_ticks_msec(), "对话关闭后没有输入锁")
	_press_e(main)
	await physics_frame
	check(not main._ruin_dialogue_visible, "第二次对话后同一 E 又重开了对话")

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
	ruin.quest_items["market_navigation_module"] = true
	ruin._refresh_story_stage()
	await process_frame
	check(ruin.story_ready(), "三件套齐了但 story_ready 仍为 false")
	check(ruin.story_objective_text().contains("门禁通讯"), "三件套齐后目标没有指向门禁通讯")

	# 回配电间门外选择医生方案。
	player.teleport_to(Vector3(secret.x, secret.y - 0.85, secret.z + 0.8))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	ruin.handle_action(1, "repair")
	await process_frame
	check(main._ruin_dialogue_visible, "三件套齐后没有最终方案对话")
	check(main._ruin_dialogue_npc == "engineer", "最终方案没有按顺序轮到工程师")
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
	for turn: int in 4:
		ruin.handle_action(1, "repair")
		await process_frame
		if turn < 3:
			check(not bool(ruin.story_flags.get("pump_shutdown", false)), "菌群泵手轮未转完就关闭了")
	check(ruin.story_flags.get("pump_shutdown", false), "菌群泵没有关闭")

	# B2 重启后不再立刻结算：要先回登陆艇。
	var reactor: Vector3 = ruin.energy_station_interior.call("reactor_console_position")
	player.teleport_to(Vector3(reactor.x, 320.15, reactor.z + 1.6))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	var reactor_target: Dictionary = ruin.nearest(player)
	check(String(reactor_target.get("kind", "")) == "energy_reactor_console", "反应堆控制台没有进入交互目标")
	for turn: int in 4:
		ruin.handle_action(1, "repair")
		await process_frame
		if turn < 3:
			check(not bool(ruin.story_flags.get("reactor_restarted", false)), "反应堆手轮未转完就重启了")
	check(ruin.story_flags.get("reactor_restarted", false), "反应堆重启没有写入标记")
	check(ruin.story_stage == "return_dialogue", "反应堆重启后没有要求回对话")
	check(not ruin.extraction_ready(), "没拿钥匙就开放了撤离")
	check(ruin.story_objective_text().contains("跃迁钥匙"), "重启后目标没有指向跃迁钥匙")

	# 回配电间门外通讯，领取关键道具后再离开。
	player.teleport_to(Vector3(secret.x, secret.y - 0.85, secret.z + 0.8))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	ruin.handle_action(1, "repair")
	await process_frame
	check(main._ruin_dialogue_visible, "反应堆重启后没有领取钥匙对话")
	ruin.choose_shelter_dialogue(1, "engineer", 0)
	await process_frame
	check(bool(ruin.story_flags.get("launch_key", false)), "对话没有给跃迁钥匙")
	check(main._items.count_kind(1, "launch_key") > 0, "跃迁钥匙没有进入物品栏")
	check(ruin.extraction_ready(), "拿到钥匙后没有开放撤离")
	check(ruin.story_objective_text().contains("回登陆艇"), "拿钥匙后目标没有指向登陆艇")

	# 回登陆艇按 E，真结局。
	var pad: Vector3 = ruin.pad_position()
	player.teleport_to(pad + Vector3(0.0, 0.02, 2.5))
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	var pad_target: Dictionary = ruin.nearest(player)
	check(String(pad_target.get("kind", "")) == "pad", "登陆艇没有进入交互目标")
	ruin.handle_action(1, "repair")
	await process_frame
	check(ruin.story_ending == "true", "回登陆艇后没有进入真结局")
	check(ruin.story_objective_text().contains("星球保住"), "真结局标题不对")
	check(ruin.snapshot().get("story", {}).get("ending", "") == "true", "结局没有进入快照")

	print("RUIN_STORY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _press_e(main: Main3D) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	main._input(event)
