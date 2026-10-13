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
    check(ship._market_button.visible and main._screen_view == "ship", "主舱 HUD 没有显示星际集市入口")
    main._show_trade()
    check(main._screen_view == "trade" and main._trade_group.visible and ship.has_panel(), "主舱右上角/航线图无法打开集市")
    ship.credits = 100
    main._trade_request("thermal_suit")
    check(ship.gear_stock.thermal_suit == 1 and ship.credits == 55, "集市购买没有进入共享装备仓")
    ship.close_panel()
    main._show_room()
    main._confirm_land()
    ship.request("ready")
    main._confirm_land()
    await physics_frame
    var player := main.players[1] as SpacePlayer3D
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
    if failures.is_empty():
        print("QUEST_MARKET_SMOKE_OK: %d checks" % checks)
        quit(0)
    for f in failures: push_error(f)
    quit(1)

