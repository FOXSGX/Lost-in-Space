extends SceneTree

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main._create_host()
    main._start_planet()
    await process_frame
    main._start_planet()
    await process_frame
    var player := main.players[1] as SpacePlayer3D
    var failures := 0

    # 1) 安全屋的确在新地图位置
    var safe := FrostMapLayout.SAFEHOUSE
    if player.global_position.distance_to(Vector3(safe.x, 0.0, safe.y)) > 6.0:
        push_error("出生点不在安全屋附近：%s" % str(player.global_position))
        failures += 1

    # 2) 每个地热口都能进入取暖判定
    for vent in FrostMapLayout.THERMAL_VENTS:
        var p := Vector2(vent.get("position", Vector2.ZERO))
        player.global_position = Vector3(p.x, 0.0, p.y)
        player.warmth = 0.1
        main._tick_survival(0.1)
        if player.warmth <= 0.1:
            push_error("地热口 %s 没有回温" % String(vent.get("name", "?")))
            failures += 1

    # 3) 离所有热源足够远时必须降温
    player.global_position = Vector3(70.0, 0.0, 30.0)
    player.warmth = 0.5
    main._tick_survival(0.1)
    if player.warmth >= 0.5:
        push_error("远离热源时体温没有下降")
        failures += 1

    # 4) 体温满值时从安全屋走到撤离点不会冻死
    var seconds := 0.0
    player.warmth = 1.0
    player.oxygen = 100.0
    while seconds < 75.0:
        main._tick_survival(1.0)
        seconds += 1.0
    if player.warmth <= 0.0:
        push_error("横穿地图的时间内体温耗尽，数值过紧")
        failures += 1

    print("地热口测试：%d 项失败，75 秒后体温 %.2f、氧气 %.0f" % [failures, player.warmth, player.oxygen])
    quit(0 if failures == 0 else 1)
