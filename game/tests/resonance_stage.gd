extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
    run.call_deferred()

func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures.append(message)
        push_error(message)

func step(stage: ResonanceStage3D, seconds: float) -> void:
    var remaining: float = seconds
    while remaining > 0.0:
        var delta: float = minf(remaining, 0.05)
        # 该脚本验证轨道机关的状态链，敌人战斗由独立运行时测试覆盖；
        # 每个采样步清掉战斗实体，避免安全闸测试被随机火力打断。
        clear_enemies(stage.controller)
        stage.stage_tick(delta)
        clear_enemies(stage.controller)
        remaining -= delta

func clear_enemies(main: Main3D) -> void:
    for enemy_value in main.enemies.values().duplicate():
        var enemy: SpaceEnemy3D = enemy_value as SpaceEnemy3D
        if enemy != null and is_instance_valid(enemy):
            enemy.queue_free()
    main.enemies.clear()

func unlock_heat_chain(main: Main3D, stage: ResonanceStage3D) -> void:
    var sequence: Array = ["left", "right", "relief"]
    var operators: Array = [1, 2, 1] if main.connected_ids.size() > 1 else [1, 1, 1]
    for index in sequence.size():
        var key: String = String(sequence[index])
        var peer_id: int = operators[index]
        var operator: SpacePlayer3D = main.players[peer_id] as SpacePlayer3D
        if index == 1 and main.connected_ids.size() > 1:
            var same_player: SpacePlayer3D = main.players[1] as SpacePlayer3D
            same_player.global_position = Vector3(stage.heat_valve_positions[key])
            main.handle_action(1, "repair")
            step(stage, 0.2)
            check(int(stage.heat_valves[key]) == 0, "同一玩家连续操作热阀时没有被拒绝")
        operator.global_position = Vector3(stage.heat_valve_positions[key])
        main.handle_action(peer_id, "repair")
        step(stage, 0.2)
    check(stage.heat_chain_complete, "洞底热阀链没有完成")

func complete_support_relay(main: Main3D, stage: ResonanceStage3D) -> void:
    var sender: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var receiver: SpacePlayer3D = main.players[2] as SpacePlayer3D
    sender.global_position = stage.SUPPORT_RELAY_LOW_POSITION
    main.handle_action(1, "repair")
    step(stage, 0.2)
    receiver.global_position = stage.SUPPORT_RELAY_HIGH_POSITION
    main.handle_action(2, "repair")
    step(stage, 0.2)
    check(stage.shortcut_unlocked, "第一节模块后没有完成支援接力，第二节路线无法开放")

