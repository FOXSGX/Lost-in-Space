extends SceneTree

var checks: int = 0
var failures: Array[String] = []
var main: Main3D
var stage: ResonanceStage3D
var phase_filter: String = ""

func _initialize() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    if not args.is_empty():
        phase_filter = String(args[0])
    run.call_deferred()

func stop_after(phase: String) -> bool:
    if phase_filter == phase:
        print("RUNTIME_PROBE_STOP: " + phase)
        print("RESONANCE_RUNTIME_PROBE: %d checks, %d failures" % [checks, failures.size()])
        quit(0 if failures.is_empty() else 1)
        return true
    return false

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func step(seconds: float) -> void:
    var remaining: float = seconds
    while remaining > 0.0:
        var delta: float = minf(remaining, 0.05)
        stage.stage_tick(delta)
        remaining -= delta

func unlock_heat_chain() -> void:
    var sequence: Array = ["left", "right", "relief"]
    var operators: Array = [1, 2, 1] if main.connected_ids.size() > 1 else [1, 1, 1]
    for index in sequence.size():
        var key: String = String(sequence[index])
        var peer_id: int = operators[index]
        var operator: SpacePlayer3D = main.players[peer_id] as SpacePlayer3D
        operator.teleport_to(Vector3(stage.heat_valve_positions[key]))
        main.handle_action(peer_id, "repair")
        step(0.2)
    check(stage.heat_chain_complete, "洞底热阀链没有完成")

func complete_support_relay() -> void:
    var sender: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var receiver: SpacePlayer3D = main.players[2] as SpacePlayer3D
    sender.teleport_to(stage.SUPPORT_RELAY_LOW_POSITION)
    main.handle_action(1, "repair")
    step(0.2)
    receiver.teleport_to(stage.SUPPORT_RELAY_HIGH_POSITION)
    main.handle_action(2, "repair")
    step(0.2)
    check(stage.shortcut_unlocked, "第一节模块后支援接力没有开放第二节")

func complete_module(index: int, fast: bool = false) -> void:
    var module: Dictionary = stage.modules[index]
    var first: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var second: SpacePlayer3D = main.players[2] as SpacePlayer3D
    if index == 1:
        if fast:
            first.teleport_to(Vector3(module["route_position"]))
            main.handle_action(1, "repair")
            step(0.2)
        first.teleport_to(Vector3(module["freight_position"]))
        main.handle_action(1, "pickup")
        step(0.2)
        check(stage.freight_carrier == 1 and first.carrying == 4, "第二模块没有接入磁力货箱")
        second.teleport_to(Vector3(module["support_position"]))
        main.handle_action(2, "repair")
        step(0.2)
        check(int(module["support_peer"]) == 2, "第二模块没有由队友稳定绿色插槽")
        first.teleport_to(Vector3(module["support_position"]))
        main.handle_action(1, "pickup")
        step(0.2)
        check(bool(module["cargo_loaded"]) and stage.freight_carrier == 0, "第二模块货箱没有插入绿色插槽")
    elif index == 2:
        first.teleport_to(Vector3(module["support_position"]))
        main.handle_action(1, "repair")
        step(0.2)
        first.teleport_to(Vector3(module["route_position"]))
        main.handle_action(1, "repair")
        step(0.2)
        check(int(module["beam_step"]) == 1, "第三模块没有拒绝同一玩家连续校准")
        second.teleport_to(Vector3(module["route_position"]))
        main.handle_action(2, "repair")
        step(0.2)
        first.teleport_to(Vector3(module["safety_position"]))
        main.handle_action(1, "repair")
        step(0.2)
        check(int(module["beam_step"]) == 3, "第三模块光束节点没有按顺序校准")
    elif fast:
        first.teleport_to(Vector3(module["route_position"]))
        main.handle_action(1, "repair")
        step(0.2)
    first.teleport_to(Vector3(module["rail_position"]))
    main.handle_action(1, "repair")
    second.teleport_to(Vector3(module["clamp_position"]))
    main.handle_action(2, "repair")
    step(7.4)
    check(String(module["state"]) == "docked", "模块 %d 没有完成对接" % (index + 1))

