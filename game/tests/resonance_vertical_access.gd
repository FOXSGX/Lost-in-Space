extends SceneTree

## 只读诊断：检查共振星所有登高坡道两端是否落在可站立面上，
## 以及坡道顶端是否与目标平台高度接续。

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func _shape_size(body: Node3D) -> Vector3:
    var shape_node: CollisionShape3D = body.get_child(0) as CollisionShape3D
    if shape_node == null:
        return Vector3.ZERO
    var box: BoxShape3D = shape_node.shape as BoxShape3D
    return box.size if box != null else Vector3.ZERO

func _ends(body: Node3D, size: Vector3) -> Array:
    var half: float = size.x * 0.5
    return [body.global_transform * Vector3(-half, 0.0, 0.0), body.global_transform * Vector3(half, 0.0, 0.0)]

func run() -> void:
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25410 + int(Time.get_ticks_msec() % 100)
    main._create_host()
    main.connected_ids = [1, 2]
    main.spawn_player_for_peer(2)
    main._start_planet("electromagnetic")
    await process_frame
    main.set_process(false)
    var stage: ResonanceStage3D = main._resonance_stage

    var ramp_names: Array[String] = []
    for body in stage.world_root.find_children("*Ramp*", "StaticBody3D", true, false):
        ramp_names.append(String(body.name))
    var deck_names: Array[String] = []
    for body in stage.world_root.find_children("*Catwalk*", "StaticBody3D", true, false):
        deck_names.append(String(body.name))
    for body in stage.world_root.find_children("*Bridge*", "StaticBody3D", true, false):
        deck_names.append(String(body.name))
    for body in stage.world_root.find_children("*Shaft*", "StaticBody3D", true, false):
        deck_names.append(String(body.name))

    print("--- 坡道 ---")
    for name_value in ramp_names:
        var body: Node3D = stage.world_root.get_node_or_null(name_value) as Node3D
        if body == null:
            continue
        var size: Vector3 = _shape_size(body)
        var ends: Array = _ends(body, size)
        var low: Vector3 = ends[0] if ends[0].y <= ends[1].y else ends[1]
        var high: Vector3 = ends[1] if ends[0].y <= ends[1].y else ends[0]
        var low_lava: bool = stage._is_lava_position(low)
        var high_lava: bool = stage._is_lava_position(high)
        print("%-34s low=(%.1f, %.2f, %.1f)%s high=(%.1f, %.2f, %.1f)%s" % [
            name_value, low.x, low.y, low.z, "  [熔岩]" if low_lava else "",
            high.x, high.y, high.z, "  [熔岩]" if high_lava else ""])
        check(not low_lava, "坡道低端落在熔岩上：%s" % name_value)
        check(not high_lava, "坡道高端落在熔岩上：%s" % name_value)
        check(low.y < 1.2, "坡道低端没有接近地面：%s (y=%.2f)" % [name_value, low.y])

    print("--- 平台 ---")
    for name_value in deck_names:
        var body: Node3D = stage.world_root.get_node_or_null(name_value) as Node3D
        if body == null:
            continue
        var size: Vector3 = _shape_size(body)
        print("%-34s center=(%.1f, %.2f, %.1f) size=(%.1f, %.1f, %.1f)" % [
            name_value, body.global_position.x, body.global_position.y, body.global_position.z,
            size.x, size.y, size.z])

    print("RESONANCE_VERTICAL_ACCESS: %d checks, %d failures" % [checks, failures.size()])
    if not _walk_test(main, stage, "ResonanceCatwalkRamp_1", 5.4, 300):
        failures.append("中层观景桥坡道爬不上去")
        checks += 1
    if not _walk_test(main, stage, "ResonanceShaftRampCollision", 11.4, 460):
        failures.append("高位观察台坡道爬不上去")
        checks += 1
    print("RESONANCE_VERTICAL_WALK: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)

func _walk_test(main: Main3D, stage: ResonanceStage3D, ramp_name: String, target_height: float, steps: int) -> bool:
    var ramp: Node3D = stage.world_root.get_node_or_null(ramp_name) as Node3D
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    if ramp == null or player == null:
        return false
    var size: Vector3 = _shape_size(ramp)
    var ends: Array = _ends(ramp, size)
    var low: Vector3 = ends[0] if ends[0].y <= ends[1].y else ends[1]
    player.global_position = low + Vector3(-1.2, 0.8, 0.0)
    player.velocity = Vector3.ZERO
    player._camera_yaw = -PI * 0.5
    player._camera_yaw_target = player._camera_yaw
    player.rotation.y = player._camera_yaw
    Input.action_press("move_up")
    var peak_height: float = player.global_position.y
    for _step in steps:
        player._physics_process(1.0 / 60.0)
        peak_height = maxf(peak_height, player.global_position.y)
    Input.action_release("move_up")
    print("walk %-30s from x=%.1f y=%.2f -> peak y=%.2f (end x=%.1f y=%.2f)" % [
        ramp_name, low.x, low.y, peak_height, player.global_position.x, player.global_position.y])
    return peak_height >= target_height - 0.4
