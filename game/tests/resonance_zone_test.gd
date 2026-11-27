extends SceneTree

## 共振星分区包裹：闸门、分区推进、镜头限制。

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func run() -> void:
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 27510 + int(Time.get_ticks_msec() % 60)
    main._create_host()
    main.connected_ids = [1]
    main.spawn_player_for_peer(1)
    main._ship_session.enter_ship(true, [1], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1]
    main._ship_session.select_destination("electromagnetic")
    main._confirm_land()
    await process_frame
    var stage: ResonanceStage3D = main._resonance_stage
    check(stage != null, "共振星没有创建")
    if stage == null:
        print("RESONANCE_ZONE: %d checks, %d failures" % [checks, failures.size()])
        quit(1)
        return

    # 1. 每个模块边界都有一道闸门
    check(stage.zone_gates.size() == stage.modules.size() - 1, "闸门数量与模块边界不一致：%d" % stage.zone_gates.size())
    check(stage.active_zone == 0, "初始分区不是第一区：%d" % stage.active_zone)

    # 2. 初始所有闸门关闭且有碰撞
    for gate in stage.zone_gates:
        var node: Node3D = gate as Node3D
        check(node.visible, "初始闸门没有显示：%s" % node.name)
        var has_collision := false
        for child in node.get_children():
            var body := child as StaticBody3D
            if body != null and body.collision_layer != 0:
                has_collision = true
        check(has_collision, "初始闸门没有碰撞：%s" % node.name)

    # 3. 模块 1 对接后推进到第二区，第一道闸门打开
    stage.modules[0]["state"] = "docked"
    stage.modules[0]["phase"] = "docked"
    stage._on_module_docked(1)
    await process_frame
    check(stage.active_zone == 1, "对接模块 1 后没有推进分区：%d" % stage.active_zone)
    var first_gate: Node3D = stage.zone_gates[0]
    check(not first_gate.visible, "第一道闸门没有收起")
    var gate_body_collision := 0
    for child in first_gate.get_children():
        var body := child as StaticBody3D
        if body != null:
            gate_body_collision = maxi(gate_body_collision, body.collision_layer)
    check(gate_body_collision == 0, "第一道闸门碰撞没有关闭")

    # 4. 镜头被限制在当区半径内
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    check(player != null, "玩家不存在")
    if player != null:
        var focus: Vector3 = stage.zone_camera_focus()
        var far_point: Vector3 = focus + Vector3(60.0, 0.0, 60.0)
        var clamped: Vector3 = player._clamp_resonance_camera(far_point)
        var horizontal := Vector2(clamped.x - focus.x, clamped.z - focus.z).length()
        check(horizontal <= SpacePlayer3D.RESONANCE_ZONE_CAMERA_RADIUS + 0.01, "镜头没有被限制在当区：%.1f" % horizontal)

    print("RESONANCE_ZONE: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
