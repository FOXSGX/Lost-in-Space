extends SceneTree

## Continuous cave chapter integration checks.
## This test targets the new chapter controller and does not reinterpret the
## legacy factory tests as evidence for the cave slice.

var checks := 0
var failures: Array[String] = []
var g_main: Main3D
var g_stage: ResonanceCaveChapter3D

func _initialize() -> void:
    call_deferred("run_test")

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        push_error(message)

func run_test() -> void:
    print("CAVE_CHAPTER: start")
    var main_scene := ResourceLoader.load("res://scenes/main_3d.tscn") as PackedScene
    check(main_scene != null, "main_3d.tscn 加载失败")
    if main_scene == null:
        _finish()
        return
    var main := main_scene.instantiate() as Main3D
    check(main != null, "Main3D 实例化失败")
    if main == null:
        _finish()
        return
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    var host_created := false
    var port_seed := 30000 + int(Time.get_ticks_msec() % 4000)
    for offset in 24:
        main.network_port = port_seed + offset
        main._create_host()
        if main.is_host:
            host_created = true
            break
    check(host_created, "测试主机端口创建失败")
    if not host_created:
        _finish()
        return
    main.connected_ids = [1, 2]
    main._start_planet("electromagnetic")
    await process_frame
    await process_frame

    var stage := main._resonance_stage as ResonanceCaveChapter3D
    g_main = main
    g_stage = stage
    check(stage != null, "共振星阶段没有使用 ResonanceCaveChapter3D")
    if stage == null:
        _finish()
        return
    check(stage.cave_visual != null, "Blender 洞穴 GLB 没有实例化")
    if stage.cave_visual != null:
        check(String(stage.cave_visual.get_meta("visual_authority", "")).ends_with("resonance_cave_vertical_slice_v3.glb"), "运行时没有使用坐标修正后的 v3 GLB")
    check(stage.cave_gate_bodies.size() == 2, "连续章节没有两道可控洞门")
    check(stage.cave_collision_bodies.size() >= 10, "洞穴碰撞边界数量不足")
    check(stage.get_active_map_size().x >= 180.0, "地图宽度不足以覆盖第二洞厅出口")
    check(stage.cave_feedback != null, "六个洞穴机关没有创建运行时反馈层")
    var mechanism_kinds: Array[String] = [
        "power", "clamp", "relay_entry", "relay_exit", "freight", "stabilizer"
    ]
    if stage.cave_feedback != null:
        stage.cave_feedback.reset_all()
        check(stage.cave_feedback.mechanism_count() == 6, "机关反馈节点数量不是 6：%d" % stage.cave_feedback.mechanism_count())
        check(stage.cave_feedback.gate_count() == 2, "洞门反馈代理数量不是 2")
        for kind in mechanism_kinds:
            check(stage.cave_feedback.has_mechanism(kind), "缺少机关反馈：%s" % kind)
            check(stage.cave_feedback.get_state(kind) == stage.cave_feedback.STATE_IDLE, "机关 %s 初始状态不是 IDLE" % kind)
    check(stage.cave_art != null, "洞穴美术指导层没有创建")
    if stage.cave_art != null:
        check(stage.cave_art.family_count() >= 8, "洞穴材质家族不足：%d" % stage.cave_art.family_count())
        check(stage.cave_art.light_count() >= 15, "洞穴灯光节点不足：%d" % stage.cave_art.light_count())
        check(int(stage.cave_art.material_families.get("rock", 0)) >= 30, "主岩体没有应用分层材质")
        check(int(stage.cave_art.material_families.get("crystal_cyan", 0)) >= 20, "青色晶体没有应用晶体材质")
        check(int(stage.cave_art.material_families.get("floor", 0)) >= 2, "地面没有应用地面材质")
        check(int(stage.cave_art.material_families.get("metal_teal", 0)) >= 1, "机械轨道没有应用金属材质")
        check(stage.cave_art.environment != null and stage.cave_art.environment.fog_enabled, "洞穴环境缺少纵深雾")
        check(stage.cave_art.environment.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "洞穴环境没有电影化色调映射")
        check(stage.cave_art.fade_meshes.size() >= 20, "相机遮挡层没有覆盖任务装置/拱门")
    if stage.cave_feedback != null:
        check(stage.cave_feedback.world_props.size() >= 10, "机关没有绑定 GLB 本体动作节点")

    var space := main.get_world_3d().direct_space_state
    for segment in [[-12.0, 12.0], [16.0, 48.0], [52.0, 86.0]]:
        var route_query := PhysicsRayQueryParameters3D.create(Vector3(float(segment[0]), 1.0, 0.0), Vector3(float(segment[1]), 1.0, 0.0))
        route_query.collision_mask = 2
        check(space.intersect_ray(route_query).is_empty(), "主路线中心被侧壁或碰撞体挡住：%s" % [segment])
    for x in [-8.0, 30.0, 70.0, 84.0]:
        var floor_query := PhysicsRayQueryParameters3D.create(Vector3(x, 3.0, 0.0), Vector3(x, -2.0, 0.0))
        floor_query.collision_mask = 2
        check(not space.intersect_ray(floor_query).is_empty(), "主路线没有稳定地面：x=%s" % x)

    var required_anchors := [
        "RES_Entrance", "RES_Respawn01", "RES_Task01_Power", "RES_Task01_Clamp",
        "RES_Transition01_MineGate", "RES_Chamber01_Camera", "RES_Tunnel01_Entry",
        "RES_Tunnel01_Exit", "RES_Tunnel01_Camera", "RES_Chamber02_Entry",
        "RES_Task02_Freight", "RES_Task02_StableSocket", "RES_Respawn02",
        "RES_Chamber02_Camera", "RES_Exit"
    ]
    var missing: Array[String] = []
    for anchor_name in required_anchors:
        if stage.cave_visual == null or stage.cave_visual.find_child(anchor_name, true, false) == null:
            missing.append(anchor_name)
    check(missing.is_empty(), "缺少 RES_ 锚点：%s" % [missing])

    check(main.players.size() >= 2, "测试主机没有生成两名玩家")
    var player_one := main.players.get(1) as SpacePlayer3D
    var player_two := main.players.get(2) as SpacePlayer3D
    check(player_one != null and player_two != null, "两名玩家对象不存在")
    if player_one != null:
        check(absf(wrapf(player_one.rotation.y + PI * 0.5, -PI, PI)) < 0.12, "入口出生镜头没有朝向 +X 主路线")
        var clamped_camera := player_one._clamp_resonance_camera(Vector3(-40.0, 8.0, 0.0))
        check(clamped_camera.x >= -17.01, "入口镜头仍能退到洞口外")
    if player_one == null or player_two == null:
        _finish()
        return

    # Camera follow regression probe: moving the local player across the
    # entrance must move its actual runtime Camera3D, rather than leaving the
    # camera pinned to the room clamp.
    check(player_one._camera != null, "本地玩家没有创建第三人称相机")
    if player_one._camera != null:
        await process_frame
        await process_frame
        var camera_before := player_one._camera.global_position
        player_one.teleport_to(Vector3(-8.0, 0.1, 0.0))
        for _frame in 18:
            await process_frame
        camera_before = player_one._camera.global_position
        player_one.teleport_to(Vector3(7.0, 0.1, 0.0))
        for _frame in 24:
            await process_frame
        var camera_after := player_one._camera.global_position
        var camera_delta := camera_after - camera_before
        print("CAVE_CAMERA_PROBE: player_delta=15 camera_delta=%s before=%s after=%s" % [camera_delta, camera_before, camera_after])
        check(camera_delta.x > 4.0, "玩家向前移动后相机没有跟随：%s" % [camera_delta])
        check(camera_after.distance_to(player_one.global_position + Vector3(0.0, 0.9, 0.0)) >= 8.0, "相机被拉到玩家身上")

    # Extended acceptance: cave_room is a task phase, not a camera boundary.
    # The camera must keep following through the corridor/chamber and settle
    # on the current player target within 0.3-0.5 s.
    if player_one._camera != null:
        player_one.set_physics_process(false)
        player_two.set_physics_process(false)
        _configure_camera_probe(player_one)
        await create_timer(0.45).timeout
        _check_camera_after_move(player_one, "入口")

        stage.cave_room = 1
        player_one.global_position = Vector3(5.0, 0.1, 0.0)
        await create_timer(0.45).timeout
        var phase_camera := player_one._camera.global_position
        print("CAVE_CAMERA_PHASE: cave_room=1 player_x=5 camera=%s" % [phase_camera])
        check(phase_camera.x < 15.0, "cave_room=1 把入口镜头拉到回廊：%s" % [phase_camera])

        var corridor_start := Vector3(30.0, 0.1, 0.0)
        player_one.global_position = corridor_start
        await create_timer(0.45).timeout
        var corridor_before := player_one._camera.global_position
        _configure_camera_probe(player_one)
        for step in 30:
            var corridor_ratio := float(step + 1) / 30.0
            player_one.global_position = Vector3(lerpf(corridor_start.x, 48.0, corridor_ratio), 0.1, 0.0)
            await process_frame
        await create_timer(0.45).timeout
        var corridor_after := player_one._camera.global_position
        var corridor_delta := corridor_after - corridor_before
        print("CAVE_CAMERA_CORRIDOR: before=%s after=%s delta=%s" % [corridor_before, corridor_after, corridor_delta])
        check(corridor_before.x < 24.0, "回廊入口相机仍被硬钳在旧 x=26：%s" % [corridor_before])
        check(corridor_delta.x > 8.0, "回廊内相机没有连续跟随：%s" % [corridor_delta])
        check(corridor_after.x > 30.0, "回廊相机没有越过旧边界：%s" % [corridor_after])
        _check_camera_after_move(player_one, "回廊")
        var tunnel_camera_clamp := player_one._clamp_resonance_camera(Vector3(33.0, 30.0, 30.0))
        check(tunnel_camera_clamp.y < 6.0, "回廊相机没有被洞顶限制：%s" % [tunnel_camera_clamp])
        check(absf(tunnel_camera_clamp.z) < 5.0, "回廊相机没有被侧壁限制：%s" % [tunnel_camera_clamp])

        stage.cave_room = 2
        # In real progression task two is complete and the corridor gate is
        # open when the players reach this chamber.  Set that state for the
        # camera probe, then restore it so the later task-flow checks still
        # observe task two as pending.
        stage.cave_task_two_done = true
        stage._set_cave_gate_open(1, true)
        player_one.global_position = Vector3(62.0, 0.1, 0.0)
        await create_timer(0.45).timeout
        var chamber_before := player_one._camera.global_position
        _configure_camera_probe(player_one)
        for step in 30:
            var chamber_ratio := float(step + 1) / 30.0
            player_one.global_position = Vector3(lerpf(62.0, 80.0, chamber_ratio), 0.1, 0.0)
            await process_frame
        await create_timer(0.45).timeout
        var chamber_after := player_one._camera.global_position
        var chamber_delta := chamber_after - chamber_before
        print("CAVE_CAMERA_CHAMBER: before=%s after=%s delta=%s" % [chamber_before, chamber_after, chamber_delta])
        check(chamber_before.x < 50.0, "晶体洞厅入口相机被旧边界拉到 x=52：%s" % [chamber_before])
        check(chamber_delta.x > 8.0, "晶体洞厅相机没有连续跟随：%s" % [chamber_delta])
        _check_camera_after_move(player_one, "晶体洞厅")
        stage.cave_task_two_done = false
        stage._set_cave_gate_open(1, false)

        stage.cave_room = 0
        player_one.global_position = Vector3(-8.0, 0.1, 0.0)
        player_two.global_position = Vector3(-5.0, 0.1, 2.2)

    if stage.cave_feedback != null:
        stage.cave_feedback.reset_all()
        stage.cave_gate_opening = [false, false]

    player_one.global_position = ResonanceCaveChapter3D.CAVE_POWER_POSITION
    player_two.global_position = ResonanceCaveChapter3D.CAVE_CLAMP_POSITION
    stage.handle_stage_action(1, "repair", 1)
    check(stage.cave_power_peer == 1, "青色供能端没有记录触发玩家")
    if stage.cave_feedback != null:
        check(stage.cave_feedback.get_state("power") == stage.cave_feedback.STATE_ACTIVATING or stage.cave_feedback.get_state("power") == stage.cave_feedback.STATE_ARMED, "青色供能端触发后没有进入 ACTIVATING/ARMED")
        check(stage.cave_feedback.activation_count >= 1, "青色供能端没有产生触发反馈事件")
        check(not stage.cave_feedback.last_event.is_empty(), "青色供能端没有可检测的反馈元数据")
        var first_activation_count: int = int(stage.cave_feedback.activation_count)
        var first_mechanism_count: int = int(stage.cave_feedback.mechanism_count())
        stage.handle_stage_action(1, "repair", 1)
        check(stage.cave_feedback.activation_count == first_activation_count, "重复按 E 重复注册了青色供能端")
        check(stage.cave_feedback.mechanism_count() == first_mechanism_count, "重复按 E 重复生成了反馈节点")
        await create_timer(0.45).timeout
        check(stage.cave_feedback.get_state("power") == stage.cave_feedback.STATE_ARMED, "青色供能端触发动画没有落到 ARMED")
    stage.handle_stage_action(2, "repair", 2)
    check(stage.cave_task_one_done, "入口双端锁止没有完成")
    if stage.cave_feedback != null:
        check(stage.cave_feedback.get_state("power") == stage.cave_feedback.STATE_COMPLETED, "入口完成后青色供能端不是 COMPLETED")
        check(stage.cave_feedback.get_state("clamp") == stage.cave_feedback.STATE_COMPLETED, "入口完成后琥珀色夹具不是 COMPLETED")
        check(stage.cave_feedback.completion_count >= 2, "入口完成没有两端同时播放完成脉冲")
        check(stage.cave_feedback.gate_is_opening(0), "第一道洞门没有进入开启动画")
    check(stage.cave_gate_opening[0], "第一道洞门开启状态没有记录")
    check(stage.cave_gate_bodies[0].collision_layer != 0, "第一道洞门碰撞在动画开始前就消失了")
    await create_timer(0.75).timeout
    check(stage.cave_gate_bodies[0].collision_layer == 0, "第一道洞门动画没有随后关闭碰撞")
    if stage.cave_feedback != null:
        check(stage.cave_feedback.gate_curtain_scale(0) < 0.8, "第一道洞门视觉门幕没有播放开启动画")
        check(stage.cave_cart_x > 24.0, "矿脉车轨移动目标没有移动")
        check(stage.cave_feedback.cart_marker.visible, "矿脉车轨移动目标没有显示")
        var first_flow_count: int = int(stage.cave_feedback.flow_count)
        stage.cave_feedback.play_task_complete(1, {"power": 1, "clamp": 2})
        check(stage.cave_feedback.flow_count == first_flow_count, "重复任务事件重复播放了完成能量流")

    player_one.global_position = ResonanceCaveChapter3D.CAVE_RELAY_ENTRY_POSITION
    player_two.global_position = ResonanceCaveChapter3D.CAVE_RELAY_EXIT_POSITION
    stage.handle_stage_action(1, "repair", 3)
    stage.handle_stage_action(2, "repair", 4)
    check(stage.cave_task_two_done, "矿脉回廊双端中继没有完成")
    if stage.cave_feedback != null:
        check(stage.cave_feedback.get_state("relay_entry") == stage.cave_feedback.STATE_COMPLETED, "回廊完成后入口中继不是 COMPLETED")
        check(stage.cave_feedback.get_state("relay_exit") == stage.cave_feedback.STATE_COMPLETED, "回廊完成后出口中继不是 COMPLETED")
        check(stage.cave_feedback.gate_is_opening(1), "第二道洞门没有进入开启动画")
    check(stage.cave_gate_opening[1], "第二道洞门开启状态没有记录")
    check(stage.cave_gate_bodies[1].collision_layer != 0, "第二道洞门碰撞在动画开始前就消失了")
    await create_timer(0.75).timeout
    check(stage.cave_gate_bodies[1].collision_layer == 0, "第二道洞门动画没有随后关闭碰撞")

    player_one.global_position = ResonanceCaveChapter3D.CAVE_FREIGHT_POSITION
    player_two.global_position = ResonanceCaveChapter3D.CAVE_STABILIZER_POSITION
    for press in 3:
        stage.handle_stage_action(1, "repair", 5)
    for press in 4:
        stage.handle_stage_action(2, "repair", 6)
    check(stage.cave_task_three_done, "晶体洞厅交替校准没有完成")
    check(stage.cave_evacuation_started, "晶体洞厅完成后没有进入崩塌撤离段")
    if stage.cave_feedback != null:
        check(stage.cave_feedback.get_state("freight") == stage.cave_feedback.STATE_COMPLETED, "晶体洞厅完成后货箱位不是 COMPLETED")
        check(stage.cave_feedback.get_state("stabilizer") == stage.cave_feedback.STATE_COMPLETED, "晶体洞厅完成后绿色接收座不是 COMPLETED")
        check(stage.cave_feedback.flow_count >= 3, "三段任务没有产生各自的任务完成能量流")
        check(stage.cave_feedback.tool_action_count >= 4, "导能/钩索工具触发没有产生独立反馈")
        check(stage.cave_feedback.evacuation_count >= 1, "崩塌撤离段没有播放视觉事件")
    stage.apply_stage_snapshot(stage.stage_snapshot())
    if stage.cave_feedback != null:
        check(stage.cave_feedback.get_state("freight") == stage.cave_feedback.STATE_COMPLETED, "快照恢复后货箱位状态丢失")
        check(stage.cave_feedback.get_state("stabilizer") == stage.cave_feedback.STATE_COMPLETED, "快照恢复后绿色接收座状态丢失")
        check(stage.cave_feedback.get_state("power") == stage.cave_feedback.STATE_COMPLETED, "快照恢复后入口机关状态丢失")
        check(stage.cave_feedback.mechanism_count() == 6, "快照恢复重复注册了反馈节点")

    player_one.set_physics_process(false)
    player_one.teleport_to(Vector3(-12.0, 0.1, 0.0))
    check(_walk_route(player_one, Vector3(12.0, 0.1, 0.0)), "入口洞厅主路线移动被阻挡")
    check(_walk_route(player_one, Vector3(48.0, 0.1, 0.0)), "矿脉回廊主路线移动被阻挡")
    check(_walk_route(player_one, Vector3(86.0, 0.1, 0.0)), "晶体洞厅主路线移动被阻挡")

    player_one.global_position = ResonanceCaveChapter3D.CAVE_EXIT_POSITION
    player_two.global_position = ResonanceCaveChapter3D.CAVE_EXIT_POSITION + Vector3(0.0, 0.0, 2.0)
    stage.stage_tick(0.3)
    check(stage.cave_chapter_complete, "两名玩家到达出口后章节没有完成")
    var snapshot := stage.stage_snapshot()
    check(bool(snapshot.get("cave_task_three_done", false)), "章节快照没有保存最终任务状态")

    # 1–4 player capability modes. Spawn all four kit carriers once, then
    # switch connected_ids/tools and rebuild the cave for each scenario.
    main.spawn_player_for_peer(3)
    main.spawn_player_for_peer(4)
    await process_frame
    main.set_process(false)

    _run_mode(1, ["conduit"])
    check(stage.cave_chapter_complete, "1 人仅用 conduit 无法完整通关")
    check(int(stage.cave_tool_usage.get("conduit", 0)) >= 2, "1 人路径没有记录 conduit 工具贡献")
    check(int(stage.cave_feedback.manual_pulse_count) > 0, "1 人缺少 hook/scanner 时没有走应急操作")

    _run_mode(2, ["conduit", "hook"])
    check(stage.cave_chapter_complete, "2 人 conduit + hook 无法完整通关")
    check(int(stage.cave_tool_usage.get("conduit", 0)) >= 2, "2 人路径没有 conduit 贡献")
    check(int(stage.cave_tool_usage.get("hook", 0)) >= 2, "2 人路径没有 hook 贡献")

    _prepare_mode(3, ["conduit", "hook", "scanner"])
    check(stage._objective_enabled("scan_route"), "3 人 scanner 模式没有启用额外并行任务 scan_route")
    _act_at(1, "power")
    _act_at(2, "clamp")
    check(stage.cave_task_one_done, "3 人入口任务没有完成")
    _act_at(3, "scan_route")
    check(stage.cave_scan_route_done, "3 人 scanner 额外并行任务没有完成")
    check(String(stage.cave_feedback.last_tool_action.get("tool", "")) == "scanner", "scanner 触发没有记录独立工具反馈")
    _act_at(1, "relay_entry")
    _act_at(2, "relay_exit")
    check(stage.cave_task_two_done, "3 人回廊任务没有完成")
    _act_at(2, "freight")
    _act_at(3, "stabilizer")
    _finish_mode()
    check(stage.cave_chapter_complete, "3 人 scanner 队伍无法完整通关")

    _prepare_mode(3, ["conduit", "hook", "scanner"])
    _act_at(1, "power")
    _act_at(2, "clamp")
    _act_at(1, "relay_entry")
    _act_at(2, "relay_exit")
    check(stage.cave_task_two_done, "3 人核心回廊任务未完成")
    check(not stage.cave_scan_route_done, "3 人扫描并行任务不应阻塞核心回廊")

    _run_mode(4, ["conduit", "hook", "scanner", "shield"])
    check(stage.cave_chapter_complete, "4 人四工具队伍无法完整通关")
    check(stage.cave_shield_window_done, "4 人 shield 安全窗口没有贡献")
    check(stage.cave_energy_aligned, "4 人 conduit 能量方向没有贡献")
    check(stage.cave_aux_peer.has("shield_route"), "4 人 shield 没有回廊安全区任务")
    check(stage.cave_aux_peer.has("shield_calibration"), "4 人 shield 没有洞厅安全区任务")
    for tool in ["conduit", "hook", "scanner", "shield"]:
        check(int(stage.cave_tool_usage.get(tool, 0)) >= 1, "4 人模式工具 %s 没有实际作用" % tool)

    _prepare_mode(4, ["conduit", "hook", "scanner", "shield"])
    _act_at(4, "shield_window")
    check(String(stage.cave_feedback.last_tool_action.get("tool", "")) == "shield", "shield 触发没有独立护盾反馈")
    _act_at(1, "power")
    check(String(stage.cave_feedback.last_tool_action.get("tool", "")) == "conduit", "conduit 触发没有独立能量束反馈")
    _act_at(2, "clamp")
    check(String(stage.cave_feedback.last_tool_action.get("tool", "")) == "hook", "hook 触发没有独立连接线/拉动反馈")
    _act_at(3, "scan_route")
    check(String(stage.cave_feedback.last_tool_action.get("tool", "")) == "scanner", "scanner 触发没有独立扫描波/隐藏路线反馈")
    check(int(stage.cave_feedback.tool_action_count) >= 4, "四种工具没有产生四种独立反馈事件")

    _run_mode(2, ["conduit", "conduit"])
    check(stage.cave_chapter_complete, "缺少 hook/scanner 时替代路线无法完成")
    check(int(stage.cave_feedback.manual_pulse_count) > 0, "缺少工具时没有记录应急操作反馈")

    _run_mode(1, ["conduit"], true)
    check(stage.cave_chapter_complete, "单人无人机补位路线无法完整通关")
    check(int(stage.cave_tool_usage.get("drone", 0)) >= 4, "单人无人机没有代理缺失能力")

    _prepare_mode(2, ["conduit", "hook"])
    _act_at(1, "power")
    _act_at(2, "clamp")
    var downed_partner := main.players.get(2) as SpacePlayer3D
    downed_partner.downed = true
    check(stage._active_peer_ids().size() == 1, "倒地玩家仍被计入活跃队伍")
    check(stage.get_stage_action_target(2, "repair").is_empty(), "倒地玩家仍能触发机关")
    check(stage.cave_task_one_done and stage.cave_clamp_peer == 2, "倒地后已完成的机关状态丢失")
    downed_partner.downed = false

    _prepare_mode(2, ["conduit", "hook"])
    _act_at(1, "power")
    _act_at(2, "clamp")
    check(stage.cave_task_one_done, "掉线测试前入口任务未完成")
    main.connected_ids.erase(2)
    main.players.erase(2)
    _act_at(1, "relay_entry")
    _act_at(1, "relay_exit", 3)
    _act_at(1, "freight", 3)
    _act_at(1, "stabilizer", 4)
    _finish_mode()
    check(stage.cave_chapter_complete, "队友掉线后剩余玩家无法完成任务")
    check(stage.cave_clamp_peer == 2 and stage.cave_task_one_done, "掉线后已完成的机关状态丢失")

    print("CAVE_CHAPTER: %d checks, %d failures" % [checks, failures.size()])
    _finish()

