extends SceneTree

var checks: int = 0
var failures: Array[String] = []
var main: Main3D
var stage: ResonanceStage3D

func _initialize() -> void:
    run.call_deferred()

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
    check(String(module["state"]) == "docked", "移动模块 %d 没有完成对接" % (index + 1))

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
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 24701
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
    second_player.teleport_to(Vector3(first_module["rail_position"]))
    main.handle_action(2, "repair")
    check(int(first_module["rail_peer"]) == 0, "定场玩家错误地占用了轨道供能接口")
    first_player.teleport_to(Vector3(first_module["rail_position"]))
    main.handle_action(1, "repair")
    check(int(first_module["rail_peer"]) == 1, "导能玩家没有锁住轨道供能接口")
    first_player.teleport_to(Vector3(-55.0, 0.0, 24.0))
    step(1.0)
    check(String(first_module["state"]) == "ready", "导能玩家离开后模块错误开始移动")
    complete_module(0)
    clear_enemies()
    check(stage.checkpoint == 1, "第一节模块没有写入检查点")
    check(Vector3(first_module["position"]) != Vector3(first_module["start_position"]), "模块完成后没有沿轨道移动")
    complete_support_relay()

    complete_module(1, true)
    clear_enemies()
    complete_module(2)
    check(stage.checkpoint == 3 and stage.reactor_deck_active, "三个移动模块完成后没有进入反应堆甲板")
    complete_reactor_deck()

    first_player.teleport_to(stage.core_node.global_position + Vector3(-0.8, 0.0, 0.0))
    second_player.teleport_to(stage.core_node.global_position + Vector3(0.8, 0.0, 0.0))
    main.handle_action(1, "pickup")
    main.handle_action(2, "pickup")
    step(0.2)
    check(stage.core_carriers.size() == 2, "双人无法接入移动工厂核心")

    var enemy: SpaceEnemy3D = main.ENEMY_SCENE.instantiate() as SpaceEnemy3D
    enemy.setup(main.next_enemy_id, 2)
    main.add_child(enemy)
    main.enemies[main.next_enemy_id] = enemy
    enemy.position = first_player.position + Vector3(1.8, 0.0, 0.0)
    var hp: int = enemy.health
    main.attack_from_peer(1)
    check(enemy.health == hp, "核心搬运者仍能攻击")
    main.enemies.erase(enemy.enemy_id)
    enemy.queue_free()

    first_player.teleport_to(stage.extraction_node.position + Vector3(-0.8, 0.0, 0.0))
    second_player.teleport_to(stage.extraction_node.position + Vector3(0.8, 0.0, 0.0))
    step(0.3)
    check(stage.core_delivered and stage.extraction_enabled, "核心没有沿轨道送到返航平台")
    step(3.2)
    check(main.mission_completed, "全队没有完成返航集合")
    print("RESONANCE_RUNTIME: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
