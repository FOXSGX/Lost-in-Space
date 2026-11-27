extends SceneTree

## 腐墟星第一人称改版验收：
## 相机、准星、最近目标近战、地图边界、返航镜头恢复，以及不影响主舱第一人称。

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
	main.network_port = 27510 + int(Time.get_ticks_msec() % 40)
	main._create_host()
	main.connected_ids = [1]
	main.spawn_player_for_peer(1)
	main._start_ruin_planet()
	await process_frame

	var player: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(main.current_planet_id == "ruin", "没有进入腐墟星")
	check(player != null, "玩家没有生成")
	if player == null:
		_finish()
		return
	check(player.is_ruin_first_person(), "腐墟星没有切到第一人称")
	check(player._camera != null, "本地玩家没有相机")
	if player._camera != null:
		check(player._camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "相机不是透视投影")
		check(absf(player._camera.fov - SpacePlayer3D.RUIN_FIRST_PERSON_FOV) < 0.1, "第一人称 FOV 不对")
		check(player._camera.global_position.y > 1.35 and player._camera.global_position.y < 1.9, "相机不在眼睛高度：%.2f" % player._camera.global_position.y)
	check(not player._visual.visible, "第一人称下本地角色模型仍然可见")
	check(player.attack_range_visual == null or not player.attack_range_visual.visible, "第一人称仍然显示攻击范围圈")
	check(main._ruin_planet.hud != null, "腐墟星 HUD 没有创建")
	check(main.get_active_map_size().x <= 152.0 and main.get_active_map_size().y <= 102.0, "腐墟星地图边界仍沿用霜烬星尺寸")

	# 腐墟星已移除丧尸与激光剑：不再存在感染体、Saber 或腐墟星近战动画。
	check(main._ruin_planet.get("zombies") == null, "腐墟星仍然保留感染体字典")
	check(player.find_children("Saber*", "MeshInstance3D", true, false).is_empty(), "第一人称仍然存在激光剑网格")
	check(not player.has_method("play_ruin_attack"), "仍然保留腐墟星近战动画")

	# 返航：收起腐墟星世界，镜头回到主舱第一人称。
	main.return_to_ship("测试返航")
	await process_frame
	check(main.current_planet_id == "demo", "返航后星球 id 没有复位")
	check(not main._ruin_planet.world_root.visible, "返航后腐墟星世界仍然可见")
	var returned: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(returned != null, "返航后玩家没有重建")
	if returned != null:
		check(not returned.is_ruin_first_person(), "返航后仍处于腐墟星第一人称")
		check(returned._ship_first_person_mode, "返航后主舱没有恢复第一人称")

	_finish()


func _finish() -> void:
	print("RUIN_FIRST_PERSON: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