func _prepare_mode(mode: int, tools: Array) -> void:
    var ids: Array = []
    for peer_id in range(1, mode + 1):
        ids.append(peer_id)
    g_main.connected_ids.clear()
    for peer_id in ids:
        g_main.connected_ids.append(peer_id)
    for peer_id in [1, 2, 3, 4]:
        var player := g_main.players.get(peer_id) as SpacePlayer3D
        if player == null:
            continue
        player.downed = false
        player.lava_dead = false
        player.set_physics_process(false)
        if peer_id <= mode and peer_id <= tools.size():
            var tool: String = tools[peer_id - 1]
            g_main.kit_assignments[peer_id] = tool
            player.set_tool(tool)
        else:
            g_main.kit_assignments.erase(peer_id)
            player.set_tool("")
    g_stage.drone_state["active"] = false
    g_stage.drone_state["remaining"] = 0.0
    g_stage.drone_state["target"] = ""
    g_stage.start_stage()
    if g_stage.cave_feedback != null:
        g_stage.cave_feedback.reset_all()
    g_main.set_process(false)

func _deploy_drone() -> void:
    var player := g_main.players.get(1) as SpacePlayer3D
    if player == null:
        return
    g_stage.drone_state["active"] = false
    g_stage.drone_state["remaining"] = 0.0
    g_stage.drone_state["target"] = ""
    g_stage._toggle_drone(1, player)
    if not bool(g_stage.drone_state["active"]):
        g_stage.drone_state["active"] = true
        g_stage.drone_state["owner"] = 1
    g_stage.drone_state["remaining"] = 12.0
    g_stage.drone_state["target"] = ""

