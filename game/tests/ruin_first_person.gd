extends SceneTree

## 腐墟星第一人称改版验收：
## 相机、准星、瞄准锥近战、地图边界、返航镜头恢复，以及不影响主舱第一人称。

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

	# 生成一只感染体，把它放到准星正前方；第一击必须命中。
	main._ruin_planet._spawn_one()
	check(main._ruin_planet.zombies.size() > 0, "感染体没有生成")
	var zombie: SpaceEnemy3D = null
	for value in main._ruin_planet.zombies.values():
		zombie = value as SpaceEnemy3D
		break
	if zombie != null:
		player.global_position = Vector3(0.0, 0.0, 0.0)
		player.rotation.y = 0.0
		player._camera_yaw = 0.0
		player._camera_yaw_target = 0.0
		player._camera_pitch = 0.0
		player._camera_pitch_target = 0.0
		zombie.global_position = Vector3(0.0, 0.0, -2.0)
		var before := zombie.health
		main._attack_ready_at.clear()
		main.attack_from_peer(1)
		check(zombie.health == before - 1, "准星正前方的感染体没有被近战命中")

		# 同一只感染体移到身后，攻击必须落空（第一人称不能打到背后）。
		zombie.global_position = Vector3(0.0, 0.0, 2.0)
		var behind_health := zombie.health
		main._attack_ready_at.clear()
		main.attack_from_peer(1)
		check(zombie.health == behind_health, "身后的感染体仍然被近战命中")

		# 超出近战距离也不该命中。
		zombie.global_position = Vector3(0.0, 0.0, -6.0)
		var far_health := zombie.health
		main._attack_ready_at.clear()
		main.attack_from_peer(1)
		check(zombie.health == far_health, "超出近战距离仍然命中")

	# 返航：收起腐墟星世界，镜头回到主舱第一人称。
	main.return_to_ship("测试返航")
	await process_frame
	check(main.current_planet_id == "demo", "返航后星球 id 没有复位")
	check(not main._ruin_planet.world_root.visible, "返航后腐墟星世界仍然可见")
	check(main._ruin_planet.zombies.is_empty(), "返航后感染体没有清理")
	var returned: SpacePlayer3D = main.players.get(1) as SpacePlayer3D
	check(returned != null, "返航后玩家没有重建")
	if returned != null:
		check(not returned.is_ruin_first_person(), "返航后仍处于腐墟星第一人称")
		check(returned._ship_first_person_mode, "返航后主舱没有恢复第一人称")

	_finish()


func _finish() -> void:
	print("RUIN_FIRST_PERSON: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
