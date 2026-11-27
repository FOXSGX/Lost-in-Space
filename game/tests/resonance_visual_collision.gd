extends SceneTree

## 只读诊断：验证共振星视觉碰撞
##   1. 大结构已经生成碰撞体
##   2. 角色走不进反应堆塔与维修设施（不再穿模）
##   3. 出生点没有被碰撞体包住

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
    run.call_deferred()

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func _walk(player: SpacePlayer3D, yaw: float, steps: int) -> void:
    player._camera_yaw = yaw
    player._camera_yaw_target = yaw
    player.rotation.y = yaw
    Input.action_press("move_up")
    for _step in steps:
        player._physics_process(1.0 / 60.0)
    Input.action_release("move_up")

func _walk_to_point(player: SpacePlayer3D, target: Vector3, max_steps: int) -> void:
    Input.action_press("move_up")
    for _step in max_steps:
        var delta: Vector2 = Vector2(target.x - player.global_position.x, target.z - player.global_position.z)
        if delta.length() < 1.0:
            break
        var yaw: float = atan2(-delta.x, -delta.y)
        player._camera_yaw = yaw
        player._camera_yaw_target = yaw
        player.rotation.y = yaw
        player._physics_process(1.0 / 60.0)
    Input.action_release("move_up")

func _has_standing_room(stage: ResonanceStage3D, anchor: Vector3) -> bool:
    var radius: float = 1.9
    for index in 8:
        var angle: float = TAU * float(index) / 8.0
        var probe: Vector3 = Vector3(anchor.x + cos(angle) * radius, 1.0, anchor.z + sin(angle) * radius)
        if _blocks_point(stage, probe) == "":
            return true
    return false

func _blocks_point(stage: ResonanceStage3D, point: Vector3) -> String:
    for child in stage.world_root.get_children():
        if not (child is StaticBody3D) or not String(child.name).begins_with("VisualCollider_"):
            continue
        var shape_node: CollisionShape3D = (child as Node).get_child(0) as CollisionShape3D
        if shape_node == null:
            continue
        var box: BoxShape3D = shape_node.shape as BoxShape3D
        if box == null:
            continue
        var half: Vector3 = box.size * 0.5
        var delta: Vector3 = point - shape_node.position
        if absf(delta.x) < half.x and absf(delta.z) < half.z and absf(delta.y) < half.y:
            return String(child.name)
    return ""

