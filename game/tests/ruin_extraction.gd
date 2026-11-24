extends SceneTree

## 腐墟星一局目标验收：翻找 3 处物资 + 查看 3 栋建筑 → 撤离开放 →
## 全员在登陆艇保持 3 秒 → 任务完成并返航。

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
	main.network_port = 27610 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame

	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	var ruin: RuinPlanet = main._ruin_planet
	check(player != null and ruin != null, "腐墟星没有建立")
	check(not ruin.extraction_ready(), "刚登陆就判定撤离开放")
	check(not main.extraction_enabled, "刚登陆就开启了撤离")

	# 真实走翻找路径：3 处物资。
	for index: int in RuinPlanet.OBJECTIVE_FOOD:
		ruin._finish_search(1, "food_%s" % String.chr(97 + index))
	check(ruin.taken_food.size() >= RuinPlanet.OBJECTIVE_FOOD, "翻找物资数量没有达到目标")
	check(main.salvage_value >= RuinPlanet.OBJECTIVE_FOOD * 10, "翻找没有累计回收价值")

	# 查看 3 栋建筑。
	for index: int in RuinPlanet.OBJECTIVE_BUILDINGS:
		ruin.enter_building(1, ["market", "hospital", "school"][index])
	check(ruin.discovered_buildings.size() >= RuinPlanet.OBJECTIVE_BUILDINGS, "查看建筑数量没有达到目标")
	check(ruin.extraction_ready(), "目标和完成后没有判定撤离开放")

	main._tick_ruin_extraction(0.1)
	check(main.extraction_enabled, "目标完成后没有开启撤离")
	check(ruin._pad_active_ring != null and ruin._pad_active_ring.visible, "登陆艇没有切到撤离开放外观")

	# 全员站到登陆艇上，保持 3 秒。
	player.global_position = ruin.pad_position()
	for index: int in 4:
		main._tick_ruin_extraction(0.8)
	check(main.extraction_progress >= RuinPlanet.EXTRACTION_HOLD, "撤离读条没有走完：%.2f" % main.extraction_progress)
	check(main.mission_completed, "撤离读条完成后没有标记任务完成")
	check("腐墟星搜刮完成" in main.mission_summary, "任务总结缺少腐墟星完成文案")

	# 走真实返航，确认世界收起、镜头回主舱。
	main.return_to_ship(main.mission_summary, main._vitals_snapshot())
	await process_frame
	check(main.current_planet_id == "demo", "返航后星球 id 没有复位")
	check(not ruin.world_root.visible, "返航后腐墟星世界仍然可见")
	var returned: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(returned != null and returned._ship_first_person_mode, "返航后没有回到主舱第一人称")

	print("RUIN_EXTRACTION: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
