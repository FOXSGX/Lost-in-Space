extends SceneTree

## 只读探针：对比共振星当前镜头与“大空间”候选方案的画面。
## 不修改星球逻辑、场景资源或主场景 GLB，只做临时相机与节点可见性切换。

var output_dir: String = ""
var main: Main3D
var stage: ResonanceStage3D
var failures: int = 0

func _initialize() -> void:
    run.call_deferred()

func _shot(label: String) -> void:
    for _frame in 3:
        await process_frame
    var image: Image = root.get_texture().get_image()
    var result: Error = image.save_png(output_dir.path_join(label + ".png"))
    if result != OK:
        failures += 1
    print("SPACE_PROBE %s save=%d" % [label, result])

func _set_hud_visible(visible_state: bool) -> void:
    for control in [main._objective_panel, main._vitals_panel, main._compass_panel, main._interaction_panel, main._subtitle_panel, main._side_quest_panel, main._alert_label, main._hint_label, main._status_label, main._game_status_label]:
        if control != null:
            control.visible = visible_state
    for node in stage.world_root.find_children("*", "Label3D", true, false):
        (node as Label3D).visible = visible_state

func _master() -> Node3D:
    return stage.art_asset_nodes.get("ArtResonanceMasterScene") as Node3D

func _hide_matching(patterns: Array) -> int:
    var target: Node3D = _master()
    if target == null:
        return 0
    var hidden: int = 0
    for node in target.find_children("*", "Node3D", true, false):
        var normalized: String = String(node.name).replace("/", "_")
        for pattern in patterns:
            if normalized.begins_with(String(pattern)):
                (node as Node3D).visible = false
                hidden += 1
                break
    return hidden

func _place(point: Vector3) -> void:
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.global_position = point
    if player._camera != null:
        player._camera.current = true
    for _frame in 20:
        player._process(0.05)
        await process_frame
    print("SPACE_PROBE player=%s camera=%s" % [player.global_position, player._camera.global_position])

func _show_all() -> void:
    var target: Node3D = _master()
    if target == null:
        return
    for node in target.find_children("*", "Node3D", true, false):
        (node as Node3D).visible = true

func _variant(label: String, offset: Vector3, look_offset: Vector3, fov: float) -> void:
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    var base: Vector3 = player.global_position
    var camera: Camera3D = Camera3D.new()
    camera.name = "SpaceProbeCamera"
    camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    camera.fov = fov
    camera.position = base + offset
    main.add_child(camera)
    camera.look_at(base + look_offset, Vector3.UP)
    camera.current = true
    await _shot(label)
    camera.current = false
    camera.queue_free()

