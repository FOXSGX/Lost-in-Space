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
    main._create_host()
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
    print("探索功能测试：%d 项检查，%d 项失败" % [checks, failures])
    quit(0 if failures == 0 else 1)
