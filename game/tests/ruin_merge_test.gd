extends SceneTree

## 腐墟星合并验证：从飞船选择腐墟星 → 落地 → 场景与感染者建立。

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
    main.network_port = 27310 + int(Time.get_ticks_msec() % 60)
    main._create_host()
    main.connected_ids = [1]
    main.spawn_player_for_peer(1)
    main._ship_session.enter_ship(true, [1], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1]

    # 注册表与目的地白名单
    var info := PlanetRegistry.info("ruin")
    check(not info.is_empty(), "注册表里没有腐墟星")
    check(bool(info.get("available", false)), "腐墟星没有标记为可登陆")
    check(PlanetRegistry.can_land("ruin"), "PlanetRegistry.can_land 拒绝腐墟星")
    main._ship_session.select_destination("ruin")
    check(main._ship_session.selected_destination == "ruin", "飞船不接受腐墟星作为目的地")

    # 落地
    main._confirm_land()
    await process_frame
    await process_frame
    check(main.current_planet_id == "ruin", "落地后星球 id 不是 ruin：%s" % main.current_planet_id)
    check(main._ruin_planet != null, "RuinPlanet 没有创建")
    if main._ruin_planet != null:
        check(main._ruin_planet.buildings.size() >= 3, "建筑没有生成：%d" % main._ruin_planet.buildings.size())
        check(main._ruin_planet.food_sites.size() > 0, "物资点没有生成")
        var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
        check(player != null, "玩家没有生成")
        if player != null:
            var spawn := main._ruin_planet.spawn_position(1)
            check(player.global_position.distance_to(spawn) < 6.0, "玩家没有落在腐墟星出生点")
        # 数帧推进不报错
        for index in 30:
            main._ruin_planet.tick(1.0 / 30.0)
        check(true, "tick 正常")

    print("RUIN_MERGE: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
