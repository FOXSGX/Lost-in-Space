extends SceneTree

## 只读截图：四名角色各自拿着专属工具，以及护盾展开的样子。

var output_dir: String = ""

func _initialize() -> void:
    run.call_deferred()

func _shot(label: String) -> void:
    for _frame in 3:
        await process_frame
    var image: Image = root.get_texture().get_image()
    image.resize(960, 540, Image.INTERPOLATE_BILINEAR)
    image.save_png(output_dir.path_join(label + ".png"))

func _camera(main: Main3D, position: Vector3, target: Vector3, fov: float = 45.0) -> Camera3D:
    var camera: Camera3D = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_PERSPECTIVE
    camera.fov = fov
    camera.position = position
    main.add_child(camera)
    camera.look_at(target, Vector3.UP)
    camera.current = true
    return camera

func run() -> void:
    var args: PackedStringArray = OS.get_cmdline_user_args()
    output_dir = String(args[0]) if not args.is_empty() else "C:/Users/ASUS/Desktop/迷失太空/work/gameplay-iterations/20261017-character-kit"
    DirAccess.make_dir_recursive_absolute(output_dir)
    var main: Main3D = load("res://scenes/main_3d.tscn").instantiate() as Main3D
    root.add_child(main)
    await process_frame
    main._ship_session.persistence_enabled = false
    main.network_port = 26010 + int(Time.get_ticks_msec() % 80)
    main._create_host()
    main.connected_ids = [1]
    for peer_id in [2, 3, 4]:
        main.connected_ids.append(peer_id)
        main.spawn_player_for_peer(peer_id)
    main.spawn_player_for_peer(1)
    await process_frame
    main._ship_session.enter_ship(true, [1, 2, 3, 4], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1, 2, 3, 4]
    main._ship_session.select_destination("electromagnetic")
    main._confirm_land()
    await process_frame
    main.set_process(false)
    main.set_physics_process(false)
    # 登陆会清空并重建玩家，确保四人都在场
    for peer_id in [1, 2, 3, 4]:
        if not main.players.has(peer_id):
            main.connected_ids.append(peer_id)
            main.spawn_player_for_peer(peer_id)
    await process_frame
    print("CAPTURE players=%s" % str(main.players.keys()))
    var stage: ResonanceStage3D = main._resonance_stage
    if stage != null:
        stage.set_process(false)
        stage.set_physics_process(false)
    var tools: Array = ["conduit", "hook", "scanner", "shield"]
    for index in 4:
        var peer_id: int = index + 1
        var player: SpacePlayer3D = main.players[peer_id] as SpacePlayer3D
        player.set_physics_process(false)
        main.kit_assignments[peer_id] = tools[index]
        player.set_tool(String(tools[index]))
        player.global_position = Vector3(-50.0 + float(index) * 1.4, 0.4, 20.0)
        player.rotation.y = 0.0
        await process_frame
    var focus: Vector3 = Vector3(-48.0, 1.1, 20.0)
    # 角色正面朝 -Z，机位放在 z 更小的一侧才能看到手里的工具。
    var camera: Camera3D = _camera(main, Vector3(-48.0, 1.5, 24.4), focus, 42.0)
    await _shot("tools-lineup")
    camera.queue_free()
    # 直接对准第一名玩家的工具位置拍近景
    var holder: SpacePlayer3D = main.players[1] as SpacePlayer3D
    if holder != null and holder._visual != null and holder._visual._tool_node != null:
        var tool_pos: Vector3 = holder._visual._tool_node.global_position
        var close_camera: Camera3D = _camera(main, tool_pos + Vector3(1.5, 1.1, -2.1), tool_pos, 50.0)
        await _shot("tool-closeup-conduit")
        close_camera.queue_free()
    # 只显示工具本体，确认模型是否真的渲染出来
    if holder != null and holder._visual != null:
        holder._visual._body.visible = false
        await process_frame
        var only_camera: Camera3D = _camera(main, holder._visual._tool_node.global_position + Vector3(1.1, 0.6, -1.4), holder._visual._tool_node.global_position, 45.0)
        await _shot("tool-only")
        only_camera.queue_free()
        holder._visual._body.visible = true
    var hook_holder: SpacePlayer3D = main.players[2] as SpacePlayer3D
    if hook_holder != null and hook_holder._visual != null and hook_holder._visual._tool_node != null:
        var hook_pos: Vector3 = hook_holder._visual._tool_node.global_position
        var hook_camera: Camera3D = _camera(main, hook_pos + Vector3(1.5, 1.1, -2.1), hook_pos, 50.0)
        await _shot("tool-closeup-hook")
        hook_camera.queue_free()
    if main.players.has(4):
        main.players[4].shield_remaining = 1.0
        var shield_camera: Camera3D = _camera(main, Vector3(-44.6, 1.8, 23.4), Vector3(-45.8, 1.0, 20.0), 42.0)
        await _shot("shield-raised")
        shield_camera.queue_free()
    print("CHARACTER_TOOL_CAPTURE done")
    quit(0)
