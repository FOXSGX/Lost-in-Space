extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
    call_deferred("run")
func check(ok: bool, msg: String) -> void:
    checks += 1
    if not ok: failures.append(msg)
func run() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    var ship := main._ship_session
    ship.persistence_enabled = false
    main.network_port = 24572
    main._create_host()
    await physics_frame
    ship.tick(0.0)
    check(ship.device_room() != null and main._screen_view == "ship", "主舱没有实体集市终端")
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.teleport_to(ShipDevices3D.point_for("gear_thermal_suit") + Vector3(0, 0, 1.3))
    player.rotation.y = 0.0
    check(ship.device_room().nearby(1).get("kind", "") == "gear" and not ship.has_panel(), "集市仍依赖按钮")
    ship.credits = 100
    main.handle_action(1, "interact")
    check(ship.gear_stock.thermal_suit == 1 and ship.credits == 55, "集市购买没有进入共享装备仓")
    ship.close_panel()
    main._show_room()
    main._confirm_land()
    player.teleport_to(Vector3(ShipDevices3D.PILOT_X[0], 0, -12.2))
    player.rotation.y = 0.0
    ship.request("ready")
    main._confirm_land()
    await physics_frame
    player = main.players[1] as SpacePlayer3D
    main._update_hud()
    check(main._side_quest_label.text.contains("金色") and main._side_quest_label.text.contains("按 E"), "登陆后没有显示支线线索入口提示")
    player.teleport_to(Vector3(-157, 0, 98))
    main.handle_action(1, "repair")
    check(bool(main.side_quest_states.echo_route.discovered) and int(main.side_quest_states.echo_route.stage) == 1 and not bool(main.side_quest_states.echo_route.completed), "靠近金色线索没有接取支线")
    main._update_hud()
    check(main._side_quest_label.text.contains("第二条路线") and main._side_quest_label.text.contains("辅助中继器"), "接取后没有显示当前支线目标")
    player.teleport_to(Vector3(-140, 0, 77))
    main.handle_action(1, "repair")
    check(int(main.side_quest_states.echo_route.stage) == 2 and not bool(main.side_quest_states.echo_route.completed), "支线目标没有逐段推进")
    player.teleport_to(Vector3(-135, 0, -82))
    main.handle_action(1, "repair")
    check(bool(main.side_quest_states.echo_route.completed) and bool(main.achievement_flags.achievement_echo_route), "支线完成或成就没有解锁")
    # 自由探索活动不占用主线：靠近地图上的青色活动点后，按 E 持续操作并获得共享回收价值。
    check(main._roam_activities != null and main._roam_activities.states.size() == 3, "霜烬星没有建立自由探索活动点")
    var roam_point := Vector2(main._roam_activities.positions.resource_cache)
    player.teleport_to(Vector3(roam_point.x, 0.0, roam_point.y))
    var before_salvage := main.salvage_value
    main.handle_action(1, "repair")
    check(main._roam_activities.has_interaction_job(1), "靠近青色自由活动点后没有开始持续操作")
    main._roam_activities.tick(2.1)
    check(int(main._roam_activities.states.resource_cache.stage) == 1 and main.salvage_value == before_salvage, "自由活动第一阶段没有正确推进")
    main.handle_action(1, "repair")
    main._roam_activities.tick(3.1)
    check(int(main._roam_activities.states.resource_cache.completed_count) == 1 and main.salvage_value == before_salvage + 16, "自由活动完成后没有发放共享回收价值")
    check(Vector2(main._roam_activities.positions.resource_cache) != roam_point, "自由活动完成后没有移动到下一处候选地点")
    var found_roam_log := false
    for entry in main.journal_entries:
        if String(entry).contains("自由活动完成"):
            found_roam_log = true
            break
    check(found_roam_log, "自由活动完成没有留下日志记录")
    if failures.is_empty():
        print("QUEST_MARKET_SMOKE_OK: %d checks" % checks)
        quit(0)
        return
    for f in failures: push_error(f)
    quit(1)