func run() -> void:
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 24569
    main._create_host()
    await process_frame
    main.connected_ids = [1, 2]
    main._start_planet("electromagnetic")
    await process_frame
    check(main.game_started and main.current_planet_id == "electromagnetic", "共振星没有启动")
    var stage: ResonanceStage3D = main._resonance_stage
    stage.minigames_enabled = false
    check(stage.modules.size() == 3, "轨道工厂没有生成三个移动模块")
    check(String(stage.modules[0]["state"]) == "ready", "第一模块没有处于待机状态")
    check(stage.role_assignments.get(1, "") == "conduit", "玩家 1 未分配导能设备")
    check(stage.role_assignments.get(2, "") == "anchor", "玩家 2 未分配定场设备")
    unlock_heat_chain(main, stage)

    var module: Dictionary = stage.modules[0]
    var conduit: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var anchor: SpacePlayer3D = main.players[2] as SpacePlayer3D
    conduit.global_position = Vector3(module["route_position"])
    main.handle_action(1, "repair")
    step(stage, 0.2)
    check(String(module["route_choice"]) == "fast", "路线切换没有进入低位快线")
    conduit.global_position = Vector3(module["rail_position"])
    main.handle_action(1, "repair")
    anchor.global_position = Vector3(module["clamp_position"])
    main.handle_action(2, "repair")
    check(String(module["state"]) == "docking", "供能和夹具锁止后没有开始移动对接")
    step(stage, 1.0)
    check(float(module["docking_progress"]) > 0.0, "移动对接没有推进")
    step(stage, 2.2)
    check(String(module["state"]) == "traveling" or String(module["state"]) == "docked", "模块没有进入沿轨移动")
    step(stage, 3.2)
    check(String(module["state"]) == "docked", "第一模块没有完成移动对接")
    check(stage.checkpoint == 1, "第一模块没有写入轨道检查点")
    complete_support_relay(main, stage)

    main.connected_ids = [1, 2, 3, 4]
    stage._assign_roles()
    main.spawn_player_for_peer(3)
    main.spawn_player_for_peer(4)
    check(stage.role_assignments.get(3, "") == "support", "第三名玩家未分配支援职责")
    check(stage.role_assignments.get(4, "") == "support", "第四名玩家未分配支援职责")
    var second_module: Dictionary = stage.modules[1]
    var support: SpacePlayer3D = main.players[3] as SpacePlayer3D
    var safety: SpacePlayer3D = main.players[4] as SpacePlayer3D
    conduit.global_position = Vector3(second_module["route_position"])
    main.handle_action(1, "repair")
    step(stage, 0.2)
    conduit.global_position = Vector3(second_module["freight_position"])
    main.handle_action(1, "pickup")
    step(stage, 0.2)
    check(stage.freight_carrier == 1 and conduit.carrying == 4, "第二模块没有接入磁力货箱")
    support.global_position = Vector3(second_module["support_position"])
    main.handle_action(3, "repair")
    step(stage, 0.2)
    check(int(second_module["support_peer"]) == 3, "第三名玩家没有稳定绿色插槽")
    conduit.global_position = Vector3(second_module["support_position"])
    main.handle_action(1, "pickup")
    step(stage, 0.2)
    check(bool(second_module["cargo_loaded"]) and stage.freight_carrier == 0, "第二模块货箱没有插入绿色插槽")
    safety.global_position = Vector3(second_module["safety_position"])
    main.handle_action(4, "repair")
    step(stage, 0.2)
    check(int(second_module["support_peer"]) == 3, "第三名玩家没有插入保险栓")
    check(int(second_module["safety_peer"]) == 4, "第四名玩家没有布置安全锚点")
    conduit.global_position = Vector3(second_module["rail_position"])
    main.handle_action(1, "repair")
    anchor.global_position = Vector3(second_module["clamp_position"])
    main.handle_action(2, "repair")
    step(stage, 7.0)
    check(String(second_module["state"]) == "docked", "支援模块没有完成对接")
    check(stage.checkpoint == 2, "第二模块没有写入检查点")
    check(bool(second_module["fast_route_used"]), "第二模块没有记录快线选择")
    clear_enemies(main)


    var third_module: Dictionary = stage.modules[2]
    conduit.global_position = Vector3(third_module["support_position"])
    main.handle_action(1, "repair")
    step(stage, 0.2)
    conduit.global_position = Vector3(third_module["route_position"])
    main.handle_action(1, "repair")
    step(stage, 0.2)
    check(int(third_module["beam_step"]) == 1, "第三模块没有拒绝同一玩家连续校准")
    anchor.global_position = Vector3(third_module["route_position"])
    main.handle_action(2, "repair")
    step(stage, 0.2)
    conduit.global_position = Vector3(third_module["safety_position"])
    main.handle_action(1, "repair")
    step(stage, 0.2)
    check(int(third_module["beam_step"]) == 3, "第三模块光束节点没有按顺序校准")
    conduit.global_position = Vector3(third_module["rail_position"])
    main.handle_action(1, "repair")
    anchor.global_position = Vector3(third_module["clamp_position"])
    main.handle_action(2, "repair")
    step(stage, 7.4)
    check(String(third_module["state"]) == "docked", "第三模块没有完成光束校准后的对接")

    var lift: Dictionary = stage.reactor_challenges[0]
    conduit.global_position = Vector3(lift["lower_position"])
    main.handle_action(1, "repair")
    step(stage, 0.2)
    conduit.global_position = Vector3(58.0, 0.0, -22.0)
    step(stage, 1.5)
    check(conduit.global_position.y > 2.5, "升降甲板没有把站在平台上的玩家抬到高位")
    anchor.global_position = Vector3(lift["upper_position"])
    main.handle_action(2, "repair")
    step(stage, 0.2)
    check(stage.reactor_challenge_index == 1, "反应堆升降接力没有完成")
    var mirror: Dictionary = stage.reactor_challenges[1]
    conduit.global_position = Vector3(mirror["left_position"])
    main.handle_action(1, "repair")
    step(stage, 0.2)
    conduit.global_position = Vector3(mirror["right_position"])
    main.handle_action(1, "repair")
    step(stage, 0.2)
    check(int(mirror["step"]) == 1, "反应堆镜面没有拒绝同一玩家连续操作")
    anchor.global_position = Vector3(mirror["right_position"])
    main.handle_action(2, "repair")
    step(stage, 0.2)
    conduit.global_position = Vector3(mirror["center_position"])
    main.handle_action(1, "repair")
    step(stage, 0.2)
    check(stage.reactor_challenge_index == 2, "反应堆镜面反射没有完成")
    var coolant: Dictionary = stage.reactor_challenges[2]
    anchor.global_position = Vector3(coolant["stabilizer_position"])
    main.handle_action(2, "repair")
    step(stage, 0.2)
    conduit.global_position = Vector3(coolant["coolant_position"])
    main.handle_action(1, "pickup")
    step(stage, 0.2)
    conduit.global_position = Vector3(coolant["coolant_socket_position"])
    main.handle_action(1, "pickup")
    step(stage, 0.2)
    check(stage.reactor_challenge_index == 3 and stage.core_node.visible, "反应堆冷却单元完成后核心没有开放")
    check(bool(stage.vertical_shaft_gate_node.get_meta("resonance_gate_open", false)) and stage.vertical_shaft_gate_body.collision_layer == 0, "反应堆稳定后垂直井安全闸没有打开")

    stage.storm_clock = 34.9
    step(stage, 0.3)
    check(stage.storm_active, "磁暴没有按轨道工厂规则触发")
    main._update_vision_overlay()
    check(not main._vision_overlay.visible, "共振星轨道压力仍然启用了周期视线遮罩")

    print("共振星移动轨道测试：%d 项检查，%d 项失败" % [checks, failures.size()])
    quit(1 if not failures.is_empty() else 0)
