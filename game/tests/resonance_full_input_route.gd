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
    var remaining := seconds
    while remaining > 0.0:
        var delta := minf(remaining, 0.05)
        stage.stage_tick(delta)
        remaining -= delta

func press_e(player: SpacePlayer3D) -> void:
    var pressed := InputEventKey.new()
    pressed.physical_keycode = KEY_E
    pressed.keycode = KEY_E
    pressed.pressed = true
    Input.parse_input_event(pressed)
    player._physics_process(0.016)
    var released := InputEventKey.new()
    released.physical_keycode = KEY_E
    released.keycode = KEY_E
    released.pressed = false
    Input.parse_input_event(released)
    step(0.2)
    await process_frame

func press_f(player: SpacePlayer3D) -> void:
    var pressed := InputEventKey.new()
    pressed.physical_keycode = KEY_F
    pressed.keycode = KEY_F
    pressed.pressed = true
    Input.parse_input_event(pressed)
    player._physics_process(0.016)
    var released := InputEventKey.new()
    released.physical_keycode = KEY_F
    released.keycode = KEY_F
    released.pressed = false
    Input.parse_input_event(released)
    step(0.2)
    await process_frame

func at(player: SpacePlayer3D, point: Vector3) -> void:
    player.teleport_to(point)

func run() -> void:
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25410 + int(Time.get_ticks_msec() % 200)
    main._create_host()
    main.connected_ids = [1, 2]
    main.spawn_player_for_peer(2)
    main._show_route()
    main._electro_land_button.pressed.emit()
    main._ship_session.ready_peers = [1, 2]
    main._ship_session.tick(0.0)
    main._electro_land_button.pressed.emit()
    await process_frame
    main.set_process(false)
    stage = main._resonance_stage
    var first: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var second: SpacePlayer3D = main.players[2] as SpacePlayer3D
    first.set_physics_process(false)
    second.set_physics_process(false)
    second.set_multiplayer_authority(1)

    at(first, Vector3(stage.heat_valve_positions["left"]))
    await press_e(first)
    at(second, Vector3(stage.heat_valve_positions["right"]))
    await press_e(second)
    at(first, Vector3(stage.heat_valve_positions["relief"]))
    await press_e(first)
    step(0.2)
    check(stage.heat_chain_complete, "E 键路线：热阀链没有完成")

    var module: Dictionary = stage.modules[0]
    at(first, Vector3(module["route_position"]))
    await press_e(first)
    at(first, Vector3(module["rail_position"]))
    await press_e(first)
    at(second, Vector3(module["clamp_position"]))
    await press_e(second)
    step(7.4)
    check(String(module["state"]) == "docked", "E 键路线：第一模块没有完成对接")

    at(first, stage.SUPPORT_RELAY_LOW_POSITION)
    await press_e(first)
    at(second, stage.SUPPORT_RELAY_HIGH_POSITION)
    await press_e(second)
    step(0.2)
    check(stage.shortcut_unlocked, "E 键路线：第一节后支援接力没有开放第二节")

    module = stage.modules[1]
    at(first, Vector3(module["freight_position"]))
    await press_f(first)
    at(second, Vector3(module["support_position"]))
    await press_e(second)
    at(first, Vector3(module["support_position"]))
    await press_f(first)
    step(0.2)
    check(bool(module["cargo_loaded"]), "E/F 键路线：第二模块货箱没有接入")
    at(first, Vector3(module["rail_position"]))
    await press_e(first)
    at(second, Vector3(module["clamp_position"]))
    await press_e(second)
    step(7.4)
    check(String(module["state"]) == "docked", "E 键路线：第二模块没有完成对接")

    module = stage.modules[2]
    at(first, Vector3(module["support_position"]))
    await press_e(first)
    at(first, Vector3(module["route_position"]))
    await press_e(first)
    at(second, Vector3(module["route_position"]))
    await press_e(second)
    at(first, Vector3(module["safety_position"]))
    await press_e(first)
    step(0.2)
    check(int(module["beam_step"]) == 3, "E 键路线：第三模块光束校准没有完成")
    at(first, Vector3(module["rail_position"]))
    await press_e(first)
    at(second, Vector3(module["clamp_position"]))
    await press_e(second)
    step(7.4)
    check(String(module["state"]) == "docked", "E 键路线：第三模块没有完成对接")

    var lift: Dictionary = stage.reactor_challenges[0]
    at(first, Vector3(lift["lower_position"]))
    await press_e(first)
    at(second, Vector3(lift["upper_position"]))
    await press_e(second)
    step(0.2)
    check(stage.reactor_challenge_index == 1, "E 键路线：反应堆升降接力没有完成")

    var mirror: Dictionary = stage.reactor_challenges[1]
    at(first, Vector3(mirror["left_position"]))
    await press_e(first)
    at(second, Vector3(mirror["right_position"]))
    await press_e(second)
    at(first, Vector3(mirror["center_position"]))
    await press_e(first)
    step(0.2)
    check(stage.reactor_challenge_index == 2, "E 键路线：反应堆镜面反射没有完成")

    var coolant: Dictionary = stage.reactor_challenges[2]
    at(second, Vector3(coolant["stabilizer_position"]))
    await press_e(second)
    at(first, Vector3(coolant["coolant_position"]))
    await press_f(first)
    at(first, Vector3(coolant["coolant_socket_position"]))
    await press_f(first)
    step(0.2)
    check(stage.reactor_challenge_index == 3 and stage.core_node.visible, "E/F 键路线：反应堆冷却阶段没有完成")

    at(first, stage.core_node.global_position + Vector3(-0.8, 0.0, 0.0))
    await press_f(first)
    at(second, stage.core_node.global_position + Vector3(0.8, 0.0, 0.0))
    await press_f(second)
    at(first, stage.extraction_node.global_position + Vector3(-0.8, 0.0, 0.0))
    at(second, stage.extraction_node.global_position + Vector3(0.8, 0.0, 0.0))
    step(3.4)
    check(stage.core_delivered and main.mission_completed, "E/F 键路线：核心搬运和返航没有完成")
    print("RESONANCE_FULL_INPUT_ROUTE: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
