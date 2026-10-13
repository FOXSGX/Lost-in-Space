extends SceneTree

var checks := 0
var failures := 0

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
    main.network_port = 25844
    main._ship_session.persistence_enabled = false
    main._create_host()
    main._start_planet()
    main.set_process(false)

    var ship_snapshot := main._ship_session.snapshot()
    check(ship_snapshot.has("planet_states"), "飞船快照没有包含星球长期状态")
    check(ship_snapshot.has("goofy_stock") and ship_snapshot.has("gear_stock"), "共享装备/道具没有进入团队快照")

    main._discover_side_quest("echo_route")
    main._complete_side_quest("echo_route")
    check(bool(main.side_quest_states["echo_route"].completed), "支线完成状态没有保存")
    check(main.achievement_flags.has("achievement_echo_route"), "支线完成没有解锁成就")

    var player := main.players.get(1) as SpacePlayer3D
    check(player != null, "测试主机没有生成 1 号船员")
    main._goofy_items.activate(1, "penguin")
    check(main._goofy_items.active_effects.size() == 1, "欢乐道具没有创建可重复效果")
    main._goofy_items.activate(1, "penguin")
    check(main._goofy_items.active_effects.size() == 2, "欢乐道具被错误地限制为冷却/单实例")
    for item_id in ["bubble", "board", "hologram", "smoke"]:
        main._goofy_items.activate(1, item_id)
    main._goofy_items.tick(0.1)
    check(main._goofy_items.active_effects.size() == 6, "欢乐道具视觉效果没有完整生成")

    main._ship_session.active = true
    main._ship_session.in_hub = true
    main._ship_session.credits = 100
    main._ship_session.handle_request(1, "trade", "thermal_suit")
    main._ship_session.handle_request(1, "assign_gear", "thermal_suit")
    check(main._ship_session.has_gear(1, "thermal_suit"), "共享装备没有分配到船员")

    player.carrying = 1
    player.carrying_id = 1
    var old_epoch := main._planet_resource_epoch
    main._save_planet_progress(true)
    check(main.lost_cargo.size() == 1, "任务失败没有生成散落资源")
    check(main._planet_resource_epoch == old_epoch + 1, "离开星球没有刷新资源轮次")
    check(main._ship_session.planet_state(main.PLANET_ID).has("lost_cargo"), "散落资源没有写入星球存档")

    print("战役系统测试：%d 项检查，%d 项失败" % [checks, failures])
    quit(0 if failures == 0 else 1)
