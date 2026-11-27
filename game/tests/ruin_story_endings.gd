extends SceneTree

## 三条撤离方案/结局的状态验收。

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
	main.network_port = 28250 + int(Time.get_ticks_msec() % 30)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	var ruin: RuinPlanet = main._ruin_planet
	for id in ["energy_access_card", "coolant_stabilizer", "market_navigation_module", "reactor_core"]:
		ruin.quest_items[id] = true

	ruin._apply_story_plan("engineer")
	check(ruin.story_plan == "engineer", "工程师方案没有写入")
	check(is_equal_approx(ruin.story_timer, 180.0), "工程师方案倒计时不是 180 秒")
	check(ruin.extraction_ready(), "工程师方案没有开放撤离")
	check(ruin.story_objective_text().contains("快速重启"), "工程师方案目标文本不对")
	main._tick_ruin_extraction(1.0)
	check(not main.mission_completed, "工程师方案被旧的 3 秒撤离提前结算")
	ruin.story_timer = 0.0
	ruin._tick_story(0.1)
	check(ruin.story_ending == "destroyed", "倒计时结束没有进入星球沦陷结局")
	check(ruin.story_objective_text().contains("超时"), "超时结局标题不对")

	# 同一实例重置剧情状态，验证直接离开结局，避免第二个 ENet 主机。
	ruin.story_ending = ""
	ruin.story_stage = "start"
	ruin.story_plan = ""
	ruin.story_timer = 0.0
	ruin._story_return_timer = -1.0
	ruin.story_flags.clear()
	ruin._apply_story_plan("leave")
	check(ruin.story_plan == "leave", "离开方案没有写入")
	check(ruin.extraction_ready(), "离开方案没有开放撤离")
	ruin.finish_story_ending("leave")
	check(ruin.story_ending == "leave", "离开结局没有写入")
	check(ruin.story_objective_text().contains("迫降"), "离开结局标题不对")

	print("RUIN_STORY_ENDINGS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
