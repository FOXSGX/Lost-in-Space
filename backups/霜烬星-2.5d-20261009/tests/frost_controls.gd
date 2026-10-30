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
    var main: Node = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)
    await process_frame
    main._create_host()
    check(main.is_host, "测试主机创建失败")
    if not main.is_host:
        quit(1)
        return
    main.set_process(false)
    main._generate_demo_layout()
    main.change_stage.rpc("demo")
    var player: NetworkPlayer = main.players[1]
    player.set_physics_process(false)
    check(main.demo_obstacle_layout.size() >= 8, "霜烬星应生成足够的环境障碍")
    check(main._demo_stage.obstacle_nodes.size() == main.demo_obstacle_layout.size(), "障碍视觉节点应与布局同步")

    for binding in [["scan", KEY_Q], ["repair", KEY_E], ["pickup", KEY_F], ["deposit", KEY_G], ["revive", KEY_R]]:
        var events := InputMap.action_get_events(binding[0])
        check(events.size() == 1 and events[0].physical_keycode == binding[1], "按键映射错误：%s" % binding[0])
    check(not InputMap.has_action("interact"), "旧的全功能交互键仍存在")

    check(main.enemy_wave_index == 1, "登陆应出现首波")
    main._tick_enemy_waves(14.0)
    check(main.enemy_wave_index == 1, "不足 15 秒不能增援")
    main._tick_enemy_waves(1.0)
    check(main.enemy_wave_index == 2, "15 秒应触发第二波")
    main._tick_enemy_waves(30.0)
    check(main.enemy_wave_index == 4, "增援应超过三波，且计时不依赖任务事件")
    main._tick_enemy_waves(0.0)
    check(main.enemy_wave_index == 4, "同一时刻不能重复生成波次")
    main.is_host = false
    main._tick_enemy_waves(60.0)
    check(main.enemy_wave_index == 4, "客户端不能自行生成波次")
    main.is_host = true

    var origin := player.position
    Input.action_press("move_right")
    Input.action_press("scan")
    player._physics_process(0.016)
    Input.action_release("scan")
    await process_frame
    check(player.scan_lock_remaining > 3.9, "Q 应启动 4 秒扫描锁定")
    check(player.position == origin, "按住移动并启动扫描的同一帧也不能移动")
    check(main.activated_demo_beacon_ids.is_empty() and main.taken_crate_ids.is_empty(), "Q 不得修复或拾取")
    player._physics_process(1.0)
    check(player.position == origin and player.velocity == Vector2.ZERO, "扫描途中应保持原地")
    main._process(0.0)
    main.storm_active = true
    main.storm_remaining = main.STORM_DURATION
    main._update_storm_overlay()
    check(main.scan_radius == 520.0 and main.scan_duration == 4.0, "天气切换不应改变已发出的脉冲")
    var material: ShaderMaterial = main.storm_overlay.material
    check(float(material.get_shader_parameter("scan_progress")) > 0.2, "脉冲应随时间渐进扩散")
    player._physics_process(3.1)
    check(player.position.x > origin.x and player.scan_lock_remaining == 0.0, "脉冲结束后应恢复移动")
    Input.action_release("move_right")
    player.tick_scan_lock(2.1)
    main._process(0.0)
    main.scan_local_area()
    check(is_equal_approx(main.scan_radius, 374.4), "暴风雪扫描应采用有限且缩小的最大范围")
    player.scan_lock_remaining = 0.0
    player.scan_cooldown_remaining = 0.0
    main.storm_active = false

    var beacon: Node2D = main.demo_beacons[1]
    var crate: Node2D = main.resource_crates[1]
    crate.position = beacon.position
    player.teleport(beacon.position)
    main.spawn_player_for_peer(2)
    var mate: NetworkPlayer = main.players[2]
    mate.teleport(beacon.position)
    mate.downed = true
    check(main.get_action_target(player.position, "repair").kind == main.INTERACT_BEACON, "E 只能选修复目标")
    check(main.get_action_target(player.position, "pickup").kind == main.INTERACT_CRATE, "F 只能选电池，不能被倒地队友抢占")
    check(main.get_action_target(player.position, "revive").kind == main.INTERACT_REVIVE, "R 只能选倒地队友")
    check(main.get_action_target(player.position, "deposit").is_empty(), "G 在撤离点外应无效")
    Input.action_press("repair")
    player._physics_process(0.016)
    Input.action_release("repair")
    check(main.activated_demo_beacon_ids.size() == 1 and player.carrying == 0, "E 修复不应顺带拾取电池")
    await process_frame
    Input.action_press("pickup")
    player._physics_process(0.016)
    Input.action_release("pickup")
    check(player.carrying == 1 and main.reviving.is_empty(), "F 拾取不应顺带救援")
    await process_frame
    Input.action_press("revive")
    player._physics_process(0.016)
    Input.action_release("revive")
    check(main.reviving.has(1), "R 应独立启动救援")
    player.teleport(main.EXTRACTION_POSITION)
    await process_frame
    Input.action_press("deposit")
    player._physics_process(0.016)
    Input.action_release("deposit")
    check(main.deposited_resources == 1 and player.carrying == 0, "G 应独立投送")

    main.activated_demo_beacon_ids.assign([1, 2, 3])
    main.deposited_resources = 4
    var last_wave: int = main.enemy_wave_index
    main._tick_enemy_waves(120.0)
    check(main.enemy_wave_index == last_wave, "目标完成后应停止增援")
    for enemy in main.enemies.values():
        enemy.queue_free()
    main.enemies.clear()
    mate.downed = false
    mate.teleport(main.EXTRACTION_POSITION)
    main._tick_extraction(3.0)
    check(main.mission_completed, "不限波数的任务仍应正常清场撤离")
    main.change_stage.rpc("ship")
    check(player.scan_lock_remaining == 0.0 and main.enemy_wave_timer == 0.0, "返航应清除扫描锁定与波次计时")
    await process_frame
    print("霜烬星行为测试：%d 项检查，%d 项失败" % [checks, failures])
    quit(0 if failures == 0 else 1)