func run() -> void:
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25610 + int(Time.get_ticks_msec() % 80)
    main._create_host()
    main.connected_ids = [1]
    main._ship_session.enter_ship(true, [1], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1]
    main._ship_session.select_destination("electromagnetic")
    main._confirm_land()
    await process_frame
    main.set_process(false)
    var stage: ResonanceStage3D = main._resonance_stage
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.set_physics_process(false)

    var collider_count: int = 0
    for child in stage.world_root.get_children():
        if child is StaticBody3D and String(child.name).begins_with("VisualCollider_"):
            collider_count += 1
    print("visual colliders: %d" % collider_count)
    check(collider_count >= 30, "视觉碰撞体数量过少：%d" % collider_count)

    # 出生点不能被碰撞体包住
    var spawn: Vector3 = stage.spawn_position(1)
    var spawn_blocked: bool = false
    for child in stage.world_root.get_children():
        if child is StaticBody3D and String(child.name).begins_with("VisualCollider_"):
            var shape: CollisionShape3D = (child as Node).get_child(0) as CollisionShape3D
            if shape == null:
                continue
            var box: BoxShape3D = shape.shape as BoxShape3D
            if box == null:
                continue
            var center: Vector3 = shape.position
            var half: Vector3 = box.size * 0.5
            if absf(spawn.x - center.x) < half.x and absf(spawn.z - center.z) < half.z and spawn.y < center.y + half.y and spawn.y + 1.8 > center.y - half.y:
                spawn_blocked = true
    check(not spawn_blocked, "出生点被视觉碰撞体包住")

    # 走向反应堆塔：应该被挡在塔体外侧，而不是穿过去
    var tower_center: Vector3 = Vector3(55.0, 0.0, -17.0)
    print("--- colliders within 16m of tower ---")
    for child in stage.world_root.get_children():
        if child is StaticBody3D and String(child.name).begins_with("VisualCollider_"):
            var shape_node: CollisionShape3D = (child as Node).get_child(0) as CollisionShape3D
            var box_shape: BoxShape3D = shape_node.shape as BoxShape3D
            if box_shape == null:
                continue
            var offset: float = Vector2(shape_node.position.x - tower_center.x, shape_node.position.z - tower_center.z).length()
            if offset < 16.0:
                print("  d=%.1f center=(%.1f,%.1f,%.1f) size=(%.1f,%.1f,%.1f)" % [
                    offset, shape_node.position.x, shape_node.position.y, shape_node.position.z,
                    box_shape.size.x, box_shape.size.y, box_shape.size.z])
    player.global_position = tower_center + Vector3(0.0, 0.5, 12.0)
    player.velocity = Vector3.ZERO
    _walk(player, 0.0, 260)
    var tower_distance: float = Vector2(player.global_position.x - tower_center.x, player.global_position.z - tower_center.z).length()
    print("walk into tower: end=(%.1f, %.1f, %.1f) flat_distance=%.2f" % [
        player.global_position.x, player.global_position.y, player.global_position.z, tower_distance])
    # 反应堆塔的 GLB 当前是躺倒的（基座包围盒 21.7 x 21.7 x 1.7），
    # 因此这里判定“没有被穿过去”：自由行走 260 帧会前进约 19 米，
    # 角色必须停在塔心之前。
    check(player.global_position.z > tower_center.z - 1.2, "角色穿过了反应堆塔体：z=%.2f" % player.global_position.z)

    # 走向废弃维修仓：同样应该被挡住
    var facility_center: Vector3 = Vector3(-61.0, 0.0, -28.0)
    player.global_position = facility_center + Vector3(0.0, 0.5, 10.0)
    player.velocity = Vector3.ZERO
    _walk(player, 0.0, 260)
    var facility_distance: float = Vector2(player.global_position.x - facility_center.x, player.global_position.z - facility_center.z).length()
    print("walk into maintenance: end=(%.1f, %.1f, %.1f) flat_distance=%.2f" % [
        player.global_position.x, player.global_position.y, player.global_position.z, facility_distance])
    check(facility_distance > 2.0, "角色穿进了维修设施：距离 %.2f" % facility_distance)

    # 关键交互锚点必须还有可站立的位置（装置本身可以是实体）
    var anchors: Array = []
    for key in stage.heat_valve_positions.keys():
        anchors.append(["热阀:%s" % String(key), Vector3(stage.heat_valve_positions[key])])
    for index in stage.modules.size():
        var module: Dictionary = stage.modules[index]
        for field in ["rail_position", "clamp_position", "support_position", "safety_position", "route_position"]:
            anchors.append(["模块%d.%s" % [index + 1, field], Vector3(module[field])])
    anchors.append(["接力低位", stage.SUPPORT_RELAY_LOW_POSITION])
    anchors.append(["接力高位", stage.SUPPORT_RELAY_HIGH_POSITION])
    for challenge in stage.reactor_challenges:
        var challenge_id: String = String(challenge.get("id", "reactor"))
        for field in ["lower_position", "upper_position", "left_position", "right_position", "center_position", "coolant_position", "coolant_socket_position", "stabilizer_position"]:
            if challenge.has(field):
                anchors.append(["%s.%s" % [challenge_id, field], Vector3(challenge[field])])
    anchors.append(["中央核心", stage.core_node.global_position])
    anchors.append(["返航平台", stage.extraction_node.position])
    var blocked_anchors: Array[String] = []
    for entry in anchors:
        if not _has_standing_room(stage, Vector3(entry[1])):
            blocked_anchors.append(String(entry[0]))
    print("anchors=%d blocked=%d" % [anchors.size(), blocked_anchors.size()])
    for item in blocked_anchors:
        print("  blocked: %s" % item)
    check(blocked_anchors.is_empty(), "有 %d 个交互锚点已经没有可站立位置" % blocked_anchors.size())

    # 主路线不能被碰撞盒挡死：从出生点绕过进料处理区走到第一个热阀
    player.global_position = stage.spawn_position(1) + Vector3(0.0, 0.4, 0.0)
    player.velocity = Vector3.ZERO
    var waypoints: Array[Vector3] = [
        Vector3(-58.0, 0.4, 24.0),
        Vector3(-58.0, 0.4, 14.0),
        Vector3(-49.0, 0.4, 14.0)
    ]
    for waypoint in waypoints:
        _walk_to_point(player, waypoint, 240)
    var heat_target: Vector3 = Vector3(stage.heat_valve_positions["left"])
    var heat_distance: float = Vector2(player.global_position.x - heat_target.x, player.global_position.z - heat_target.z).length()
    print("walk spawn->heat valve: end=(%.1f, %.1f, %.1f) distance=%.2f" % [
        player.global_position.x, player.global_position.y, player.global_position.z, heat_distance])
    check(heat_distance < 4.0, "从出生点走不到第一个热阀：距离 %.2f" % heat_distance)

    print("RESONANCE_VISUAL_COLLISION: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
