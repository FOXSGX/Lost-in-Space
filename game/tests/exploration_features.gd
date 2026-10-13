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

func key_event(code: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.pressed = true
    event.physical_keycode = code
    return event

func run() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._show_home()
    main._ship_session.persistence_enabled = false
    main._create_host()
    main._start_planet()
    await process_frame
    var player := main.players[1] as SpacePlayer3D
    check(main.game_started, "功能测试未能登陆星球")

    main.scan_revealed_clues.append(1)
    main._place_map_marker(1, "clue")
    check(main.map_markers.size() == 1 and main.map_markers[0].get("kind", "") == "clue", "已探索线索没有生成地图标记")
    main._place_map_marker(1, "heat")
    check(main.map_markers.size() == 2 and main.map_markers[1].get("kind", "") == "heat", "热源没有生成地图标记")

    main._input(key_event(KEY_TAB))
    check(main.is_journal_visible(), "Tab 没有打开探索日志")
    main._input(key_event(KEY_TAB))
    check(not main.is_journal_visible(), "Tab 没有关闭探索日志")
    main._input(key_event(KEY_M))
    check(main.is_journal_visible() and main._journal_map_view.visible and not paused, "M 没有打开地图或错误暂停游戏")
    main._input(key_event(KEY_M))
    check(not main.is_journal_visible() and not main._journal_map_view.visible, "再次按 M 没有关闭地图")
    main._input(key_event(KEY_ESCAPE))
    check(main._settings_visible and paused, "Esc 没有打开暂停中的设置")
    main._begin_rebind("sprint")
    main._input(key_event(KEY_X))
    check(int(main._key_bindings["sprint"]) == KEY_X, "设置没有修改加速键")
    main._reset_key_bindings()
    main._input(key_event(KEY_ESCAPE))
    check(not main._settings_visible and not paused, "Esc 没有关闭设置并恢复游戏")

    # Q 部署的是固定位置扫描器：玩家走开后，扫描范围仍围绕扫描器，结束后必须回收。
    var scan_clue := main.exploration_clues[0]
    var scan_point := Vector2(scan_clue.get("position", Vector2.ZERO))
    player.global_position = Vector3(scan_point.x, 0.0, scan_point.y)
    main.start_scan_for_peer(1)
    var deployed_scan_position := main.scan_device_position
    player.global_position += Vector3(30.0, 0.0, 0.0)
    main._reveal_clues_in_scan(main.SCAN_DEVICE_RADIUS)
    check(main.scan_device_active and main.scan_device_position == deployed_scan_position, "Q 扫描器没有固定在部署位置")
    check(main.scan_revealed_clues.has(int(scan_clue.get("id", 0))), "扫描器附近线索没有被锁定")
    player.global_position = deployed_scan_position
    main.handle_action(1, "pickup")
    check(not main.scan_device_active, "扫描器没有通过 F 手动回收")

    # 携带物可以丢下，异常冰样也能正常拾取；加速状态不再被携带减速逻辑覆盖。
    player.global_position = Vector3(main.sample_positions[0].x, 0.0, main.sample_positions[0].y)
    main.handle_action(1, "pickup")
    check(player.carrying == 2 and player.carrying_id == 1, "异常冰样仍然无法拾取")
    main.handle_action(1, "drop")
    check(player.carrying == 0 and not main.taken_samples.has(1), "携带物没有被 X 丢下")
    player.carrying = 1
    player.carrying_id = 1
    main.taken_crates.append(1)
    main.crates[1].visible = false
    main.handle_action(1, "drop")
    check(player.carrying == 0 and not main.taken_crates.has(1) and main.crates[1].visible, "热能电池没有被丢回地面")

    player.global_position = Vector3.ZERO
    player.sprinting = false
    player.oxygen = 100.0
    player.warmth = 1.0
    main._tick_survival(1.0)
    var normal_oxygen := player.oxygen
    var normal_warmth := player.warmth
    player.oxygen = 100.0
    player.warmth = 1.0
    player.sprinting = true
    main._tick_survival(1.0)
    check(player.oxygen < normal_oxygen and player.warmth < normal_warmth, "加速没有增加氧气和体温消耗")

    player.global_position = Vector3(-130.0, 0.0, -88.0)
    main._inspect_landmark(1, "weather_station")
    check(main.minigame_active and main.minigame_landmark_id == "weather_station", "调查地标没有启动对应小游戏")
    main._handle_clue_minigame_input(key_event(KEY_A))
    main._handle_clue_minigame_input(key_event(KEY_D))
    main._handle_clue_minigame_input(key_event(KEY_W))
    check(main.knowledge_flags.has("weather_station"), "完成气象站小游戏后没有解锁知识")

    player.global_position = main.beacons[1].global_position
    main.activated_beacons.append(1)
    main._check_enemy_triggers()
    var minimum_distance := INF
    for enemy_value in main.enemies.values():
        var enemy := enemy_value as SpaceEnemy3D
        minimum_distance = minf(minimum_distance, enemy.global_position.distance_to(player.global_position))
    check(minimum_distance > 6.0, "触发敌袭时敌人仍然出生在玩家身边")

    # 关键动作的即时反馈：本地镜头有短促震动，目标上方生成浮动确认文字。
    var camera_before_shake := player._camera.global_position
    player.trigger_camera_shake(0.08, 0.2)
    player._process(0.03)
    check(absf(player._camera.rotation_degrees.z) > 0.0, "关键动作没有触发镜头震动")
    for frame in 10:
        player._process(0.03)
    check(player._camera.global_position.distance_to(camera_before_shake) < 0.01, "镜头震动结束后位置发生漂移")
    main.floating_feedback_rpc(Vector3.ZERO, "测试反馈", Color.WHITE)
    var feedback_found := false
    for child in main._world_root.get_children():
        if child is Label3D and (child as Label3D).text == "测试反馈":
            feedback_found = true
            break
    check(feedback_found, "关键动作没有生成浮动反馈文字")
    print("探索功能测试：%d 项检查，%d 项失败" % [checks, failures])
    quit(0 if failures == 0 else 1)