func complete_reactor_deck() -> void:
    var first: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var second: SpacePlayer3D = main.players[2] as SpacePlayer3D
    var lift: Dictionary = stage.reactor_challenges[0]
    first.teleport_to(Vector3(lift["lower_position"]))
    main.handle_action(1, "repair")
    step(0.2)
    second.teleport_to(Vector3(lift["upper_position"]))
    main.handle_action(2, "repair")
    step(0.2)
    check(stage.reactor_challenge_index == 1, "反应堆升降接力没有完成")
    var mirror: Dictionary = stage.reactor_challenges[1]
    first.teleport_to(Vector3(mirror["left_position"]))
    main.handle_action(1, "repair")
    step(0.2)
    first.teleport_to(Vector3(mirror["right_position"]))
    main.handle_action(1, "repair")
    step(0.2)
    check(int(mirror["step"]) == 1, "镜面反射没有拒绝同一玩家连续操作")
    second.teleport_to(Vector3(mirror["right_position"]))
    main.handle_action(2, "repair")
    step(0.2)
    first.teleport_to(Vector3(mirror["center_position"]))
    main.handle_action(1, "repair")
    step(0.2)
    check(stage.reactor_challenge_index == 2, "反应堆镜面反射没有完成")
    var coolant: Dictionary = stage.reactor_challenges[2]
    second.teleport_to(Vector3(coolant["stabilizer_position"]))
    main.handle_action(2, "repair")
    step(0.2)
    first.teleport_to(Vector3(coolant["coolant_position"]))
    main.handle_action(1, "pickup")
    step(0.2)
    check(stage.reactor_carrier == 1 and first.carrying == 5, "冷却单元没有接入")
    first.teleport_to(Vector3(coolant["coolant_socket_position"]))
    main.handle_action(1, "pickup")
    step(0.2)
    check(stage.reactor_challenge_index == 3 and stage.core_node.visible, "反应堆甲板完成后核心没有开放")

func clear_enemies() -> void:
    for enemy_value in main.enemies.values().duplicate():
        var enemy: SpaceEnemy3D = enemy_value as SpaceEnemy3D
        if enemy != null and is_instance_valid(enemy):
            enemy.queue_free()
    main.enemies.clear()

