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

func is_safe(stage: ResonanceStage3D, point: Vector3) -> bool:
    return not stage._is_lava_position(point)

func run() -> void:
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 24573 + int(Time.get_ticks_msec() % 200)
    main._create_host()
    await process_frame
    main.connected_ids = [1, 2]
    main._start_planet("electromagnetic")
    await process_frame
    var stage: ResonanceStage3D = main._resonance_stage
    check(stage != null and stage.is_active(), "空间检查没有启动共振星阶段")
    check(stage.SAFE_DECK_RECTS.size() >= 8, "洞穴安全甲板分区不足")
    check(stage.SAFE_PATH_SEGMENTS.size() >= 5, "轨道安全连接路径不足")

    var key_points: Array[Vector3] = []
    for value in stage.heat_valve_positions.values():
        key_points.append(Vector3(value))
    for module_value in stage.modules:
        var module: Dictionary = module_value
        for key in ["rail_position", "clamp_position", "support_position", "safety_position", "route_position"]:
            key_points.append(Vector3(module[key]))
    for challenge_value in stage.reactor_challenges:
        var challenge: Dictionary = challenge_value
        for key in ["lower_position", "upper_position", "left_position", "right_position", "center_position", "coolant_position", "coolant_socket_position", "stabilizer_position"]:
            if challenge.has(key):
                key_points.append(Vector3(challenge[key]))
    key_points.append(Vector3(stage.core_node.global_position))
    key_points.append(Vector3(stage.extraction_node.global_position))
    key_points.append(Vector3(-47.0, 0.0, 30.0))
    for index in key_points.size():
        var point: Vector3 = key_points[index]
        check(absf(point.x) < stage.LAVA_MARGIN_X and absf(point.z) < stage.LAVA_MARGIN_Z, "关键交互点越过洞穴地图边界 #%d" % index)
        check(is_safe(stage, point), "关键交互点落在熔岩判定区 #%d: %s" % [index, point])

    check(stage._is_lava_position(Vector3(73.0, 0.0, 0.0)), "地图外缘没有熔岩死亡区")
    check(stage._is_lava_position(Vector3(-2.0, 0.0, 29.0)), "洞底熔岩裂隙没有生效")
    check(not stage._is_lava_position(Vector3(-28.0, 3.1, -12.0)), "高位维护桥没有安全站立层")
    check(not stage._is_lava_position(stage.SUPPORT_RELAY_LOW_POSITION), "支援接力低位发送端落在熔岩区")
    check(not stage._is_lava_position(stage.SUPPORT_RELAY_HIGH_POSITION), "支援接力高位接收端落在熔岩区")

    var catwalk_decks: int = 0
    var catwalk_fences: int = 0
    for child in stage.world_root.get_children():
        if child is StaticBody3D:
            var node_name: String = String(child.name)
            if node_name.contains("Fence"):
                catwalk_fences += 1
            elif node_name.begins_with("ResonanceCatwalkCollision_"):
                catwalk_decks += 1
    check(catwalk_decks == 3, "中层检修平台数量不正确：%d" % catwalk_decks)
    check(catwalk_fences >= 6, "高架平台缺少防坠护栏碰撞：%d" % catwalk_fences)
    check(stage.world_root.get_node_or_null("ResonanceCatwalkRamp_1") != null, "中层观景桥入口坡道缺失")
    check(stage.art_asset_nodes.size() >= 15, "洞穴与工业美术节点没有全部接入")
    check(stage.art_asset_nodes.has("ArtCavernShell"), "洞穴壳体没有接入实际场景")
    check(stage.art_asset_nodes.has("ArtReactorTower"), "反应堆塔没有接入实际场景")
    check(stage.art_asset_nodes.has("ArtExtractionPlatform"), "返航平台没有接入实际场景")
    check(stage.reactor_mechanism_nodes.has("lift_platform"), "反应堆升降甲板没有接入场景")
    check(stage.reactor_mechanism_nodes.has("mirror_left") and stage.reactor_mechanism_nodes.has("mirror_right") and stage.reactor_mechanism_nodes.has("mirror_center"), "反应堆三面镜节点不完整")
    check(stage.reactor_mechanism_nodes.has("coolant_socket") and stage.reactor_mechanism_nodes.has("coolant_stabilizer"), "冷却接收座机制节点不完整")
    var lift_platform: Node3D = stage.reactor_mechanism_nodes.get("lift_platform") as Node3D
    check(lift_platform != null and lift_platform.get_node_or_null("ReactorLiftPlatformCollision") != null, "升降甲板没有独立碰撞体")
    check(stage.vertical_shaft_gate_node != null and not bool(stage.vertical_shaft_gate_node.get_meta("resonance_gate_open", true)), "垂直井安全闸提前开放")
    check(stage.vertical_shaft_gate_body != null and stage.vertical_shaft_gate_body.collision_layer == 2, "垂直井安全闸初始碰撞没有锁定")
    check(stage.world_root.get_node_or_null("ResonanceObservationBridgeCollision") != null, "中层观景桥缺少碰撞体")
    check(stage.world_root.get_node_or_null("ResonanceShaftDeckCollision") != null, "高位竖井观察台缺少碰撞体")
    check(stage.world_root.get_node_or_null("ResonanceShaftRampCollision") != null, "高位竖井观察台缺少登台坡道")
    check(not stage._is_lava_position(Vector3(0.0, 6.0, -12.0)), "中层观景桥被错误判定为熔岩")
    check(stage._is_lava_position(Vector3(0.0, 0.0, -34.0)), "桥面高度的熔岩豁免范围过大，地面熔岩判定被破坏")
    var ground_body: StaticBody3D = stage.world_root.get_node_or_null("ResonanceGroundCollision") as StaticBody3D
    check(ground_body != null and ground_body.get_child_count() >= 7, "熔岩裂隙没有拆出独立地表碰撞片")
    check(stage.world_root.get_node_or_null("CliffEdgesVisuals") != null, "悬崖断面视觉节点缺失")
    check(stage.world_root.get_node_or_null("SafeDeckVisuals") != null, "安全岩台视觉节点缺失")
    check(stage.world_root.get_node_or_null("SupportResonanceRelay") != null, "支援接力视觉节点缺失")
    check(stage.support_relay_nodes.has("low") and stage.support_relay_nodes.has("high"), "支援接力两端指示器不完整")
    check(not ("camera_occluder_nodes" in stage), "相机遮挡代理仍然存在，远景镜头方案不应再依赖遮挡淡出")
    var local_player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var camera_target: Vector3 = local_player.global_position + Vector3(0.0, 0.9, 0.0)
    var camera_candidate: Vector3 = local_player._choose_resonance_camera_position(camera_target)
    check(camera_candidate.distance_to(camera_target) >= 10.0, "共振星相机安全距离过短")
    var lava_base_y: float = stage.lava_surface_node.position.y
    stage.stage_tick(16.2)
    check(stage.lava_tide_active and stage.lava_surface_node.position.y > lava_base_y, "熔岩潮汐没有抬升表面危险层")

    print("RESONANCE_SPATIAL_LINKS: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
