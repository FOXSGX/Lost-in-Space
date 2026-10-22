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

func move_to(player: SpacePlayer3D, field: FrostFieldInteractions, id: String) -> void:
    player.global_position = (field.nodes[id] as Node3D).global_position + Vector3(0.8, 0, 0.8)

func run() -> void:
    var main := load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main.network_port = 25732
    main._ship_session.persistence_enabled = false
    main._create_host()
    main._start_planet()
    main.set_process(false)
    var player := main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    var field := main._field_interactions
    check(field != null and field.nodes.size() == 10, "没有生成十处现场交互")

    move_to(player, field, "landing_terminal")
    main.handle_action(1, "interact")
    check(not main.scan_revealed_clues.is_empty() and "当前任务" in field.prompt(player), "联络终端没有给出路线或交互提示")
    field.tick(0.1)
    main._update_hud()
    check(not main._journal_map_view.field_sites.is_empty(), "发现的设备没有登记在地图上")

    move_to(player, field, "emergency_locker")
    main.handle_action(1, "interact")
    check(field.has_interaction_job(1) and is_zero_approx(field.interaction_progress(1)), "持续操作开始后没有进入计时状态")
    field.tick(0.5)
    check(field.interaction_progress(1) > 0.2, "持续操作进度没有随时间增长")
    player.global_position += Vector3(5, 0, 0)
    field.tick(1.5)
    check(is_zero_approx(field.interaction_progress(1)), "中止持续操作后进度没有归零")
    check(not field.states.emergency_locker.opened and field.jobs.is_empty(), "离开补给箱后仍然完成了操作")
    move_to(player, field, "emergency_locker")
    main.handle_action(1, "interact")
    main.handle_action(1, "interact")
    check(field.jobs.is_empty(), "再次按 E 不能中止操作")
    main.handle_action(1, "interact")
    field.tick(1.9)
    check(field.states.emergency_locker.opened, "补给箱未按持续操作解锁")
    var lid := field.nodes.emergency_locker.get_node("Lid") as Node3D
    check(is_equal_approx(lid.rotation_degrees.x, -65.0), "开箱后模型没有掀盖")
    player.health = 3
    player.oxygen = 20
    player.warmth = 0.4
    main.handle_action(1, "interact")
    check(player.health == 4 and is_equal_approx(player.oxygen, 60.0) and is_equal_approx(player.warmth, 0.65), "应急补给没有恢复生存数值")
    var charges := int(field.states.emergency_locker.charges)
    main.handle_action(1, "interact")
    check(int(field.states.emergency_locker.charges) == charges and player.health == 4, "同一玩家可重复领取补给")

    move_to(player, field, "field_heater")
    main.handle_action(1, "deposit")
    check(not field.states.field_heater.boosted, "未修理或未携带电池就能强化炉子")
    main.handle_action(1, "interact")
    field.tick(3.1)
    check(field.states.field_heater.repaired and field.heat_sources().size() == 1, "修理炉子后未提供热源")
    player.sprinting = false
    player.oxygen = 30
    player.warmth = 0.4
    main._tick_survival(1.0)
    check(player.oxygen > 30 and player.warmth > 0.4, "现场供暖炉未接入补氧回温")
    player.carrying = 1
    player.carrying_id = 1
    main._items.add_item(1, "battery", 1)
    main.taken_crates.append(1)
    main.handle_action(1, "interact")
    check(field.states.field_heater.boosted and player.carrying == 0 and player.carrying_id == 0, "安装电池没有腾出双手")
    check(is_equal_approx(float(field.heat_sources()[0].radius), 8.5) and main.taken_crates.has(1) and not main.crates[1].visible, "电池未消耗或热源没有扩大")
    player.global_position = field.nodes.field_heater.global_position + Vector3(7.5, 0, 0)
    player.oxygen = 30
    main._tick_survival(1.0)
    check(player.oxygen > 30, "强化热源的外圈未恢复氧气")

    move_to(player, field, "sample_station")
    main.handle_action(1, "interact")
    check(field.states.sample_station.heard and "冰样" in main._story_label.text, "检测报告未解释晶体回波")
    player.carrying = 2
    player.carrying_id = 1
    main._items.add_item(1, "sample", 1)
    main.taken_samples.append(1)
    var value_before := main.salvage_value
    main.handle_action(1, "interact")
    check(field.states.sample_station.sealed and player.carrying == 0 and main.salvage_value == value_before + 20, "冰样未封存或结算")
    check(field.nodes.sample_station.get_node("ContainedSample").visible, "隔离舱未展示已封存冰样")
    main.handle_action(1, "deposit")
    check(main.salvage_value == value_before + 20, "已封存冰样被重复结算")

    move_to(player, field, "camp_radio")
    main.handle_action(1, "deposit")
    check(not field.states.camp_radio.answered, "未阅读科考记录就能回应")
    main.handle_action(1, "interact")
    main.handle_action(1, "interact")
    check(field.states.camp_radio.heard and field.states.camp_radio.answered and main.story_flags.has("crew_message_returned"), "科考队记录未接入回应选择")

    move_to(player, field, "cargo_winch")
    value_before = main.salvage_value
    main.handle_action(1, "interact")
    field.tick(3.1)
    check(field.states.cargo_winch.opened and main.salvage_value == value_before + 12, "绞盘未回收货物")
    main.handle_action(1, "interact")
    check(main.salvage_value == value_before + 12, "绞盘可以重复刷回收价值")

    move_to(player, field, "west_sign")
    var marker_count := main.map_markers.size()
    main.handle_action(1, "interact")
    field.tick(1.3)
    check(field.states.west_sign.repaired and main.map_markers.size() == marker_count + 1, "扶正路标没有登记地图路线")

    move_to(player, field, "weather_scope")
    main.handle_action(1, "interact")
    field.tick(2.1)
    check(field.states.weather_scope.heard and not main.storm_active, "手动观测没有完成或意外招来风暴")
    main.handle_action(1, "interact")
    check(not field.jobs.has(1), "观测镜冷却没有生效")

    var world_state := main._world_snapshot()
    check(world_state.field_state.sites.field_heater.boosted and world_state.field_state.sites.sample_station.sealed, "中途加入快照缺少现场设备状态")
    field.states.field_heater.boosted = false
    main.sync_full_state(world_state)
    check(field.states.field_heater.boosted and field.nodes.field_heater.get_node("InstalledBattery").visible, "设备快照无法恢复状态和模型")

    main.return_to_ship("现场交互测试返航")
    check(field.nodes.is_empty() and field.jobs.is_empty(), "返航没有清理现场交互")
    print("现场交互测试：%d 项检查，%d 项失败" % [checks, failures])
    quit(0 if failures == 0 else 1)