func _act_at(peer_id: int, kind: String, presses: int = 1) -> void:
    var player := g_main.players.get(peer_id) as SpacePlayer3D
    if player == null:
        return
    player.global_position = g_stage._objective_position(kind)
    for index in presses:
        g_stage.handle_stage_action(peer_id, "repair", 0)

func _finish_mode() -> void:
    var active: Array = g_stage._active_peer_ids()
    for index in active.size():
        var peer_id: int = int(active[index])
        var player := g_main.players.get(peer_id) as SpacePlayer3D
        if player != null:
            player.global_position = g_stage.CAVE_EXIT_POSITION + Vector3(0.0, 0.0, float(index) * 1.5)
    g_stage._check_cave_exit()

func _run_mode(mode: int, tools: Array, use_drone: bool = false) -> void:
    _prepare_mode(mode, tools)
    if use_drone:
        _deploy_drone()
    if mode >= 4 and tools.size() >= 4 and tools[3] == "shield":
        _act_at(4, "shield_window")
    _act_at(1, "power")
    if tools.size() >= 2 and tools[1] == "hook":
        _act_at(2, "clamp")
    else:
        _act_at(1, "clamp", 3)
    _act_at(1, "relay_entry")
    if mode >= 4 and tools.size() >= 4 and tools[3] == "shield":
        _act_at(4, "shield_route")
    if tools.size() >= 2 and tools[1] == "hook":
        _act_at(2, "relay_exit")
    else:
        _act_at(1, "relay_exit", 3)
    if mode >= 3 and tools.size() >= 3 and tools[2] == "scanner":
        _act_at(3, "scan_route")
    if mode >= 4 and tools.size() >= 1 and tools[0] == "conduit":
        _act_at(1, "energy_align")
    if mode >= 4 and tools.size() >= 4 and tools[3] == "shield":
        _act_at(4, "shield_calibration")
    if tools.size() >= 2 and tools[1] == "hook":
        _act_at(2, "freight")
    else:
        _act_at(1, "freight", 3)
    if mode >= 3 and tools.size() >= 3 and tools[2] == "scanner":
        _act_at(3, "stabilizer")
    else:
        _act_at(1, "stabilizer", 4)
    _finish_mode()

