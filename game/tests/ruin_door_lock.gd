extends SceneTree

## 腐墟星门锁验收：默认全部上锁、二级四弹子、压到底卡住、开门与取消。

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
	main.network_port = 27830 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame

	var ruin: RuinPlanet = main._ruin_planet
	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(ruin != null and player != null, "腐墟星没有建立")
	check(ruin.buildings.size() == 5, "建筑数量不是 5")
	check(main._items.count_kind(1, "lockpick") >= 1, "登陆后没有发放撬锁工具")

	for id in ruin.buildings.keys():
		check(ruin.is_building_locked(String(id)), "建筑默认没有上锁：" + String(id))
		var lock := ruin.buildings[id].get("lock") as Node3D
		check(lock != null and lock.visible, "门锁模型缺失或不可见：" + String(id))

	# 没有撬锁工具时 E 不能开锁；R 的暴力撬门不依赖工具。
	var locked_building: Dictionary = ruin.buildings["energy_station"]
	player.global_position = locked_building.entry + Vector3(0.0, 0.0, 0.8)
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	main._items.remove_item(1, "lockpick")
	main.handle_action(1, "repair")
	await process_frame
	check(not main.lockpick_active, "没有撬锁工具仍然打开了撬锁界面")
	check(ruin.is_building_locked("energy_station"), "没有撬锁工具却打开了能源站门")
	main._items.add_item(1, "lockpick", -1, {}, false)

	# 有工具时 E 正常进入四弹子；用真实的四弹子逻辑压到底。
	main.handle_action(1, "repair")
	await process_frame
	check(main.lockpick_active, "有撬锁工具时能源站门没有进入撬锁界面")
	var pick := main._lockpick_layer
	check(pick != null, "撬锁层没有创建")
	check(int(pick.get("_pins").size()) == 4, "弹子数量不是 4")
	var pick_marker := pick.get("_pick") as ColorRect
	check(pick_marker != null, "撬锁针没有建立")
	if pick_marker != null:
		var before_pick_x := pick_marker.position.x
		pick.set("_pick_target_x", before_pick_x + 100.0)
		pick.call("_process", 0.05)
		check(pick_marker.position.x > before_pick_x, "撬锁针没有移动动画")
	for index: int in 4:
		pick.set("_selected", index)
		pick.set("_holding", true)
		pick.call("_process", 1.2)
		pick.set("_holding", false)
		pick.call("_process", 0.1)
	check(bool(pick.get("_solved")), "四根弹子压到底后没有完成")
	pick.call("_process", 0.6)
	await process_frame
	check(not main.lockpick_active, "撬锁成功后界面没有关闭")
	check(not ruin.is_building_locked("energy_station"), "能源站门锁没有打开")
	var energy_lock := ruin.buildings["energy_station"].get("lock") as Node3D
	check(energy_lock != null and not energy_lock.visible, "能源站门锁模型没有收起")
	check(ruin.discovered_buildings.has("energy_station"), "开门后没有登记建筑")
	check((ruin.snapshot().get("unlocked", []) as Array).has("energy_station"), "快照没有记录已开门")

	# 取消撬锁不应改变门锁状态；用医院门。
	var hospital: Dictionary = ruin.buildings["hospital"]
	player.global_position = hospital.entry + Vector3(0.0, 0.0, 0.8)
	main.start_ruin_lockpick(1, "hospital")
	await process_frame
	check(main.lockpick_active, "医院门没有进入撬锁界面")
	if main._lockpick_layer != null:
		main._lockpick_layer.call("_cancel")
	await process_frame
	check(not main.lockpick_active, "取消后撬锁界面没有关闭")
	check(ruin.is_building_locked("hospital"), "取消撬锁却打开了医院门")

	# R 暴力撬门：不需要工具，主机计时结束后直接开门。
	var market: Dictionary = ruin.buildings["market"]
	player.global_position = market.entry + Vector3(0.0, 0.0, 0.8)
	main.handle_action(1, "ruin_force_door")
	await process_frame
	check(main.force_door_active, "按 R 没有进入暴力撬门")
	check(player.get("_ruin_force_active"), "本地没有进入暴力撬门状态")
	ruin._tick_force_jobs(3.0)
	await physics_frame
	await physics_frame
	check(not main.force_door_active, "暴力撬门结束后状态没有清掉")
	check(not ruin.is_building_locked("market"), "暴力撬门没有打开超市门")
	check((ruin.snapshot().get("unlocked", []) as Array).has("market"), "暴力撬门没有写入快照")

	# 图书馆锁死：E / R / 直接调用 unlock 都不能打开，也不登记建筑。
	var library: Dictionary = ruin.buildings["library"]
	player.global_position = library.entry + Vector3(0.0, 0.0, 0.8)
	player.rotation.y = 0.0
	player._camera_yaw = 0.0
	player._camera_yaw_target = 0.0
	var library_target: Dictionary = ruin.nearest(player)
	check(String(library_target.get("kind", "")) == "building", "图书馆没有进入交互目标")
	check(ruin.prompt(player).contains("封死"), "图书馆没有封死提示")
	main.handle_action(1, "repair")
	await process_frame
	check(ruin.is_building_locked("library"), "图书馆被 E 打开了")
	check(not ruin.discovered_buildings.has("library"), "图书馆被封死却登记了建筑")
	main.handle_action(1, "ruin_force_door")
	await process_frame
	check(ruin.is_building_locked("library"), "图书馆被 R 撬开了")
	ruin.unlock_building(1, "library")
	await process_frame
	check(ruin.is_building_locked("library"), "图书馆被 unlock_building 打开了")

	# 再次登陆：锁和建筑发现都重置。
	ruin.reset_run()
	check(ruin.is_building_locked("school"), "重置一局后学校门没有重新上锁")
	check(ruin.is_building_locked("market"), "重置一局后超市门没有重新上锁")
	check(not ruin.discovered_buildings.has("school"), "重置一局后建筑发现没有清空")
	check((ruin.snapshot().get("unlocked", []) as Array).is_empty(), "重置后快照仍有已开门")

	print("RUIN_DOOR_LOCK: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
