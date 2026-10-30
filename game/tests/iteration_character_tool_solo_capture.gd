extends SceneTree

## 单角色三视角：确认背挂工具看得清楚。

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
    main.network_port = 26160 + int(Time.get_ticks_msec() % 80)
    main._create_host()
    main.connected_ids = [1]
    main._ship_session.enter_ship(true, [1], main._ship_session.snapshot())
    main._ship_session.ready_peers = [1]
    main._ship_session.select_destination("electromagnetic")
    main._confirm_land()
    await process_frame
    main.set_process(false)
    main.set_physics_process(false)
    var stage: ResonanceStage3D = main._resonance_stage
    if stage != null:
        stage.set_process(false)
        stage.set_physics_process(false)
    var player: SpacePlayer3D = main.players[1] as SpacePlayer3D
    player.set_physics_process(false)
    var tools: Array = ["conduit", "hook", "scanner", "shield"]
    for index in tools.size():
        var tool: String = String(tools[index])
        main.kit_assignments[1] = tool
        player.set_tool(tool)
        player.global_position = Vector3(-48.0, 0.4, 20.0)
        player.rotation.y = 0.0
        await process_frame
        var back: Camera3D = _camera(main, Vector3(-48.0, 1.7, 22.6), Vector3(-48.0, 1.05, 20.0), 38.0)
        await _shot("tool-%s-back" % tool)
        back.queue_free()
    print("TOOL_SOLO_CAPTURE done")
    quit(0)