func run() -> void:
    print("RUNTIME_PROBE: setup_start")
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 24621 + int(Time.get_ticks_msec() % 500)
    main._create_host()
    main.connected_ids = [1, 2]
    main.spawn_player_for_peer(2)
    main._show_route()
    main._electro_land_button.pressed.emit()
    check(not main.game_started, "未准备的队伍能直接登陆")
    main._ship_session.ready_peers = [1, 2]
    main._ship_session.tick(0.0)
    main._electro_land_button.pressed.emit()
    check(main.game_started and main.current_planet_id == "electromagnetic", "航线卡片按钮没有触发登陆")
    if not main.game_started:
        main._confirm_land()
    print("RUNTIME_PROBE: modules_start")
    main.set_process(false)
    stage = main._resonance_stage
    stage.minigames_enabled = false
    for player_value in main.players.values():
        var player: SpacePlayer3D = player_value as SpacePlayer3D
        if player != null:
            player.set_physics_process(false)
    unlock_heat_chain()

    var first_module: Dictionary = stage.modules[0]
    var first_player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var second_player: SpacePlayer3D = main.players[2] as SpacePlayer3D
    first_player.teleport_to(Vector3(first_module["route_position"]))
    main.handle_action(1, "repair")
    step(0.2)
    check(String(first_module["route_choice"]) == "fast", "路线切换没有记录快线")
    first_player.teleport_to(Vector3(first_module["rail_position"]))
    main.handle_action(1, "repair")
    second_player.teleport_to(Vector3(first_module["clamp_position"]))
    main.handle_action(2, "repair")
    step(1.0)
    check(String(first_module["state"]) == "docking", "模块对接没有进入进行状态")
    step(6.0)
    check(String(first_module["state"]) == "docked" and stage.checkpoint == 1, "第一模块没有完成移动对接")
    clear_enemies()
    print("RUNTIME_PROBE: module_one_checked")
    if stop_after("module_one_checked"):
        return

    complete_support_relay()
    complete_module(1)
    clear_enemies()
    complete_module(2)
    check(stage.checkpoint == 3 and stage.reactor_deck_active, "三模块完成后没有进入反应堆甲板")
    complete_reactor_deck()
    clear_enemies()
    print("RUNTIME_PROBE: core_unlocked")
    if stop_after("core_unlocked"):
        return

    first_player.teleport_to(stage.core_node.global_position + Vector3(-0.8, 0.0, 0.0))
    second_player.teleport_to(stage.core_node.global_position + Vector3(0.8, 0.0, 0.0))
    main.handle_action(1, "pickup")
    main.handle_action(2, "pickup")
    step(0.2)
    check(stage.core_carriers.size() == 2, "双人无法接入移动工厂核心")
    main.damage_player(2, 5)
    step(0.2)
    check(stage.core_carriers.is_empty() and first_player.carrying == 0, "倒地后核心没有释放搬运状态")
    main.handle_action(1, "revive")
    step(3.1)
    check(not second_player.downed, "核心搬运者无法救援恢复")
    print("RUNTIME_PROBE: core_release_checked")
    if stop_after("core_release"):
        return

    first_player.teleport_to(stage.core_node.global_position + Vector3(-0.8, 0.0, 0.0))
    second_player.teleport_to(stage.core_node.global_position + Vector3(0.8, 0.0, 0.0))
    main.handle_action(1, "pickup")
    main.handle_action(2, "pickup")
    first_player.teleport_to(stage.extraction_node.position + Vector3(-0.8, 0.0, 0.0))
    second_player.teleport_to(stage.extraction_node.position + Vector3(0.8, 0.0, 0.0))
    step(0.3)
    check(stage.core_delivered and stage.extraction_enabled, "核心没有送到返航平台")
    step(3.2)
    check(main.mission_completed, "全队没有完成返航集合")
    print("RUNTIME_PROBE: extraction_checked")
    if stop_after("extraction"):
        return

    main.return_to_ship("移动轨道工厂双人测试返航")
    await process_frame
    check(main.ship_active, "完成移动轨道工厂后无法返航")
    main._clear_players()
    main.connected_ids = [1]
    main._ship_session.enter_ship(true, [1], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1]
    main._ship_session.select_destination("electromagnetic")
    main._confirm_land()
    print("RUNTIME_PROBE: single_player_start")
    main.set_process(false)
    stage = main._resonance_stage
    stage.minigames_enabled = false
    for player_value in main.players.values():
        var player: SpacePlayer3D = player_value as SpacePlayer3D
        if player != null:
            player.set_physics_process(false)
    unlock_heat_chain()
    var solo: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var solo_module: Dictionary = stage.modules[0]
    solo.teleport_to(Vector3(solo_module["rail_position"]))
    main.handle_action(1, "repair")
    main.handle_action(1, "resonance_drone")
    step(0.2)
    solo.teleport_to(Vector3(solo_module["clamp_position"]))
    main.handle_action(1, "repair")
    step(7.4)
    check(String(solo_module["state"]) == "docked", "单人无人机无法完成第一模块对接")
    check(String(stage.drone_state["target"]) == "" or not bool(stage.drone_state["active"]), "模块完成后无人机仍锁定旧接口")
    print("RUNTIME_PROBE: single_player_checked")
    print("RESONANCE_RUNTIME: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
