extends SceneTree

## 腐墟星医院内部验收：四层结构、入口/出口传送、楼层碰撞和楼梯。

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
	main.network_port = 27870 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame

	var ruin: RuinPlanet = main._ruin_planet
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(ruin != null and ruin.hospital_interior != null, "医院内部没有建立")
	var interior := ruin.hospital_interior
	check(int(interior.call("level_count")) == 4, "医院不是四层")
	for level: int in 4:
		var level_y: float = (interior.call("level_position", level) as Vector3).y
		check(is_equal_approx(level_y, 197.0 + float(level) * 3.0), "楼层高度不对：%d" % level)
		var space := main.get_world_3d().direct_space_state
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-4.0, level_y + 2.0, 0.0), Vector3(-4.0, level_y - 1.0, 0.0), 2))
		check(not hit.is_empty(), "楼层没有可站立碰撞：%d" % level)
		if not hit.is_empty():
			check(absf((hit.position as Vector3).y - level_y) < 0.05, "楼层碰撞高度不对：%d" % level)

	# 直接开医院门，走真实入口传送。
	ruin.unlock_building(1, "hospital")
	await process_frame
	await physics_frame
	check(ruin.is_inside_hospital(player.global_position), "开门后没有进入医院内部")
	var spawn: Vector3 = ruin.hospital_spawn_position()
	check(player.global_position.distance_to(spawn) < 1.0, "进入医院后没有落在入口")
	check(player.global_position.y > 190.0, "玩家没有切到室内层")

	# 3F 住院病房：六间房只留一间开放，其余五扇门带碰撞和锁定提示。
	var locked_doors: Array = interior.call("locked_door_positions")
	check(locked_doors.size() == 5, "3F 上锁病房门数量不是 5：%d" % locked_doors.size())
	check(interior.find_children("LockedWardDoor*", "MeshInstance3D", true, false).size() == 5, "3F 上锁门板数量不对")
	check(interior.find_children("UnlockedWardDoor*", "MeshInstance3D", true, false).size() == 1, "3F 未上锁病房门数量不对")
	check(not bool(interior.call("is_ward_door_open")), "3F 未上锁病房门初始不应是打开的")
	check(interior.find_children("PharmacyShelf*", "MeshInstance3D", true, false).size() >= 3, "1F 药房没有药架")
	check(interior.find_children("OutpatientSign*", "MeshInstance3D", true, false).size() >= 1, "2F 门诊没有导诊牌")
	check(interior.find_children("NurseArmPivot*", "Node3D", true, false).size() == 6, "镇静观察室护士手臂数量不对")
	check(interior.find_children("ArchiveCabinet*", "MeshInstance3D", true, false).size() == 4, "B1 档案柜数量不对")
	if not locked_doors.is_empty():
		var level_three: Vector3 = interior.call("level_position", 3)
		var door: Vector3 = locked_doors[0]
		player.teleport_to(Vector3(door.x, level_three.y + 0.15, -0.25))
		player.rotation.y = 0.0
		player._camera_yaw = 0.0
		player._camera_yaw_target = 0.0
		var door_target: Dictionary = ruin.nearest(player)
		check(String(door_target.get("kind", "")) == "hospital_locked_door", "3F 上锁病房门没有进入交互目标")
		check(ruin.prompt(player).contains("已上锁"), "3F 上锁病房门没有提示")

		# 未上锁病房：靠近提示打开，按 E 后直接推开。
		var ward_point: Vector3 = interior.call("ward_door_position")
		player.teleport_to(Vector3(ward_point.x, level_three.y + 0.15, 0.2))
		player.rotation.y = PI
		player._camera_yaw = PI
		player._camera_yaw_target = PI
		var ward_target: Dictionary = ruin.nearest(player)
		check(String(ward_target.get("kind", "")) == "hospital_ward_door", "未上锁病房门没有进入交互目标")
		check(ruin.prompt(player).contains("打开病房门"), "未上锁病房门没有打开提示")
		main.open_hospital_ward_door(1)
		await process_frame
		check(bool(interior.call("is_ward_door_open")), "未上锁病房门没有打开")
		check(String(ruin.nearest(player).get("kind", "")) != "hospital_ward_door", "病房门打开后仍在交互目标里")

		# 医院任务物：病历、稳定剂、门禁卡。
		var task_points: Dictionary = interior.call("task_item_positions")
		check(task_points.size() == 3, "医院任务物数量不是 3：%d" % task_points.size())
		for item_id: String in ["patient_records", "coolant_stabilizer", "energy_access_card"]:
			check(task_points.has(item_id), "缺少任务物：%s" % item_id)
			if not task_points.has(item_id):
				continue
			var item_point: Vector3 = task_points[item_id]
			player.teleport_to(Vector3(item_point.x, item_point.y - 0.85, item_point.z))
			var item_target: Dictionary = ruin.nearest(player)
			check(String(item_target.get("kind", "")) == "hospital_quest_item", "任务物没有进入交互目标：%s" % item_id)
			ruin.handle_action(1, "repair")
			await process_frame
			check(ruin.has_quest_item(item_id), "任务物没有被记录：%s" % item_id)
			var item_node := interior.find_child("HospitalTask_" + item_id, true, false) as Node3D
			check(item_node != null and not item_node.visible, "任务物模型没有隐藏：%s" % item_id)
		check(ruin.quest_item_count() == 3, "任务物计数不是 3")
		check((ruin.snapshot().get("quest_items", []) as Array).size() == 3, "任务物没有进入快照")
		check(ruin.hospital_quest_hud_text().contains("任务物 3/3"), "任务物 HUD 没有显示 3/3")
		check(ruin.hospital_quest_hud_text().contains("病历✓"), "任务物 HUD 没有标出病历")

		player.teleport_to(spawn)
		player.rotation.y = PI
		player._camera_yaw = PI
		player._camera_yaw_target = PI

	# 出口在入口后方；转身后应出现离开提示。
	player.rotation.y = PI
	player._camera_yaw = PI
	player._camera_yaw_target = PI
	var exit_target: Dictionary = ruin.nearest(player)
	check(String(exit_target.get("kind", "")) == "hospital_exit", "医院出口没有进入交互目标")
	check(ruin.prompt(player).contains("离开医院"), "医院出口没有提示")

	main.exit_hospital(1)
	await process_frame
	await physics_frame
	check(not ruin.is_inside_hospital(player.global_position), "离开医院后仍在室内层")
	var entry: Vector3 = ruin.buildings["hospital"].entry
	check(player.global_position.distance_to(entry) < 3.0, "离开医院后没有回到大门")

	var collision_count := 0
	for child in interior.get_children():
		if child is StaticBody3D:
			collision_count += 1
	check(collision_count >= 40, "医院内部碰撞体数量不足：%d" % collision_count)

	print("RUIN_HOSPITAL_INTERIOR: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