func _aabb_size(root_node: Node3D) -> Vector3:
    if root_node == null:
        return Vector3.ZERO
    var merged: AABB = AABB()
    var first: bool = true
    for child in root_node.find_children("*", "MeshInstance3D", true, false):
        var mesh: MeshInstance3D = child as MeshInstance3D
        if mesh == null:
            continue
        var box: AABB = mesh.global_transform * mesh.get_aabb()
        if first:
            merged = box
            first = false
        else:
            merged = merged.merge(box)
    return merged.size

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    output_dir = String(args[0]) if not args.is_empty() else "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261017-resonance-space-readability/captures"
    DirAccess.make_dir_recursive_absolute(output_dir)
    main = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 25310 + int(Time.get_ticks_msec() % 100)
    main._create_host()
    main.connected_ids = [1, 2]
    main.spawn_player_for_peer(2)
    main._start_planet("electromagnetic")
    await process_frame
    stage = main._resonance_stage
    main.set_process(false)
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.set_physics_process(false)

    # 基线：玩家站在第一节模块旁，使用当前 5.8m 肩后镜头
    await _place(Vector3(-34.0, 0.0, 18.0))
    await _shot("01-current-with-hud")
    _set_hud_visible(false)
    await _shot("02-current-no-hud")

    # 相机拉远到 16m / 抬高 9m
    player.set_process(false)
    await _variant("03-far-16m", Vector3(0.0, 9.0, 16.0), Vector3(0.0, 1.2, 0.0), 62.0)

    # 去掉桁架（保留龙门与通道）
    var hidden_spine: int = _hide_matching(["FactorySpine", "SpineTrack", "SpinePipe"])
    print("hidden spine nodes: %d" % hidden_spine)
    await _variant("04-far-16m-no-spine", Vector3(0.0, 9.0, 16.0), Vector3(0.0, 1.2, 0.0), 62.0)

    # 再去掉洞窟围合墙体，测试“开放大空间”
    var hidden_cave: int = _hide_matching(["Cave_BackWall", "Cave_LeftWall", "Cave_RightWall", "Cave_Rib", "Cave_Buttress", "Cave_BackStrata"])
    print("hidden cave nodes: %d" % hidden_cave)
    await _variant("05-far-16m-open-cavern", Vector3(0.0, 9.0, 16.0), Vector3(0.0, 1.2, 0.0), 62.0)

    # 远景大场面：30m 高、55m 外
    await _variant("06-vista-55m", Vector3(0.0, 30.0, 55.0), Vector3(14.0, 2.0, -10.0), 58.0)

    # 反应堆一侧同样对比
    await _place(Vector3(55.0, 0.0, -17.0))
    _set_hud_visible(false)
    player.set_process(false)
    await _variant("07-reactor-far-22m", Vector3(0.0, 12.0, 22.0), Vector3(0.0, 2.0, 0.0), 62.0)

    # 中层观景桥：玩家站上桥面后的真实视角（朝东看向反应堆）
    _show_all()
    var bridge_player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    bridge_player._camera_yaw = -PI * 0.5
    bridge_player._camera_yaw_target = bridge_player._camera_yaw
    await _place(Vector3(-20.0, 6.6, -12.0))
    _set_hud_visible(false)
    await _shot("08-observation-bridge")
    bridge_player._camera_yaw = PI * 0.5
    bridge_player._camera_yaw_target = bridge_player._camera_yaw
    await _place(Vector3(-4.0, 6.6, -12.0))
    await _shot("09-observation-bridge-west")
    # 高位竖井观察台：面向东侧洞口，检查单侧开口与远景山脊
    bridge_player._camera_yaw = -PI * 0.5
    bridge_player._camera_yaw_target = bridge_player._camera_yaw
    await _place(Vector3(70.0, 12.0, -26.0))
    await _shot("10-shaft-deck")
    # 登高入口：站在落地检修平台上面向坡道，检查路线是否一眼可读
    bridge_player._camera_yaw = -PI * 0.5
    bridge_player._camera_yaw_target = bridge_player._camera_yaw
    await _place(Vector3(-46.0, 0.6, -12.0))
    await _shot("11-bridge-entrance")

    var report: FileAccess = FileAccess.open(output_dir.path_join("space-probe-report.json"), FileAccess.WRITE)
    if report != null:
        report.store_string(JSON.stringify({
            "failures": failures,
            "hidden_spine_nodes": hidden_spine,
            "hidden_cave_nodes": hidden_cave,
            "master_mesh_count": stage.world_root.find_children("*", "MeshInstance3D", true, false).size(),
            "fade_removed": not ("camera_fade_cache" in stage),
            "bridge_collision": stage.world_root.get_node_or_null("ResonanceObservationBridgeCollision") != null,
            "tower_size": _aabb_size(stage.art_asset_nodes.get("ArtReactorTower") as Node3D),
            "player_position": main.players[1].global_position,
            "camera_position": (main.players[1] as SpacePlayer3D)._camera.global_position
        }, "  "))
        report.close()
    else:
        failures += 1
    print("SPACE_PROBE: 7 images, %d failures" % failures)
    quit(0 if failures == 0 else 1)
