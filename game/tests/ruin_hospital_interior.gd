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

	# 取消半身高黑色挡板：大厅接待背板、1F 药房铁栅和 B1 药库铁笼都不再生成。
	check(interior.find_children("ReceptionBack", "MeshInstance3D", true, false).is_empty(), "大厅接待黑色挡板仍然存在")
	check(interior.find_children("PharmacyGrille", "MeshInstance3D", true, false).is_empty(), "1F 药房黑色挡板仍然存在")
	check(interior.find_children("PharmacyCageBar", "MeshInstance3D", true, false).is_empty(), "B1 药库门/铁笼仍然存在")
	check(interior.find_children("Wainscot", "MeshInstance3D", true, false).is_empty(), "半身高深色墙裙仍然横穿房间")
	check(interior.find_children("WallSign_hospital_stairs*", "MeshInstance3D", true, false).size() >= 1, "进门左侧没有楼梯间导向牌")

	# 直接开医院门，走真实入口传送。
	ruin.unlock_building(1, "hospital")
	await process_frame
	await physics_frame
	check(ruin.is_inside_hospital(player.global_position), "开门后没有进入医院内部")
	var spawn: Vector3 = ruin.hospital_spawn_position()
	check(player.global_position.distance_to(spawn) < 1.0, "进入医院后没有落在入口")
	check(player.global_position.y > 190.0, "玩家没有切到室内层")

	# 3F 住院病房：所有病房门已删除，门洞敞开。
	var locked_doors: Array = interior.call("locked_door_positions")
	check(locked_doors.is_empty(), "3F 仍保留上锁病房门")
	check(interior.find_children("LockedWardDoor*", "MeshInstance3D", true, false).is_empty(), "3F 仍存在病房门板")
	check(interior.find_children("UnlockedWardDoor*", "MeshInstance3D", true, false).is_empty(), "3F 仍存在未上锁门板")
	check(interior.find_children("WardLockLight", "MeshInstance3D", true, false).is_empty(), "3F 仍存在病房门锁灯")
	check(interior.find_children("PharmacyShelf*", "MeshInstance3D", true, false).size() >= 3, "1F 药房没有药架")
	check(interior.find_children("OutpatientSign*", "MeshInstance3D", true, false).size() >= 1, "2F 门诊没有导诊牌")
	check(interior.find_children("SedatedNurse", "Node3D", true, false).is_empty(), "医院仍然存在护士 NPC 实体")
	check(interior.find_children("WardThreshold", "MeshInstance3D", true, false).is_empty(), "病房门仍有棕色门槛挡板")
	check(interior.find_children("WardLockTag", "MeshInstance3D", true, false).is_empty(), "病房门仍有棕色挂牌")
	check(interior.find_children("ArchiveCabinet*", "MeshInstance3D", true, false).size() == 4, "B1 档案柜数量不对")
	# 3F 每个原门洞中心必须可直接穿过。
	var level_three: Vector3 = interior.call("level_position", 3)
	for x: float in [-4.0, 4.0, 8.0]:
		for side: float in [-1.0, 1.0]:
			if is_equal_approx(x, -4.0) and side > 0.0:
				continue
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.36
			capsule.height = 1.45
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform = Transform3D(Basis(), Vector3(x, level_three.y + 0.85, side * 6.0))
			query.collision_mask = 2
			check(main.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "3F 病房门洞仍被挡住 @%.1f" % x)
	var task_points: Dictionary = interior.call("task_item_positions")
	check(task_points.size() == 3, "医院任务物数量不是 3：%d" % task_points.size())
	for item_id: String in ["patient_records", "coolant_stabilizer", "energy_access_card"]:
		check(task_points.has(item_id), "缺少任务物：%s" % item_id)
		if not task_points.has(item_id):
			continue
		var item_point: Vector3 = task_points[item_id]
		if item_id == "coolant_stabilizer":
			# B1 稳定剂必须能从药库门口方向站到交互距离内，不能嵌在柜台里。
			var stand := Vector3(item_point.x, item_point.y - 0.25, item_point.z + 1.2)
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.36
			capsule.height = 1.45
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform = Transform3D(Basis(), stand)
			query.collision_mask = 2
			check(main.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "B1 稳定剂前方没有可站立空间")
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

	# 2F 门诊/检查室：只保留门框，门板和碰撞都不能存在。
	var level_two: Vector3 = interior.call("level_position", 2)
	for x: float in [-4.0, 4.0, 8.0]:
		for side: float in [-1.0, 1.0]:
			var door_capsule := CapsuleShape3D.new()
			door_capsule.radius = 0.36
			door_capsule.height = 1.45
			var door_query := PhysicsShapeQueryParameters3D.new()
			door_query.shape = door_capsule
			door_query.transform = Transform3D(Basis(), Vector3(x, level_two.y + 0.85, side * 1.3))
			door_query.collision_mask = 2
			check(main.get_world_3d().direct_space_state.intersect_shape(door_query, 1).is_empty(), "2F 门洞仍有碰撞 @%.1f" % x)
	for panel in interior.find_children("DoorPanel", "MeshInstance3D", true, false):
		check(absf((panel as Node3D).global_position.y - level_two.y) > 1.0, "2F 仍有门板模型：%s" % panel.name)

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
	check((-player.global_transform.basis.z).dot(Vector3(0.0, 0.0, 1.0)) > 0.9, "离开医院后没有面向门外")
	check((-player._camera.global_transform.basis.z).dot(Vector3(0.0, 0.0, 1.0)) > 0.8, "离开医院后镜头没有朝外")

	var collision_count := 0
	for child in interior.get_children():
		if child is StaticBody3D:
			collision_count += 1
	check(collision_count >= 40, "医院内部碰撞体数量不足：%d" % collision_count)

	print("RUIN_HOSPITAL_INTERIOR: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
