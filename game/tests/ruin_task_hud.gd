extends SceneTree

## 腐墟星任务栏：当前目标与任务物品进度必须分行，不能互相压住。

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
	main.network_port = 28120 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame
	await physics_frame
	await process_frame

	var progress: Label = main.get("_progress_label") as Label
	var items: Label = main.get("_task_items_label") as Label
	check(progress != null, "没有当前目标文本")
	check(items != null, "没有任务物品进度文本")
	if progress != null and items != null:
		check(not progress.text.contains("噪音") and progress.text.contains("回收价值"), "当前目标仍显示噪音或缺少回收价值")
		check(items.text.contains("未获取任务信息"), "未接对话前就提前显示了任务道具")
		var ruin: RuinPlanet = main._ruin_planet
		ruin.story_flags["quest_intel"] = true
		main._update_hud()
		check(items.text.begins_with("任务物品 "), "任务物品没有独立进度行")
		check(items.text.contains("医院 2F 观察室") and items.text.contains("能源站 B2 应急舱"), "任务物品没有列出五个道具的位置")
		ruin.quest_items["patient_records"] = true
		main._update_hud()
		check(items.text.contains("任务物品 1/5") and items.text.contains("✓ 镇静实验病历"), "拾取任务物后任务栏没有及时更新")
		var equipment := main._items.get("_equipment_column") as Control
		check(equipment != null and not (main.get("_objective_panel") as Panel).get_global_rect().intersects(equipment.get_global_rect()), "任务栏仍然压住左上装备方框")
		var progress_rect := progress.get_global_rect()
		var items_rect := items.get_global_rect()
		check(progress_rect.end.y <= items_rect.position.y + 1.0, "任务物品进度与当前目标文字重叠")
		check(items_rect.end.y <= (main.get("_objective_panel") as Panel).get_global_rect().end.y + 1.0, "任务物品进度超出任务栏")
		var panel := main.get("_objective_panel") as Panel
		var hint := main.get("_task_hint_label") as Label
		check(is_equal_approx(panel.size.y, 208.0), "任务栏展开高度不对")
		var tab := InputEventKey.new()
		tab.keycode = KEY_TAB
		tab.pressed = true
		main._input(tab)
		check(is_equal_approx(panel.size.y, 52.0) and not progress.visible and not items.visible, "Tab 收起没有隐藏任务内容")
		check(hint.text.contains("展开"), "收起后没有展开提示")
		main._input(tab)
		check(is_equal_approx(panel.size.y, 208.0) and progress.visible and items.visible, "Tab 展开没有恢复任务内容")

	print("RUIN_TASK_HUD: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
