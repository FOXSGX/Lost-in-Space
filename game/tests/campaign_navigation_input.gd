extends "res://tests/ship_computers_input.gd"

func run() -> void:
    if DisplayServer.get_name() == "headless":
        print("CAMPAIGN_INPUT_NOT_RUN: graphical display required")
        quit(1)
        return
    output = ProjectSettings.globalize_path("res://").path_join("../work/gameplay-iterations/20261028-navigation-story-alignment/previews").simplify_path()
    DirAccess.make_dir_recursive_absolute(output)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await frames()
    var guard: ReplayInputGuard = ReplayInputGuard.new()
    root.add_child(guard)
    main.network_port = 28403
    main._ship_session.persistence_enabled = false
    await click(main._host_button)
    await frames(12)
    var ship: ShipSession3D = main._ship_session
    check(main.ship_active and ship.campaign.grounded, "点击新航程进入地面飞船")
    await device("routes")
    await select_option("route_electromagnetic")
    check(ship._computer._action.disabled and ship._computer._notes.text.contains("核心损坏"), "星系图解释核心损坏阻挡")
    layout()
    await shot("01-stranded-star-map")
    await close()
    await device("surface")
    await click(ship._computer._action)
    await frames(16)
    var frost: Node3D = main._campaign_travel.frost
    check(frost != null and frost.players.has(1), "出舱电脑确认接入新霜烬星")
    await shot("02-frost-apron")
    # Fixture supplies the quest energy. The original flow_test covers reaching
    # it; this replay covers the real install, restore and board key presses.
    frost.progress.energy = true
    var actor: SpacePlayer3D = frost.players[1]
    actor.teleport_to(Vector3(0,0.8,16.4))
    actor._camera_yaw_target = 0
    actor._camera_pitch_target = 0.2
    await frames(6)
    await key(KEY_E)
    check(frost.progress.installed and not frost.progress.flight, "E 安装能源但不自动起飞")
    await key(KEY_E)
    check(frost.progress.flight and not ship.active, "第二次 E 恢复航行并保持探索")
    actor.teleport_to(Vector3(3.2,0.8,13.4))
    await frames(6)
    await key(KEY_E)
    await frames(12)
    check(main.ship_active and ship.campaign.navigation_restored, "E 进舱移交修复结果")
    await device("routes")
    for resolution: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080)]:
        root.size = resolution
        await frames(12)
        layout()
        await shot("03-star-map-%dx%d" % [resolution.x,resolution.y])
    root.size = Vector2i(1280,720)
    await frames(12)
    await select_option("route_electromagnetic")
    check(ship.selected_destination.is_empty(), "浏览卡片不改变共享航线")
    await click(ship._computer._action)
    check(ship.selected_destination == "electromagnetic", "确认后提交航线")
    await select_option("route_earth")
    check(ship._computer._action.disabled and ship._computer._notes.text.contains("仍缺"), "地球出口显示缺少的归航储备")
    await shot("04-earth-requirements")
    await close()
    await stand(ShipDevices3D.point_for("pilot_0") + Vector3(0,0,1.3), 0, 0.12)
    await key(KEY_E)
    check(ship.ready_peers.has(1), "E 就位驾驶席")
    await frames(200)
    check(main.game_started and main.current_planet_id == "electromagnetic", "全员就位倒数进入共振星")
    await shot("05-resonance-arrival")
    main.mission_completed = true
    main.return_to_ship.rpc("输入回放完成奖励夹具")
    await frames(12)
    await device("routes")
    await select_option("route_ruin")
    await click(ship._computer._action)
    await close()
    await stand(ShipDevices3D.point_for("pilot_0") + Vector3(0,0,1.3), 0, 0.12)
    await key(KEY_E)
    await frames(200)
    check(main.game_started and main.current_planet_id == "ruin", "航线电脑和驾驶席可前往腐墟星")
    await shot("06-ruin-arrival")
    await key(KEY_E)
    await frames(12)
    check(main.ship_active and main._ruin_planet == null, "腐墟星登陆点 E 回船清理世界")
    main._show_home()
    main.queue_free()
    guard.queue_free()
    await frames(8)
    print("CAMPAIGN_INPUT_RESULT checks=",checks," failures=",failures.size())
    for failure: String in failures:
        print("CAMPAIGN_INPUT_FAILED ",failure)
    quit(1 if not failures.is_empty() else 0)
