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
    await process_frame

func run() -> void:
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25370 + int(Time.get_ticks_msec() % 200)
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
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var other: SpacePlayer3D = main.players[2] as SpacePlayer3D
    player.set_physics_process(false)
    other.set_physics_process(false)
    player.global_position = Vector3(stage.heat_valve_positions["left"])
    await press_e(player)
    check(int(stage.heat_valves["left"]) == 1, "实际 E 键没有触发左侧热阀")
    check(main._interaction_label != null, "交互提示节点不存在")
    print("RESONANCE_E_INPUT: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
