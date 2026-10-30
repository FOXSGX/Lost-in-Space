extends SceneTree

var checks: int = 0
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
    main.network_port = 25195 + int(Time.get_ticks_msec() % 100)
    main._create_host()
    main.connected_ids = [1, 2]
    main.spawn_player_for_peer(2)
    main._start_planet("electromagnetic")
    await process_frame
    main.set_process(false)
    var stage: ResonanceStage3D = main._resonance_stage
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    player._camera_yaw = 0.0
    var forward_move: Vector3 = player._third_person_movement(Vector2(0.0, -1.0))
    var right_move: Vector3 = player._third_person_movement(Vector2(1.0, 0.0))
    check(forward_move.z < -0.9 and absf(forward_move.x) < 0.1, "第三人称前进没有沿相机朝向")
    check(right_move.x > 0.9 and absf(right_move.z) < 0.1, "第三人称横移没有沿相机右侧")
    player._camera_yaw = 0.63
    player._physics_process(0.016)
    check(absf(wrapf(player.rotation.y - 0.63, -PI, PI)) < 0.01, "角色没有持续面朝鼠标控制的相机前方")
    player._camera_yaw_target = 0.0
    player._camera_pitch_target = -0.18
    player._apply_mouse_look(Vector2(10.0, 0.0))
    check(player._camera_yaw_target < 0.0, "鼠标水平移动没有正确累积为转向目标")
    player._apply_mouse_look(Vector2(0.0, -10.0))
    check(player._camera_pitch_target < -0.18, "鼠标向上移动没有让视角向上")
    player._process(0.016)
    check(player._visual != null and absf(player._visual.rotation.y) < 0.01, "角色视觉模型仍然被移动动画覆盖，未跟随玩家根节点朝向")
    if player._visual != null:
        var visual_forward := (-player._visual.global_transform.basis.z).normalized()
        var player_forward := (-player.global_transform.basis.z).normalized()
        check(visual_forward.dot(player_forward) > 0.98, "角色模型正面没有与玩家根节点的镜头前方一致")
    player._resonance_camera_mode = true
    player._camera_yaw = 0.0
    player._camera_yaw_target = 1.0
    player._update_planet_camera(true, 0.016)
    check(player._camera_yaw > 0.0 and player._camera_yaw < 1.0, "鼠标转向没有使用平滑目标角度")
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    player._mouse_capture_requested = true
    player.configure_ship_camera()
    check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not player._mouse_capture_requested, "离开星球后鼠标没有恢复为系统光标")
    player._resonance_camera_mode = false
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    player._update_planet_camera(false, 0.016)
    check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "非共振星场景切换后仍然保持鼠标捕获")
    var probes: Array[Vector3] = [
        Vector3(-34.0, 0.0, 18.0),
        Vector3(55.0, 0.0, -17.0),
        Vector3(-61.0, 0.0, -28.0)
    ]
    for point in probes:
        player.global_position = point
        for _frame in 12:
            player._process(0.05)
        var target: Vector3 = point + Vector3(0.0, 0.9, 0.0)
        var camera: Camera3D = player._camera
        check(camera != null, "玩家相机没有生成")
        if camera == null:
            continue
        check(camera.global_position.distance_to(target) >= SpacePlayer3D.THIRD_PERSON_MIN_DISTANCE - 0.15, "相机在大型设施附近被迫贴脸")
        var player_forward := -player.global_transform.basis.z
        var camera_forward := -camera.global_transform.basis.z
        var camera_offset := (camera.global_position - target).normalized()
        check(camera_forward.dot(player_forward) > 0.92, "相机前方与角色朝向不一致")
        check(camera_offset.dot(player_forward) < -0.72, "相机没有位于角色背后")
        var forward_input := player._third_person_movement(Vector2(0.0, -1.0)).normalized()
        check(forward_input.dot(player_forward) > 0.92, "前进移动没有沿角色和相机共同前方")
        # 远景镜头取代了整组资源降 alpha 的淡出方案：相机必须在洞窟体积内，
        # 场景里也不应再存在任何遮挡淡出缓存或代理体。
        check(camera.global_position.x >= SpacePlayer3D.RESONANCE_CAMERA_BOUNDS_MIN.x - 0.01 and camera.global_position.x <= SpacePlayer3D.RESONANCE_CAMERA_BOUNDS_MAX.x + 0.01, "相机超出洞窟横向安全范围：%s" % point)
        check(camera.global_position.y >= SpacePlayer3D.RESONANCE_CAMERA_BOUNDS_MIN.y - 0.01 and camera.global_position.y <= SpacePlayer3D.RESONANCE_CAMERA_BOUNDS_MAX.y + 0.01, "相机超出洞窟高度安全范围：%s" % point)
        check(camera.global_position.z >= SpacePlayer3D.RESONANCE_CAMERA_BOUNDS_MIN.z - 0.01 and camera.global_position.z <= SpacePlayer3D.RESONANCE_CAMERA_BOUNDS_MAX.z + 0.01, "相机超出洞窟纵向安全范围：%s" % point)
        check(not ("camera_fade_cache" in stage), "遮挡淡出缓存仍然存在，没有彻底移除")
    print("RESONANCE_CAMERA_OCCLUSION: %d checks, %d failures" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
