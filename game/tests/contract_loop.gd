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
    main._show_home()
    main._ship_session.persistence_enabled = false
    main._create_host()
    main._start_planet()
    await process_frame
    check(main.game_started, "合同测试未能登陆霜烬星")
    check(main.sample_positions.size() == 2 and main.samples.size() == 2, "异常冰样没有完整生成")
    check(main._known_map_positions("beacon", main.beacon_positions, []).is_empty(), "日志地图开局不应直接泄露信标坐标")
    main.scan_revealed_clues.append(1)
    check(main._known_map_positions("beacon", main.beacon_positions, []).size() == 1, "扫描后的信标回波没有进入日志地图")
    main.activated_beacons.assign([1])
    main.knowledge_flags.clear()
    check(not main._beacon_block_reason().is_empty(), "没有调查气象站时不应直接校准第二座信标")
    var player := main.players[1] as SpacePlayer3D
    player.global_position = main.samples[1].global_position
    main.handle_action(1, "pickup")
    check(player.carrying == 2, "F 键没有拾取异常冰样")
    check(main.taken_samples.has(1), "异常冰样没有从地图状态移除")
    main._check_enemy_triggers()
    check(not main.enemies.is_empty(), "携带样本没有触发高风险接触")
    for enemy in main.enemies.values():
        (enemy as Node).queue_free()
    main.enemies.clear()
    player.global_position = Vector3(main.EXTRACTION.x, 0.0, main.EXTRACTION.y)
    main.handle_action(1, "deposit")
    check(player.carrying == 0 and main.salvage_value == main.SAMPLE_VALUE, "样本投送没有计入回收价值")
    main.knowledge_flags.clear()
    main._apply_landmark_knowledge("weather_station")
    main._apply_landmark_knowledge("ice_rift")
    main._apply_landmark_knowledge("relay")
    check(main.knowledge_flags.has("weather_station") and main.knowledge_flags.has("ice_rift") and main.knowledge_flags.has("relay"), "环境调查没有完整解锁知识旗标")
    main.activated_beacons.assign([1, 2, 3])
    main.deposited_resources = 0
    main.salvage_value = 0
    check(not main._objectives_ready(), "异常尚未处理时不应开放撤离")
    player.global_position = Vector3(132.0, 0.0, -94.0)
    main.mission_elapsed = 13.0
    main.handle_action(1, "repair")
    check(main.rift_valve_open, "热脉回落期按 E 没有打开裂谷阀门")
    player.global_position = main.beacons[1].global_position
    main._set_signal_mode(1, "low")
    check(main.signal_mode == "low" and main.signal_lure_until > main.mission_elapsed, "低频信号没有建立生物诱导窗口")
    main.mission_elapsed = 24.0
    main._set_signal_mode(1, "high")
    check(main.signal_mode == "high" and main.storm_active, "高频信号没有提前唤起暴风雪")
    main._set_signal_mode(1, "low")
    check(main.signal_mode == "high", "信号冷却期间不应立即切换频段")
    main._resolve_anomaly("stabilize")
    check(main.anomaly_resolved, "中继站没有完成异常处理")
    check(main._objectives_ready(), "完成调查、信标和异常处理后没有开放撤离")
    print("合同循环测试：%d 项检查，%d 项失败" % [checks, failures])
    quit(0 if failures == 0 else 1)