func _finish() -> void:
    quit(0 if failures.is_empty() else 1)

func _configure_camera_probe(player: SpacePlayer3D) -> void:
    player.rotation.y = -PI * 0.5
    player._camera_yaw = -PI * 0.5
    player._camera_yaw_target = -PI * 0.5
    player._camera_pitch = -0.18
    player._camera_pitch_target = -0.18

func _check_camera_after_move(player: SpacePlayer3D, label: String) -> void:
    if player._camera == null:
        check(false, "%s没有 Camera3D" % label)
        return
    var target := player.global_position + Vector3(0.0, 0.9, 0.0)
    var camera_position := player._camera.global_position
    var desired := player._clamp_resonance_camera(player._third_person_camera_position(target))
    var error := camera_position.distance_to(desired)
    var follow_distance := camera_position.distance_to(target)
    var forward := -player._camera.global_transform.basis.z
    var to_target := (target - camera_position).normalized()
    print("CAVE_CAMERA_%s: distance=%.2f error=%.3f look=%.4f" % [label, follow_distance, error, forward.dot(to_target)])
    check(error < 0.7, "%s相机 0.4 秒后没有收敛到目标位置：%.2f" % [label, error])
    check(follow_distance >= 11.0 and follow_distance <= 18.0, "%s相机距离异常：%.2f" % [label, follow_distance])
    check(forward.dot(to_target) > 0.995, "%s相机没有持续看向玩家" % label)

func _walk_route(player: SpacePlayer3D, target: Vector3) -> bool:
    for _step in 500:
        var delta := target - player.global_position
        delta.y = 0.0
        if delta.length() <= 0.16:
            player.global_position = target
            return true
        var motion := delta.normalized() * minf(delta.length(), 0.16)
        var collision := player.move_and_collide(motion)
        if collision != null:
            return false
    return false
