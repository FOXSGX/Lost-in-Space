extends SceneTree

var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error(message)

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._show_room()
    check(main._room_group.visible and not main._home_group.visible, "飞船准备区中间页面未恢复")
    main._show_route()
    check(main._route_group.visible and not main._room_group.visible, "星际航线选择页面未恢复")
    main._show_home()
    main._create_host()
    await process_frame
    check(main.game_started, "3D 星球未启动")
    check(main._world_root is Node3D, "世界根节点不是 Node3D")
    check(main.players[1] is SpacePlayer3D, "玩家不是 CharacterBody3D")
    var player := main.players[1] as SpacePlayer3D
    check(player._camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "摄像机不是正交 Camera3D")
    check(main.obstacles.size() == FrostMapLayout.OBSTACLES.size(), "3D 障碍数量不匹配")
    player.global_position = main.beacons[1].global_position
    main._update_interaction_hint()
    check("E" in main._interaction_label.text, "靠近通讯塔时没有显示 E 操作提示")
    main.start_scan_for_peer(1)
    check(is_equal_approx(player.scan_lock_remaining, main.SCAN_STARTUP), "Q 扫描没有锁定 3D 玩家")
    # 敌人在首次修复信标后出现，资源不再是敌人触发条件
    main._check_enemy_triggers()
    check(main.enemies.is_empty(), "开局时不应已有敌人")
    main.activated_beacons.append(1)
    main._check_enemy_triggers()
    check(not main.enemies.is_empty(), "修复第一座信标后敌人没有出现")
    check(main.enemy_wave_index == 1, "首波敌人波次编号错误")
    if main.enemies.is_empty():
        print("3D 霜烬星测试：%d 项检查，%d 项失败" % [checks, failures])
        quit(1)
        return
    var first_enemy := main.enemies.values()[0] as SpaceEnemy3D
    first_enemy.global_position = player.global_position + Vector3(2.0, 0.0, 0.0)
    var enemy_health_before := first_enemy.health
    main.attack_from_peer(1)
    check(first_enemy.health < enemy_health_before, "3D 空格攻击没有造成伤害")
    for enemy in main.enemies.values():
        (enemy as Node).queue_free()
    main.enemies.clear()
    main.activated_beacons.append(2)
    main._check_enemy_triggers()
    check(main.enemy_wave_index == 2, "第二座信标修复后没有增援")
    main._tick_storm(main.STORM_INTERVAL + 0.1)
    check(main.storm_active, "3D 暴风雪没有按时间触发")
    main.spawn_player_for_peer(2)
    await process_frame
    main.connected_ids.append(2)
    player.downed = false
    player.health = 5
    player.oxygen = 100.0
    var teammate := main.players[2] as SpacePlayer3D
    teammate.global_position = player.global_position
    teammate.downed = true
    main.handle_action(1, "revive")
    main._tick_revive(3.1)
    check(not teammate.downed, "3D 救援没有持续 3 秒完成")
    print("3D 霜烬星测试：%d 项检查，%d 项失败" % [checks, failures])
    quit(0 if failures == 0 else 1)
